# Filter Data by Indiv Time
MoveApps

Github repository: *github.com/movestore/FilterData-by-IndivTime*

## Description
Filters your data set by track/individual specific time ranges that are provided as table/move object.

## Documentation
This App requires as input a data set consisting of tracks and one track (called e.g. 'nest') that containes information about track specific start and end timestamps by which the tracks shall be filtered. Note that the names of the tracks and those in the e.g. 'nest' table must be equal. Variable names must be given in the exact spelling as in the data, refer to the Track Attributes in the data summary of the previous App.

The use case for which this App was built is to filter data for nesting times. The nest object is generated in the Nest Detection App and can be appended to tracks with the same track names by the Cloud Storage App.

### Input data
moveStack in Movebank format

### Output data
moveStack in Movebank format

### Artefacts
none

### Parameters 
`selVar`: Name of the object containing the start and end timestamps. E.g. `nest` when using rds output from Nest Detection App.

`trackVar`: Name of the track ID variable in the object containing the start and end timestamps. Take care that this parameter also exists in the track attributes of the input data set.

`startVar`: Name of the start time variable. Take care that this parameter also exists in the track attributes of the input data set. Times must be provided in the format `YYYY-MM-DD` (if date) or `YYYY-MM-DD HH:MM:SS.SSS`.

`endVar`: Name of the end time variable. Take care that this parameter also exists in the track attributes of the input data set. Times must be provided in the format `YYYY-MM-DD` (if date) or `YYYY-MM-DD HH:MM:SS.SSS`.


### Null or error handling:
**Parameter `selVar`:** If there is no object with the given name the App will run into an error.

**Parameter `trackVar`:** If there is no variable with the name given here, an error will be returned.

**Parameter `startVar`:** If there is no variable with the name given here, the individual track will not be filtered in this direction.

**Parameter `endVar`:** If there is no variable with the name given here, the individual track will not be filtered in this direction.

**Data:** If none of the locations in the input data set are in the required time intervals, a warning is given and a NULL data set is returned. 
