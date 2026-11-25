/*
  Reporting views. The dashboard reads only from the rpt schema.
*/
SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW rpt.vw_WeeklyPositivity
AS
SELECT
    w.SeasonLabel,
    w.SeasonWeekOrder,
    w.EpiYear,
    w.EpiWeek,
    f.WeekEndDate,
    g.GeographyName,
    g.GeographyLevel,
    g.RegionName,
    v.VirusName,
    v.VirusGroup,
    v.IsSubtype,
    f.Tests,
    f.Detections,
    f.PercentPositive
FROM fct.LabDetections   AS f
JOIN dim.SurveillanceWeek AS w ON w.WeekEndDate  = f.WeekEndDate
JOIN dim.Geography        AS g ON g.GeographyKey = f.GeographyKey
JOIN dim.Virus            AS v ON v.VirusKey     = f.VirusKey;
GO

CREATE OR ALTER VIEW rpt.vw_LatestWeek
AS
-- Most recent week for every geography and virus, with the change from the week before.
WITH ordered AS
(
    SELECT
        p.*,
        LAG(p.PercentPositive) OVER (PARTITION BY p.GeographyName, p.VirusName ORDER BY p.WeekEndDate) AS PriorPercentPositive,
        LAG(p.Detections)      OVER (PARTITION BY p.GeographyName, p.VirusName ORDER BY p.WeekEndDate) AS PriorDetections
    FROM rpt.vw_WeeklyPositivity AS p
)
SELECT
    o.SeasonLabel,
    o.EpiYear,
    o.EpiWeek,
    o.WeekEndDate,
    o.GeographyName,
    o.GeographyLevel,
    o.RegionName,
    o.VirusName,
    o.VirusGroup,
    o.Tests,
    o.Detections,
    o.PercentPositive,
    o.PriorPercentPositive,
    CAST(o.PercentPositive - o.PriorPercentPositive AS decimal(5,2)) AS ChangePoints,
    o.PriorDetections
FROM ordered AS o
WHERE o.WeekEndDate = (SELECT MAX(WeekEndDate) FROM fct.LabDetections);
GO

CREATE OR ALTER VIEW rpt.vw_SeasonComparison
AS
-- Canada: the current season next to previous seasons and the pre-pandemic range,
-- aligned on week of season so the curves line up.
SELECT
    p.VirusName,
    p.SeasonWeekOrder,
    p.EpiWeek,
    p.SeasonLabel AS SeriesName,
    CAST(1 AS bit) AS IsCurrentSeason,
    p.PercentPositive
FROM rpt.vw_WeeklyPositivity AS p
WHERE p.GeographyName = N'Canada'
  AND p.SeasonLabel = (SELECT MAX(SeasonLabel) FROM dim.SurveillanceWeek)
UNION ALL
SELECT
    v.VirusName,
    b.SeasonWeekOrder,
    b.EpiWeek,
    b.SeriesName,
    CAST(0 AS bit),
    b.PercentPositive
FROM fct.PercentPositiveBaseline AS b
JOIN dim.Virus     AS v ON v.VirusKey     = b.VirusKey
JOIN dim.Geography AS g ON g.GeographyKey = b.GeographyKey
WHERE g.GeographyName = N'Canada';
GO

CREATE OR ALTER VIEW rpt.vw_LoadStatus
AS
SELECT TOP (1)
    BatchID, StartedAt, CompletedAt, SourceUpdated, RowsWeekly, RowsBaseline, Inserted, Updated, Unchanged
FROM etl.LoadLog
WHERE CompletedAt IS NOT NULL
ORDER BY CompletedAt DESC;
GO
