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

# Accepted timestamp formats of the uploaded table (all in UTC; time and seconds are optional):
#  - year first:                2014-08-03T02:01:23Z (recommended, ISO 8601 as used by MoveApps), 2014-08-03 02:01:23,
#                                also with "/" or "." between the date parts
#  - month/day/year (Excel):    8/3/2014 2:01, 8/3/2014 2:01:23, 8/3/2014 2:01 AM
#  - day.month.year (Excel):    03.08.2014 02:01
# Years must have 4 digits. Returns the time and its precision ("day", "minute", "second"),
# or type "bad"/"dmy_slash" for values that cannot be read safely.
parse_one_time <- function(v) {
  time_part <- "(?:[ T]+([0-9]{1,2}):([0-9]{2})(?::([0-9]{2}(?:\\.[0-9]+)?))?)?"
  m <- regmatches(v, regexec(paste0("^([0-9]{4})[-/.]([0-9]{1,2})[-/.]([0-9]{1,2})", time_part, "Z?$"), v, perl = TRUE))[[1]]
  if (length(m) > 0) {
    p <- list(y = m[2], mo = m[3], d = m[4], H = m[5], M = m[6], S = m[7], ap = "", type = "ymd")
  } else {
    m <- regmatches(v, regexec(paste0("^([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})", time_part, "(?:\\s*([AaPp][Mm]))?$"), v, perl = TRUE))[[1]]
    if (length(m) > 0) {
      p <- list(y = m[4], mo = m[2], d = m[3], H = m[5], M = m[6], S = m[7], ap = m[8], type = "mdy")
    } else {
      m <- regmatches(v, regexec(paste0("^([0-9]{1,2})\\.([0-9]{1,2})\\.([0-9]{4})", time_part, "$"), v, perl = TRUE))[[1]]
      if (length(m) == 0) return(list(time = NA, unit = NA, type = "bad"))
      p <- list(y = m[4], mo = m[3], d = m[2], H = m[5], M = m[6], S = m[7], ap = "", type = "dmy")
    }
  }
  p[is.na(p)] <- ""  # optional parts that were not given
  num <- function(s) if (s == "") 0 else as.numeric(s)
  mo <- num(p$mo); d <- num(p$d); hour <- num(p$H); minute <- num(p$M); sec <- num(p$S)
  # slash date with a "month" above 12 is most likely day/month/year: do not guess
  if (p$type == "mdy" && mo > 12 && d <= 12) return(list(time = NA, unit = NA, type = "dmy_slash"))
  if (p$ap != "") {
    if (hour < 1 || hour > 12) return(list(time = NA, unit = NA, type = "bad"))
    hour <- hour %% 12 + if (toupper(p$ap) == "PM") 12 else 0
  }
  if (hour > 23 || minute > 59 || sec >= 60) return(list(time = NA, unit = NA, type = "bad"))
  t <- ISOdatetime(num(p$y), mo, d, hour, minute, sec, tz = "UTC")  # NA for impossible dates, e.g. 31 Feb
  if (is.na(t)) return(list(time = NA, unit = NA, type = "bad"))
  unit <- if (p$H == "") "day" else if (p$S == "") "minute" else "second"
  list(time = t, unit = unit, type = if (p$type == "mdy" && mo != d && mo <= 12 && d <= 12) "mdy_ambiguous" else p$type)
}

# Parse a timestamp column of the uploaded table; empty cells become NA, unreadable or unsafe values stop the App
parse_table_time <- function(x, col) {
  x <- trimws(as.character(x))
  x[x %in% c("", "NA")] <- NA
  res <- lapply(x, function(v) if (is.na(v)) list(time = NA, unit = NA, type = "empty") else parse_one_time(v))
  type <- vapply(res, function(r) r$type, character(1))
  out <- as.POSIXct(vapply(res, function(r) as.numeric(r$time), numeric(1)), origin = "1970-01-01", tz = "UTC")
  unit <- vapply(res, function(r) as.character(r$unit), character(1))
  
  if (any(type == "dmy_slash")) {
    stop(paste0("These timestamps in column '", col, "' look like day/month/year: ", paste(x[type == "dmy_slash"], collapse = ", "),
                ". Dates with '/' are read as month/day/year (Excel format). Please use the format YYYY-MM-DDTHH:MM:SSZ (UTC)."))
  }
  if (any(type == "bad")) {
    stop(paste0("These timestamps in column '", col, "' of your table could not be read: ", paste(x[type == "bad"], collapse = ", "),
                ". Please use the format YYYY-MM-DDTHH:MM:SSZ (UTC) or leave the cell empty."))
  }
  if (any(type %in% c("mdy", "mdy_ambiguous"))) {
    logger.warn(paste0("Timestamps with '/' in column '", col, "' are read as month/day/year (Excel format), e.g. '",
                       x[type %in% c("mdy", "mdy_ambiguous")][1], "' = ", format(out[type %in% c("mdy", "mdy_ambiguous")][1], "%Y-%m-%d %H:%M:%S"), "."))
    if (any(type == "mdy_ambiguous")) {
      logger.warn(paste0("These values in column '", col, "' could also be read as day/month/year, please check them: ",
                         paste(x[type == "mdy_ambiguous"], collapse = ", "), ". To avoid this, use the format YYYY-MM-DDTHH:MM:SSZ."))
    }
  }
  if (any(type == "dmy")) {
    logger.info(paste0("Timestamps with '.' in column '", col, "' are read as day.month.year, e.g. '",
                       x[type == "dmy"][1], "' = ", format(out[type == "dmy"][1], "%Y-%m-%d %H:%M:%S"), "."))
  }
  list(time = out, unit = unit)
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
  start <- parse_table_time(tab[[start_col]], start_col)
  end <- parse_table_time(tab[[end_col]], end_col)
  data.frame(track_id = track_id,
             start = start$time, end = end$time,
             start_unit = start$unit, end_unit = end$unit)
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
                           format(minT, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                           format(maxT, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
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
    # a date-only end includes the whole day; times without seconds are used exactly (HH:MM:00)
    unit_secs <- c(day = 86400, minute = 0, second = 0)
    start_ext <- ifelse(is.na(m) | is.na(tab$start_unit[m]), 0, unit_secs[tab$start_unit[m]])
    end_ext <- ifelse(is.na(m) | is.na(tab$end_unit[m]), 0, unit_secs[tab$end_unit[m]])
    # empty start/end: use the first/last timestamp of the track
    time1[!is.na(m) & is.na(time1)] <- minT[!is.na(m) & is.na(time1)]
    timeN[!is.na(m) & is.na(timeN)] <- maxT[!is.na(m) & is.na(timeN)]
    
    switched <- which(!is.na(time1) & !is.na(timeN) & time1 > timeN + end_ext)
    if (length(switched) > 0) {
      logger.warn(paste("For these tracks the start timestamp is after the end timestamp. We assume that they were switched and filter accordingly:", paste(track_ids[switched], collapse = ", ")))
      tmp <- time1[switched]; time1[switched] <- timeN[switched]; timeN[switched] <- tmp
      tmp <- start_ext[switched]; start_ext[switched] <- end_ext[switched]; end_ext[switched] <- tmp
    }
    # extended ends are excluded: e.g. end 2020-08-29 keeps all locations before 2020-08-30 00:00:00
    timeN <- timeN + end_ext
    end_excl <- end_ext > 0
    if (any(end_excl)) logger.info("End values given as a date only (e.g. 2020-08-29) include the whole day. Start values given as a date only begin at 00:00:00.")
    
    # times without seconds are used as HH:MM:00; warn if this cuts off locations within that same minute,
    # which typically happens when Excel removed the seconds of the created time table
    no_sec <- !is.na(m) & (tab$start_unit[m] %in% "minute" | tab$end_unit[m] %in% "minute")
    if (any(no_sec)) {
      logger.warn("Some timestamps in your table have no seconds and are used as HH:MM:00. If the table was saved in Excel, the seconds may have been removed. To avoid this, keep the timestamps in the format YYYY-MM-DDTHH:MM:SSZ (e.g. 2014-08-03T02:01:23Z), as in the table created by the App.")
      # (a start without seconds can only include more locations, so only ends are checked)
      cut_end <- no_sec & tab$end_unit[m] %in% "minute" & maxT > timeN & maxT < timeN + 60
      if (any(cut_end)) {
        logger.warn(paste("For these tracks, the last location(s) lie in the same minute as the end time of your table, but after it, and are excluded because the seconds are missing (possibly removed by Excel):",
                          paste(track_ids[cut_end], collapse = ", ")))
      }
    }
    logger.info("Selecting the time sections of each track given in your uploaded table.")
  } else {
    stop(paste("Unknown mode:", mode))
  }
  names(time1) <- names(timeN) <- names(end_excl) <- track_ids
  logger.info("Time selections include the specified start and end. For date-only end values, the entire end date is included.")
  
  # keep locations within [time1, timeN] of their track (both ends included),
  # or [time1, timeN) for date-only custom-table ends, where timeN is midnight of the following day
  keep <- valid & ids %in% track_ids
  k_ids <- ids[keep]
  k_times <- times[keep]
  keep[keep] <- !is.na(time1[k_ids]) & k_times >= time1[k_ids] &
    ifelse(end_excl[k_ids], k_times < timeN[k_ids], k_times <= timeN[k_ids])
  
  for (id in track_ids) {
    n_in <- sum(keep[ids == id])
    n_all <- sum(ids == id)
    if (is.na(time1[id])) {
      logger.info(paste0("Track ", id, ": not in your table, the track is removed."))
      next
    }
    # selected time range of the track; a date-only end is shown as that date (whole day included)
    range_txt <- paste("from", format(time1[id], "%Y-%m-%d %H:%M:%S", tz = "UTC"), "to",
                       if (end_excl[id]) paste(format(timeN[id] - 1, "%Y-%m-%d", tz = "UTC"), "(whole day)") else format(timeN[id], "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                       "(UTC)")
    if (n_in == 0) logger.info(paste0("Track ", id, ": selected time range ", range_txt, ". No locations in this time range, the track is removed.")) else
      logger.info(paste0("Track ", id, ": selected time range ", range_txt, ". ", n_in, " of ", n_all, " locations selected."))
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