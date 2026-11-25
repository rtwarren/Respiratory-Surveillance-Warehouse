/*
  Assertions run in CI after loading the fixture files with run_etl.R.
  Invoke with sqlcmd -v Stage=initial | rerun | revision.
  Any failed assertion raises an error, which fails the job (sqlcmd -b).
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @stage nvarchar(20) = N'$(Stage)';
DECLARE @msg nvarchar(400);

IF @stage = N'initial'
BEGIN
    IF (SELECT COUNT(*) FROM fct.LabDetections) <> 30
        THROW 50001, 'initial: expected 30 fact rows', 1;
    IF (SELECT COUNT(*) FROM dim.Geography) <> 5
        THROW 50002, 'initial: expected 5 geographies', 1;
    IF (SELECT GeographyLevel FROM dim.Geography WHERE GeographyName = N'Territories') <> N'Region'
        THROW 50003, 'initial: Territories should be a Region', 1;
    IF (SELECT GeographyLevel FROM dim.Geography WHERE GeographyName = N'Northwest Territories') <> N'Province/Territory'
        THROW 50004, 'initial: Northwest Territories should be a Province/Territory', 1;
    IF (SELECT RegionName FROM dim.Geography WHERE GeographyName = N'Northwest Territories') <> N'Territories'
        THROW 50005, 'initial: Northwest Territories should roll up to Territories', 1;
    IF (SELECT COUNT(*) FROM dim.Virus) <> 5
        THROW 50006, 'initial: expected 5 viruses', 1;
    IF NOT EXISTS (SELECT 1 FROM dim.Virus WHERE VirusName = N'Influenza A' AND VirusGroup = N'Influenza' AND IsSubtype = 1)
        THROW 50007, 'initial: Influenza A should be an Influenza subtype', 1;
    IF EXISTS (SELECT 1 FROM dim.SurveillanceWeek WHERE SeasonLabel <> '2026-2027')
        THROW 50008, 'initial: all fixture weeks belong to the 2026-2027 season', 1;
    IF (SELECT EpiYear FROM dim.SurveillanceWeek WHERE WeekEndDate = '2027-01-02') <> 2027
        THROW 50009, 'initial: week ending 2027-01-02 should be epi year 2027', 1;
    IF (SELECT COUNT(*) FROM fct.PercentPositiveBaseline) <> 39
        THROW 50010, 'initial: expected 39 baseline rows', 1;
    IF (SELECT Inserted FROM rpt.vw_LoadStatus) <> 30 OR (SELECT Updated FROM rpt.vw_LoadStatus) <> 0
        THROW 50011, 'initial: expected 30 inserts and 0 updates', 1;
    IF (SELECT COUNT(*) FROM rpt.vw_LatestWeek) <> 10
        THROW 50012, 'initial: expected 10 latest-week rows', 1;
    IF (SELECT ChangePoints FROM rpt.vw_LatestWeek WHERE GeographyName = N'Canada' AND VirusName = N'SARS-CoV-2') <> -0.50
        THROW 50013, 'initial: Canada SARS-CoV-2 change should be -0.50 points', 1;
    IF (SELECT PercentPositive FROM rpt.vw_WeeklyPositivity
        WHERE GeographyName = N'Territories' AND VirusName = N'HPIV' AND WeekEndDate = '2026-12-26') IS NOT NULL
        THROW 50014, 'initial: N/A source values should load as NULL', 1;
    IF (SELECT COUNT(*) FROM rpt.vw_SeasonComparison WHERE VirusName = N'SARS-CoV-2') <> 15
        THROW 50015, 'initial: expected 3 current + 12 baseline SARS-CoV-2 points', 1;
END
ELSE IF @stage = N'rerun'
BEGIN
    IF (SELECT COUNT(*) FROM fct.LabDetections) <> 30
        THROW 50101, 'rerun: reloading the same files must not add rows', 1;
    IF (SELECT Inserted FROM rpt.vw_LoadStatus) <> 0 OR (SELECT Updated FROM rpt.vw_LoadStatus) <> 0
        THROW 50102, 'rerun: expected 0 inserts and 0 updates', 1;
    IF (SELECT Unchanged FROM rpt.vw_LoadStatus) <> 30
        THROW 50103, 'rerun: expected 30 unchanged rows', 1;
END
ELSE IF @stage = N'revision'
BEGIN
    IF (SELECT Updated FROM rpt.vw_LoadStatus) <> 1
        THROW 50201, 'revision: expected exactly 1 updated row', 1;
    IF (SELECT Detections FROM rpt.vw_WeeklyPositivity
        WHERE GeographyName = N'Canada' AND VirusName = N'RSV' AND WeekEndDate = '2027-01-02') <> 2510
        THROW 50202, 'revision: revised detections not applied', 1;
    IF (SELECT COUNT(*) FROM etl.LoadLog) <> 3
        THROW 50203, 'revision: expected 3 loads in the log', 1;
END
ELSE
BEGIN
    SET @msg = N'Unknown stage: ' + @stage;
    THROW 50999, @msg, 1;
END;

PRINT N'SQL tests passed for stage: ' + @stage;
