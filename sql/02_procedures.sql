/*
  etl.usp_LoadRVD: merges the staging tables into the warehouse.

  - Dimensions: new members inserted, changed attributes updated.
  - fct.LabDetections: upsert on (week, geography, virus). Recent weeks are often
    revised as late lab results arrive, so changed counts are updated in place and
    unchanged rows are left alone.
  - fct.PercentPositiveBaseline: the source publishes it as a complete snapshot, so it
    is replaced.

  Called by the R loader inside its transaction.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE etl.usp_LoadRVD
    @SourceUpdated datetime2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BatchID uniqueidentifier = NEWID();

    INSERT etl.LoadLog (BatchID, SourceUpdated, RowsWeekly, RowsBaseline)
    SELECT @BatchID, @SourceUpdated,
           (SELECT COUNT(*) FROM stg.RVDWeekly),
           (SELECT COUNT(*) FROM stg.RVDBaseline);

    /* ---------- dim.Geography ---------- */
    WITH src AS
    (
        SELECT GeographyName,
               MAX(Region)         AS RegionName,
               MAX(GeographyLevel) AS GeographyLevel
        FROM
        (
            SELECT GeographyName, Region, GeographyLevel FROM stg.RVDWeekly
            UNION ALL
            SELECT Region, Region,
                   CASE WHEN Region = N'Canada' THEN N'Country' ELSE N'Region' END
            FROM stg.RVDBaseline
        ) AS x
        GROUP BY GeographyName
    )
    MERGE dim.Geography AS tgt
    USING src
        ON tgt.GeographyName = src.GeographyName
    WHEN MATCHED AND (tgt.RegionName <> src.RegionName OR tgt.GeographyLevel <> src.GeographyLevel) THEN
        UPDATE SET RegionName = src.RegionName, GeographyLevel = src.GeographyLevel
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (GeographyName, RegionName, GeographyLevel)
        VALUES (src.GeographyName, src.RegionName, src.GeographyLevel);

    /* ---------- dim.Virus ---------- */
    WITH viruses AS
    (
        SELECT DISTINCT Virus FROM stg.RVDWeekly
        UNION
        SELECT DISTINCT Virus FROM stg.RVDBaseline
    )
    MERGE dim.Virus AS tgt
    USING
    (
        SELECT Virus AS VirusName,
               CASE WHEN Virus LIKE N'Influenza%' THEN N'Influenza' ELSE Virus END AS VirusGroup,
               CASE WHEN Virus LIKE N'Influenza _' THEN 1 ELSE 0 END AS IsSubtype
        FROM viruses
    ) AS src
        ON tgt.VirusName = src.VirusName
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (VirusName, VirusGroup, IsSubtype) VALUES (src.VirusName, src.VirusGroup, src.IsSubtype);

    /* ---------- dim.SurveillanceWeek ---------- */
    MERGE dim.SurveillanceWeek AS tgt
    USING
    (
        SELECT DISTINCT WeekEndDate, EpiYear, EpiWeek, SeasonLabel, WeekOrder AS SeasonWeekOrder
        FROM stg.RVDWeekly
    ) AS src
        ON tgt.WeekEndDate = src.WeekEndDate
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (WeekEndDate, EpiYear, EpiWeek, SeasonLabel, SeasonWeekOrder)
        VALUES (src.WeekEndDate, src.EpiYear, src.EpiWeek, src.SeasonLabel, src.SeasonWeekOrder);

    /* ---------- fct.LabDetections ---------- */
    DECLARE @changes TABLE (Action nvarchar(10) NOT NULL);

    MERGE fct.LabDetections AS tgt
    USING
    (
        SELECT s.WeekEndDate, g.GeographyKey, v.VirusKey, s.Tests, s.Detections, s.PercentPositive
        FROM stg.RVDWeekly AS s
        JOIN dim.Geography AS g ON g.GeographyName = s.GeographyName
        JOIN dim.Virus     AS v ON v.VirusName     = s.Virus
    ) AS src
        ON  tgt.WeekEndDate  = src.WeekEndDate
        AND tgt.GeographyKey = src.GeographyKey
        AND tgt.VirusKey     = src.VirusKey
    WHEN MATCHED AND (   ISNULL(tgt.Tests, -1)                 <> ISNULL(src.Tests, -1)
                      OR ISNULL(tgt.Detections, -1)            <> ISNULL(src.Detections, -1)
                      OR ISNULL(tgt.SourcePercentPositive, -1) <> ISNULL(src.PercentPositive, -1)) THEN
        UPDATE SET Tests                 = src.Tests,
                   Detections            = src.Detections,
                   SourcePercentPositive = src.PercentPositive,
                   LastBatchID           = @BatchID,
                   UpdatedAt             = SYSUTCDATETIME()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (WeekEndDate, GeographyKey, VirusKey, Tests, Detections, SourcePercentPositive, LastBatchID)
        VALUES (src.WeekEndDate, src.GeographyKey, src.VirusKey, src.Tests, src.Detections, src.PercentPositive, @BatchID)
    OUTPUT $action INTO @changes;

    /* ---------- fct.PercentPositiveBaseline (snapshot) ---------- */
    DELETE FROM fct.PercentPositiveBaseline;

    INSERT fct.PercentPositiveBaseline (GeographyKey, VirusKey, SeasonWeekOrder, EpiWeek, SeriesName, PercentPositive)
    SELECT g.GeographyKey, v.VirusKey, b.WeekOrder, b.EpiWeek, b.SeriesName, b.PercentPositive
    FROM stg.RVDBaseline AS b
    JOIN dim.Geography AS g ON g.GeographyName = b.Region
    JOIN dim.Virus     AS v ON v.VirusName     = b.Virus;

    /* ---------- log ---------- */
    DECLARE @inserted int = (SELECT COUNT(*) FROM @changes WHERE Action = N'INSERT');
    DECLARE @updated  int = (SELECT COUNT(*) FROM @changes WHERE Action = N'UPDATE');
    DECLARE @rows     int = (SELECT COUNT(*) FROM stg.RVDWeekly);

    UPDATE etl.LoadLog
    SET CompletedAt = SYSUTCDATETIME(),
        Inserted    = @inserted,
        Updated     = @updated,
        Unchanged   = @rows - @inserted - @updated
    WHERE BatchID = @BatchID;

    SELECT BatchID, SourceUpdated, RowsWeekly, RowsBaseline, Inserted, Updated, Unchanged
    FROM etl.LoadLog
    WHERE BatchID = @BatchID;
END;
GO
