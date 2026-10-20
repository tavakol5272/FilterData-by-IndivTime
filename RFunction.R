library("moveapps")
library("move2")
library("lubridate")

## The parameter "data" is reserved for the data object passed on from the previous app

# Shift timestamps by a duration. Hours/days/weeks are exact lengths; months/years
# are calendar periods (e.g. 15 Jan + 3 months = 15 Apr; 31 Jan + 1 month = 28/29 Feb).
shift_time <- function(t, duration, duration_unit, direction = 1) {
  if (duration_unit %in% c("months", "years")) {
    p <- if (duration_unit == "months") months(duration) else years(duration)
    if (direction > 0) t %m+% p else t %m-% p
  } else {
    t + direction * as.difftime(duration, units = duration_unit)
  }
}

# Parse timestamps from the uploaded table; empty cells become NA, unreadable values stop the App
parse_table_time <- function(x, col) {
  x <- trimws(as.character(x))
  x[x %in% c("", "NA")] <- NA
  out <- suppressWarnings(parse_date_time(x, orders = c("Ymd HMS", "Ymd HM", "Ymd"), tz = "UTC"))
  bad <- !is.na(x) & is.na(out)
  if (any(bad)) {
    stop(paste0("These timestamps in column '", col, "' of your table could not be read: ", paste(x[bad], collapse = ", "),
                ". Please use the format YYYY-MM-DD HH:MM:SS (UTC) or leave the cell empty."))
  }
  out
}

# TRUE for values given as a date only (e.g. 2020-08-29), without a time
is_date_only <- function(x) {
  grepl("^[0-9]{4}[-/.]?[0-9]{1,2}[-/.]?[0-9]{1,2}$", trimws(as.character(x)))
}

# Read the user-uploaded table with one row per track: track ID, start timestamp, end timestamp
read_custom_table <- function(file, track_col, start_col, end_col) {
  tab <- read.csv(file, colClasses = "character", check.names = FALSE)
  needed <- c(track_col, start_col, end_col)
  if (!all(needed %in% names(tab))) {
    stop(paste("Your uploaded table must have the columns:", paste(needed, collapse = ", "), ". Found:", paste(names(tab), collapse = ", ")))
  }
  track_id <- trimws(tab[[track_col]])
  if (any(duplicated(track_id))) {
    stop(paste("Your table must have only one row per track. These track IDs appear more than once:",
               paste(unique(track_id[duplicated(track_id)]), collapse = ", ")))
  }
  data.frame(track_id = track_id,
             start = parse_table_time(tab[[start_col]], start_col),
             end = parse_table_time(tab[[end_col]], end_col),
             start_date_only = is_date_only(tab[[start_col]]),
             end_date_only = is_date_only(tab[[end_col]]))
}

rFunction <- function(data, mode = "first", duration = NULL, duration_unit = "days",
                      start_time = NULL, end_time = NULL,
                      track_col = "track_id", start_col = "start_timestamp", end_col = "end_timestamp",
                      create_table = FALSE, ...) {

  # empty column-name settings fall back to the default names
  if (is.null(track_col) || trimws(track_col) == "") track_col <- "track_id"
  if (is.null(start_col) || trimws(start_col) == "") start_col <- "start_timestamp"
  if (is.null(end_col) || trimws(end_col) == "") end_col <- "end_timestamp"

  ids <- as.character(mt_track_id(data))
  times <- mt_time(data)
  track_ids <- unique(ids)

  # first and last valid timestamp of each track
  valid <- !is.na(times)
  if (any(!valid)) logger.warn(paste(sum(!valid), "locations have no timestamp and are removed from the result."))
  no_time <- setdiff(track_ids, ids[valid])
  if (length(no_time) > 0) logger.warn(paste("These tracks have no valid timestamps and are removed from the result:", paste(no_time, collapse = ", ")))
  track_ids <- setdiff(track_ids, no_time)
  if (length(track_ids) == 0) {
    logger.warn("None of your locations have a valid timestamp. The App returns NULL.")
    return(NULL)
  }
  minT <- as.POSIXct(tapply(as.numeric(times[valid]), ids[valid], min)[track_ids], origin = "1970-01-01", tz = "UTC")
  maxT <- as.POSIXct(tapply(as.numeric(times[valid]), ids[valid], max)[track_ids], origin = "1970-01-01", tz = "UTC")

  # optional editable template table with first/last timestamp per track (from the input data)
  if (isTRUE(create_table)) {
    template <- data.frame(track_ids,
                           format(minT, "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                           format(maxT, "%Y-%m-%d %H:%M:%S", tz = "UTC"))
    names(template) <- c(track_col, start_col, end_col)
    write.csv(template, appArtifactPath("track_time_table.csv"), row.names = FALSE)
    logger.info("The table 'track_time_table.csv' with the first and last timestamp of each track was created. You can edit it and upload it in the 'Custom table' mode.")
  }

  # validate settings
  if (mode %in% c("first", "last")) {
    if (!duration_unit %in% c("hours", "days", "weeks", "months", "years")) {
      stop(paste0("Unknown duration unit '", duration_unit, "'. Allowed are: hours, days, weeks, months, years."))
    }
    if (is.null(duration) || is.na(duration) || duration <= 0) {
      stop("For the modes 'first' and 'last' please provide a duration larger than 0.")
    }
    if (duration_unit %in% c("months", "years") && duration != round(duration)) {
      stop(paste("Calendar", duration_unit, "need a whole number. Please change your duration of", duration, duration_unit, "."))
    }
  }
  if (mode %in% c("from_time", "between")) {
    if (is.null(start_time)) stop("Please provide a start timestamp for this mode.")
    start_time <- as.POSIXct(start_time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
    if (is.na(start_time)) stop("Your start timestamp could not be read. Please check the setting.")
  }
  if (mode %in% c("until_time", "between")) {
    if (is.null(end_time)) stop("Please provide an end timestamp for this mode.")
    end_time <- as.POSIXct(end_time, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC")
    if (is.na(end_time)) stop("Your end timestamp could not be read. Please check the setting.")
  }

  # start (time1) and end (timeN) per track; end_excl marks ends that are excluded
  # (only used for date-only end values in the custom table, see below)
  time1 <- minT
  timeN <- maxT
  end_excl <- rep(FALSE, length(track_ids))
  if (mode == "first") {
    timeN <- shift_time(minT, duration, duration_unit, 1)
    logger.info(paste("Selecting the first", duration, duration_unit, "of each track."))
  } else if (mode == "last") {
    time1 <- shift_time(maxT, duration, duration_unit, -1)
    logger.info(paste("Selecting the last", duration, duration_unit, "of each track."))
  } else if (mode == "from_time") {
    time1[] <- start_time
    logger.info(paste("Selecting all locations from", start_time, "to the end of each track."))
  } else if (mode == "until_time") {
    timeN[] <- end_time
    logger.info(paste("Selecting all locations from the start of each track until", end_time, "."))
  } else if (mode == "between") {
    if (start_time > end_time) {
      logger.warn("Your start timestamp is after your end timestamp. We assume that they were switched and filter the data accordingly.")
      tmp <- start_time; start_time <- end_time; end_time <- tmp
    }
    time1[] <- start_time
    timeN[] <- end_time
    logger.info(paste("Selecting all locations between", start_time, "and", end_time, "."))
  } else if (mode == "custom") {
    file <- getAuxiliaryFilePath("custom_table")
    if (is.null(file)) stop(paste("For the mode 'Custom table' please upload a table (csv) with the columns", track_col, ",", start_col, ",", end_col, "."))
    tab <- read_custom_table(file, track_col, start_col, end_col)

    unknown <- setdiff(tab$track_id, c(track_ids, no_time))
    if (length(unknown) > 0) logger.warn(paste("These track IDs of your table are not in the data and are ignored:", paste(unknown, collapse = ", ")))
    missing <- setdiff(track_ids, tab$track_id)
    if (length(missing) > 0) logger.warn(paste("These tracks are not in your table and are removed from the result:", paste(missing, collapse = ", ")))

    m <- match(track_ids, tab$track_id)
    time1 <- tab$start[m]
    timeN <- tab$end[m]
    start_do <- !is.na(m) & tab$start_date_only[m]
    end_do <- !is.na(m) & tab$end_date_only[m]
    # empty start/end: use the first/last timestamp of the track
    time1[!is.na(m) & is.na(time1)] <- minT[!is.na(m) & is.na(time1)]
    timeN[!is.na(m) & is.na(timeN)] <- maxT[!is.na(m) & is.na(timeN)]

    # a date-only end includes the whole day: it ends just before midnight of the next day
    switched <- which(!is.na(time1) & !is.na(timeN) & time1 > timeN + end_do * 86400)
    if (length(switched) > 0) {
      logger.warn(paste("For these tracks the start timestamp is after the end timestamp. We assume that they were switched and filter accordingly:", paste(track_ids[switched], collapse = ", ")))
      tmp <- time1[switched]; time1[switched] <- timeN[switched]; timeN[switched] <- tmp
      tmp <- start_do[switched]; start_do[switched] <- end_do[switched]; end_do[switched] <- tmp
    }
    timeN[end_do] <- timeN[end_do] + 86400
    end_excl <- end_do
    if (any(end_do)) logger.info("End values given as a date only (e.g. 2020-08-29) include the whole day. Start values given as a date only begin at 00:00:00.")
    logger.info("Selecting the time sections of each track given in your uploaded table.")
  } else {
    stop(paste("Unknown mode:", mode))
  }
  names(time1) <- names(timeN) <- names(end_excl) <- track_ids
  logger.info("Both the start and the end timestamp are included in the selection: start <= timestamp <= end.")

  # keep locations within [time1, timeN] of their track (both ends included),
  # or [time1, timeN) for date-only ends, where timeN is midnight of the following day
  keep <- valid & ids %in% track_ids
  k_ids <- ids[keep]
  k_times <- times[keep]
  keep[keep] <- !is.na(time1[k_ids]) & k_times >= time1[k_ids] &
    ifelse(end_excl[k_ids], k_times < timeN[k_ids], k_times <= timeN[k_ids])

  for (id in track_ids) {
    n_in <- sum(keep[ids == id])
    n_all <- sum(ids == id)
    if (n_in == 0) logger.info(paste("Track", id, ": no locations in the selected time range, the track is removed.")) else
      logger.info(paste("Track", id, ":", n_in, "of", n_all, "locations selected."))
  }

  if (!any(keep)) {
    logger.warn("None of your data lie in the selected time range(s). The App returns NULL.")
    result <- NULL
  } else {
    result <- data[keep, ]
    logger.info(paste("Filtering successful.", nrow(result), "of", nrow(data), "locations of", length(unique(mt_track_id(result))), "track(s) are kept."))
  }

  return(result)
}
