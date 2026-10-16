# Filter by Individual Time Intervals

MoveApps

Github repository: https://github.com/movestore/FilterData-by-IndivTime.git

## Description
Filters each track of your data set to its own time interval(s), for example nesting periods. The start and end times per track are provided as a separate selection track in the data, such as the nest table of the Nest Cluster Detection App.

## Documentation
This App keeps, for each animal (track), only the locations that lie within the time interval(s) given for that animal. The time intervals are taken from one extra track in the input data, the *selection track*. Each location (row) of this selection track holds one time interval: the name of the animal it belongs to, a start time and an end time. The selection track itself is removed from the output.

The main use case is filtering tracks to their nesting periods. The Nest Cluster Detection App writes the artefact `nest_table.csv`, which can be added to the tracking data with the Upload File from Cloud Storage App. The table then becomes a track (by default named `nesting`). Use the following settings for this case:

- Selection track name: `nesting`
- Track name variable: `track`
- Start time variable: `first_date` (or `attempt_start`)
- End time variable: `last_date` (or `attempt_end`)

Note that in the Upload File from Cloud Storage App, the track ID column must be set to `individual_local_identifier` (with underscores, as written in `nest_table.csv`).

The App works as follows:

1. The selection track is found by its name. Its rows are read as a table of time intervals.
2. For each animal track, the App looks for rows with the same name in the track name variable. If there is no exact match, the App also tries the "cleaned" animal name, in the same way as the Nest Cluster Detection App writes names into `nest_table.csv` (spaces removed, then R `make.names()`, e.g. `Animal 1` → `Animal1`, `1234` → `X1234`). This matching is reported in the logs.
3. An animal can have several time intervals (e.g. several nesting attempts). Locations that lie in **any** of the intervals are kept.
4. If an end value is a date without a time (e.g. `2020-05-30`), the **full end day** is included. If the end value has a time, the interval ends exactly at that time.
5. If a start value is after its end value, the two are assumed to be switched and are swapped.
6. All other locations are removed. At the end, the App writes a summary table to the logs, listing for each track the number of input locations, the number of kept locations, and what happened to it.

### Application scope
#### Generality of App usability
This App was developed for filtering white stork data to nesting periods detected by the Nest Cluster Detection App, but it can be used for any taxonomic group and for any kind of time intervals per track (e.g. breeding, migration, or deployment periods), as long as they are provided as a selection track.

#### Required data properties
The input data must contain the selection track, i.e. one track that holds a table with one row per time interval and columns for the track name, the start time and the end time. The track names in this table must be the same as the track names of the data (or their cleaned version as written by the Nest Cluster Detection App).

Start and end times must be in UTC and in the format `YYYY-MM-DD` (date only) or `YYYY-MM-DD HH:MM:SS` (date and time). Columns of date or date-time type are also accepted.

### Input type
`move2::move2_loc`

### Output type
`move2::move2_loc`

### Artefacts
none

### Settings 
`Selection track name` (selName): Name of the track in your data that holds the table of start and end times per animal, e.g. `nesting` when `nest_table.csv` of the Nest Cluster Detection App was added with the Upload File from Cloud Storage App. Default: none.

`Track name variable` (trackVar): Name of the column in the selection track that holds the animal (track) names, e.g. `track` for `nest_table.csv`. This setting is required. Default: none.

`Start time variable` (startVar): Name of the column in the selection track with the start times, e.g. `first_date` or `attempt_start`. Default: none.

`End time variable` (endVar): Name of the column in the selection track with the end times, e.g. `last_date` or `attempt_end`. A date without time includes the full end day. Default: none.

### Changes in output data
The App filters the input data: only locations within the time interval(s) of their track are kept. Tracks without any kept locations are removed, and the selection track is always removed. No columns are added or changed.

### Errors and null handling
**Setting `selName`:** If it is not set, or no track with this name exists in the data, the App returns NULL and writes a message to the logs.

**Setting `trackVar`:** If it is not set, or the column does not exist in the selection track, the App stops with an error message.

**Setting `startVar`:** If it is not set, or the column does not exist in the selection track, the tracks are not filtered at the start: each track is filtered from its first timestamp.

**Setting `endVar`:** If it is not set, or the column does not exist in the selection track, the tracks are not filtered at the end: each track is filtered until its last timestamp.

**Start/end values:** Values that cannot be read as a time are treated as missing, and a warning lists the affected track and value. Intervals with a missing start or end value are not used. Empty cells are treated as missing without a warning.

**Track names:** Animal tracks without any interval in the selection track are removed. If two animal tracks have the same cleaned name (e.g. `Bird 9` and `Bird9`) and the cleaned name is needed for matching, the track is not matched and is removed, with a warning. Names in the selection track that do not match any track of the data are listed in a warning.

**Input data:** Tracks without any valid timestamp are removed, with a warning. Tracks without any location in their time interval(s) are removed, with a warning.

**Null output:** If no locations remain after filtering, the App returns NULL with a warning.

### Technical details
- The App uses the `move2` package (`mt_track_id()`, `mt_time()`) to handle the tracking data, `lubridate` (`parse_date_time()`, `with_tz()`) to read the start and end times as UTC, and `sf` (`st_drop_geometry()`) to read the selection track as a table.
- Data are processed per track. Locations are kept if their timestamp is ≥ start and ≤ end of any interval of their track; for date-only end values, the comparison is < end date + 1 day.
- Name matching tries the exact track name first. Only if there is no exact match is the cleaned name (`make.names(gsub(" ", "", name))`) used, and only if it is unique among the tracks of the data.
- This App is a `move2` version of the earlier `move::moveStack` App with the same name, and it has some changes in behaviour: several intervals per track are allowed, date-only end values include the full end day, start and end column names are checked in the selection track, start/end times are read as UTC, cleaned-name matching is available, and a summary is written to the logs.
