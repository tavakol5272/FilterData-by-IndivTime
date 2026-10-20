# Filter Data by Indiv Time

MoveApps

Github repository:

## Description
Selects a time section of each track: the first or last specified duration of each track, all locations from or until a specified timestamp, all locations between two timestamps, or a custom time range per track uploaded as a table. Optionally creates an editable table with the first and last timestamp of each track.

## Documentation
This App filters the locations of each track to a selected time section. The user chooses one of six time selection modes:

1. **First specified duration of each track**: keeps all locations from the first location of each track until the specified duration has passed (e.g. the first 3 months of each track). All tracks have the same duration, but their start times can differ.
2. **Last specified duration of each track**: keeps all locations from the specified duration before the last location of each track until its last location (e.g. the last 3 months of each track). All tracks have the same duration, but their end times can differ.
3. **From a specified timestamp to the end of each track**: keeps all locations at or after the given timestamp (e.g. from 2021-03-15 to the end of each track). All tracks start at the same time, but their durations can differ.
4. **From the start of each track to a specified timestamp**: keeps all locations at or before the given timestamp (e.g. from the start of each track to 2023-07-20). All tracks end at the same time, but their durations can differ.
5. **Between two specified timestamps**: keeps all locations between the given start and end timestamps (e.g. from 2023-05-01 to 2023-07-01) for all tracks.
6. **Custom time range for each track**: keeps for each track the locations between a start and an end timestamp given in an uploaded table (.csv) with one row per track. If the start of a track is empty, its first location is used; if the end is empty, its last location is used. This gives full flexibility over which section of each track is selected.

In all modes, both the start and the end of the time range are included in the selection (start <= timestamp <= end). The only exception is an end given as a date only in the custom table (e.g. `2020-08-29`): this includes the whole day, i.e. all locations before midnight of the following day.

Durations in hours, days and weeks are exact lengths of time. Months and years are calendar periods (e.g. 15 Jan + 3 months = 15 Apr; 31 Jan + 1 month = 28/29 Feb).

To make the custom table easy to prepare, the App can create an editable table `track_time_table.csv` with the first and last timestamp of each track of the input data. This table can be downloaded, edited (e.g. changing times or deleting rows of tracks that should be removed) and uploaded again in the mode 'Custom time range for each track'.

Tracks without any location in their selected time range are removed from the output. Messages in the logs show for each track how many locations were selected.

### Application scope
#### Generality of App usability
This App was developed for any taxonomic group.

#### Required data properties
The App should work for any kind of location data. For the mode 'Custom time range for each track', the track IDs in the uploaded table must match the track IDs of the input data exactly.

### Input type
`move2::move2_loc`

### Output type
`move2::move2_loc`

### Artefacts
`track_time_table.csv`: only created if `Create editable time table` is selected. A csv file with one row per track of the input data and three columns: track ID, timestamp of the first location and timestamp of the last location of the track (format `YYYY-MM-DD HH:MM:SS`, UTC). The column names are taken from the settings `Track ID column name`, `Start timestamp column name` and `End timestamp column name`, so that the table can be edited and directly uploaded in the mode 'Custom time range for each track'.

### Settings
`Time selection mode` (mode): Selects how the time section of each track is chosen. Options: 'First specified duration of each track' (`first`), 'Last specified duration of each track' (`last`), 'From a specified timestamp to the end of each track' (`from_time`), 'From the start of each track to a specified timestamp' (`until_time`), 'Between two specified timestamps' (`between`), 'Custom time range for each track' (`custom`). Default: `first`.

`Duration` (duration): Only used for the modes 'First specified duration of each track' and 'Last specified duration of each track'. Length of the time section to select, counted from the first location, or backwards from the last location, of each track. Must be larger than 0. For months and years it must be a whole number. Unit: as selected in `Duration unit`. Default: no default (must be set for these modes).

`Duration unit` (duration_unit): Only used for the modes 'First specified duration of each track' and 'Last specified duration of each track'. Unit of the duration. Options: `hours`, `days`, `weeks`, `months`, `years`. Months and years are calendar periods. Default: `days`.

`Start timestamp` (start_time): Only used for the modes 'From a specified timestamp to the end of each track' and 'Between two specified timestamps'. All locations at or after this timestamp (UTC) are kept. Default: no default (must be set for these modes).

`End timestamp` (end_time): Only used for the modes 'From the start of each track to a specified timestamp' and 'Between two specified timestamps'. All locations at or before this timestamp (UTC) are kept. Default: no default (must be set for these modes).

`Custom time table` (custom_table): Only used for the mode 'Custom time range for each track'. A .csv file with one row per track and three columns: track ID, start timestamp and end timestamp. Timestamps must be in UTC and use the format `YYYY-MM-DD HH:MM:SS` (also `YYYY-MM-DD HH:MM` and `YYYY-MM-DD` are accepted). An empty start uses the first location of the track, an empty end the last location. A date-only end includes the entire day, a date-only start begins at 00:00:00. Tracks not listed in the table are removed, and each track ID may appear only once. Default: no file.

`Track ID column name` (track_col): Name of the column with the track IDs in the custom table. Also used as column name in the created time table. Default: `track_id`.

`Start timestamp column name` (start_col): Name of the column with the start timestamps in the custom table. Also used as column name in the created time table. Default: `start_timestamp`.

`End timestamp column name` (end_col): Name of the column with the end timestamps in the custom table. Also used as column name in the created time table. Default: `end_timestamp`.

`Create editable time table` (create_table): If selected, the artefact `track_time_table.csv` with the first and last timestamp of each track of the input data is created. Default: `false`.

### Changes in output data
The App filters the input data to the selected time section of each track. No columns are added or changed. Tracks without any location in their selected time range are removed.

### Errors and null handling
**Setting `mode`:** For the modes 'First specified duration of each track' and 'Last specified duration of each track', the App stops with an error if no `duration` larger than 0 is given, if `duration_unit` is not one of hours, days, weeks, months or years, or if a non-whole number of months or years is given (e.g. 1.5 months). For the modes using timestamps, the App stops with an error if the required `start_time` and/or `end_time` is not given or cannot be read. Settings that are not used by the selected mode are ignored.

**Start after end:** If the start timestamp is after the end timestamp (in the mode 'Between two specified timestamps' or for a track in the custom table), the App assumes that they were switched, swaps them and gives a warning.

**Setting `custom_table`:** In the mode 'Custom time range for each track', the App stops with an error if no table is uploaded, if the table does not contain the columns named in `Track ID column name`, `Start timestamp column name` and `End timestamp column name`, if a track ID appears more than once, or if a timestamp cannot be read (the error lists the values that could not be read). Track IDs of the table that are not in the data are ignored with a warning. Tracks of the data that are not in the table are removed with a warning.

**Column name settings:** If `Track ID column name`, `Start timestamp column name` or `End timestamp column name` is left empty, the default names `track_id`, `start_timestamp` and `end_timestamp` are used.

**Input data:** Locations without a timestamp are removed with a warning. Tracks without any valid timestamp are removed with a warning; if no location has a valid timestamp, the App returns NULL.

**No data in time range:** If none of the locations lie in the selected time range(s), the App returns NULL with a warning. Check that the selected timestamps or durations fit the time span of your data.

### Technical details
- The App uses the `move2` package (`mt_track_id()`, `mt_time()`) to access track IDs and timestamps, and the `lubridate` package for calendar month/year arithmetic (`%m+%`, `%m-%`) and for reading the timestamps of the custom table (`parse_date_time()`).
- The time range is determined per track: the first and last valid timestamps of each track are used for the 'first/last specified duration' modes and for empty cells of the custom table.
- The data are filtered in one step on the whole data set (`data[keep, ]`), so the order of locations, the projection and all event and track attributes of the kept data remain unchanged.
- All timestamps are handled in UTC.
- The App is based on the App 'Filter by Individual Time Intervals' (move/moveStack), in which the start and end times had to be stored as an additional track in the data. Here they are provided as an uploaded table instead.
