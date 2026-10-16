library('move2')

## Helper: convert start/end values (POSIXct, Date or text) to POSIXct in UTC
## Text can be "YYYY-MM-DD", "YYYY-MM-DD HH:MM" or "YYYY-MM-DD HH:MM:SS(.SSS)"
## Returns the times, a flag for date-only values and a flag for values that could not be read
toUTC <- function(x)
{
  if (inherits(x, "POSIXct")) return(list(time = lubridate::with_tz(x, "UTC"), dateOnly = rep(FALSE, length(x)), bad = rep(FALSE, length(x))))
  if (inherits(x, "Date")) return(list(time = as.POSIXct(format(x), tz = "UTC"), dateOnly = !is.na(x), bad = rep(FALSE, length(x))))
  txt <- trimws(as.character(x))
  time <- lubridate::parse_date_time(txt, orders = c("Ymd HMS", "Ymd HM", "Ymd"), tz = "UTC", quiet = TRUE)
  list(time = time,
       dateOnly = !is.na(time) & grepl("^[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2}$", txt),
       bad = is.na(time) & !is.na(txt) & txt != "")
}

## Helper: warn about start/end values that exist but cannot be read as a time
warnBad <- function(parsed, raw, track, varName)
{
  if (any(parsed$bad)) logger.warn(paste0("These values of '", varName, "' could not be read as a time and are treated as missing (track: value): ",
                                         paste(paste0(track[parsed$bad], ": ", raw[parsed$bad]), collapse = ", "),
                                         ". Use the format YYYY-MM-DD or YYYY-MM-DD HH:MM:SS."))
}

rFunction <- function(data, selName = NULL, startVar = NULL, endVar = NULL, trackVar = NULL, ...)
{
  ids <- as.character(mt_track_id(data))

  if (is.null(selName) || !(selName %in% ids))
  {
    logger.info("Your selection track name (e.g. 'nest') is not set or does not exist in the data. The App returns NULL.")
    return(NULL)
  }

  ## table of time periods = event attributes of the selection track
  selT <- sf::st_drop_geometry(data[ids == selName, ])
  if (is.null(trackVar)) stop(paste0("Please provide the track name variable (the column of the selection track '", selName, "' that holds the track names)."))
  if (!(trackVar %in% names(selT))) stop(paste0("The track name variable '", trackVar, "' does not exist in the selection track '", selName, "'."))

  useStart <- !is.null(startVar) && startVar %in% names(selT)
  useEnd <- !is.null(endVar) && endVar %in% names(selT)
  if (!useStart) logger.info("You have not provided a start time variable name or it does not exist in the selection track. Therefore, each track is filtered by its minimum timestamp.")
  if (!useEnd) logger.info("You have not provided an end time variable name or it does not exist in the selection track. Therefore, each track is filtered by its maximum timestamp.")

  periods <- data.frame(track = as.character(selT[[trackVar]]), stringsAsFactors = FALSE)
  periods$startDateOnly <- FALSE
  periods$endDateOnly <- FALSE
  if (useStart)
  {
    p <- toUTC(selT[[startVar]])
    warnBad(p, selT[[startVar]], periods$track, startVar)
    periods$start <- p$time
    periods$startDateOnly <- p$dateOnly
  }
  if (useEnd)
  {
    p <- toUTC(selT[[endVar]])
    warnBad(p, selT[[endVar]], periods$track, endVar)
    periods$end <- p$time
    periods$endDateOnly <- p$dateOnly
  }

  ## cleaned track names, the same way as Nest Cluster Detection writes them into its nest table
  animalIds <- setdiff(unique(ids), selName)
  cleanIds <- make.names(gsub(" ", "", animalIds))
  names(cleanIds) <- animalIds
  matched <- character()

  times <- mt_time(data)
  keep <- rep(FALSE, nrow(data))
  summ <- data.frame(track = character(), n_input = integer(), n_kept = integer(), status = character(), stringsAsFactors = FALSE)

  for (id in animalIds)
  {
    logger.info(id)
    idx <- which(ids == id)
    ti <- times[idx]
    if (all(is.na(ti)))
    {
      logger.warn(paste0("Track ", id, " has no valid timestamps. All locations of this track are removed from the result."))
      summ[nrow(summ) + 1, ] <- list(id, length(idx), 0L, "removed: no valid timestamps")
      next
    }
    minT <- min(ti, na.rm = TRUE)
    maxT <- max(ti, na.rm = TRUE)

    per <- periods[!is.na(periods$track) & periods$track == id, , drop = FALSE]
    noDataStatus <- "removed: no start/end data"
    if (nrow(per) == 0 && cleanIds[id] != id)
    {
      ## no exact match: try the cleaned track name (only if it is unique)
      if (sum(cleanIds == cleanIds[id]) > 1)
      {
        logger.warn(paste0("Track ", id, " has no exact match, and its cleaned name '", cleanIds[id], "' is not unique in the data. It is not matched."))
        noDataStatus <- "removed: cleaned name not unique"
      } else
      {
        per <- periods[!is.na(periods$track) & periods$track == cleanIds[id], , drop = FALSE]
        if (nrow(per) > 0)
        {
          logger.info(paste0("Matched track '", id, "' using its cleaned name '", cleanIds[id], "'."))
          matched <- c(matched, cleanIds[id])
        }
      }
    }
    if (nrow(per) > 0)
    {
      if (!useStart) per$start <- minT
      if (!useEnd) per$end <- maxT
      per <- per[!is.na(per$start) & !is.na(per$end), , drop = FALSE]
    }

    if (nrow(per) == 0)
    {
      logger.info(paste0("There are no start/end data available for the track ", id, ". Therefore, all locations of this track are removed from the result."))
      summ[nrow(summ) + 1, ] <- list(id, length(idx), 0L, noDataStatus)
      next
    }

    swap <- per$start > per$end
    status <- "filtered"
    if (any(swap))
    {
      s0 <- per$start[swap]
      per$start[swap] <- per$end[swap]
      per$end[swap] <- s0
      d0 <- per$startDateOnly[swap]
      per$startDateOnly[swap] <- per$endDateOnly[swap]
      per$endDateOnly[swap] <- d0
      status <- "filtered (start/end switched)"
      logger.warn(paste0("For track ", id, ", a start timestamp is after its end timestamp. We assume that they were switched and filter the data accordingly."))
    }

    ## keep locations that lie in any of the periods of this track
    ## a date-only end value includes the full end date (until before midnight of the next day)
    inPer <- rep(FALSE, length(idx))
    for (i in seq_len(nrow(per)))
    {
      inEnd <- if (per$endDateOnly[i]) ti < per$end[i] + 86400 else ti <= per$end[i]
      inPer <- inPer | (!is.na(ti) & ti >= per$start[i] & inEnd)
    }

    if (!any(inPer))
    {
      logger.warn(paste0("None of the locations of track ", id, " lie in the requested time range(s). All locations of this track are removed from the result."))
      summ[nrow(summ) + 1, ] <- list(id, length(idx), 0L, "removed: no locations in time range(s)")
    } else
    {
      logger.info(paste("Filtering successful. It found", sum(inPer), "positions of", length(idx), "locations for the track", id, "."))
      keep[idx] <- inPer
      summ[nrow(summ) + 1, ] <- list(id, length(idx), sum(inPer), status)
    }
  }

  ## summary of what happened to each animal
  summ[nrow(summ) + 1, ] <- list(selName, sum(ids == selName), 0L, "removed: selection track")
  logger.info(paste0("Summary per track:\n", paste(utils::capture.output(print(summ, row.names = FALSE)), collapse = "\n")))
  logger.info(paste0("In total ", sum(keep), " of ", sum(ids != selName), " animal locations and ", sum(summ$n_kept > 0), " of ", length(animalIds), " animal tracks are kept."))
  notFound <- setdiff(unique(stats::na.omit(periods$track)), c(ids, matched))
  if (length(notFound) > 0) logger.warn(paste0("These track names in the selection track do not exist in the data and were ignored: ", paste(notFound, collapse = ", ")))

  if (!any(keep))
  {
    logger.warn("No locations remain after filtering. The App returns NULL.")
    return(NULL)
  }

  result <- data[keep, ]
  return(result)
}
