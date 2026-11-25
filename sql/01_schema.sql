/*
  Respiratory surveillance warehouse: star schema.

  stg  typed copies of the source files, replaced on every load
  dim  geography, virus and surveillance week dimensions
  fct  weekly laboratory tests and detections; historical seasonal baselines
  rpt  reporting views (see 03_rpt_views.sql)
  etl  load log

  All scripts are idempotent.
*/
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF SCHEMA_ID(N'stg') IS NULL EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
IF SCHEMA_ID(N'dim') IS NULL EXEC (N'CREATE SCHEMA dim AUTHORIZATION dbo;');
IF SCHEMA_ID(N'fct') IS NULL EXEC (N'CREATE SCHEMA fct AUTHORIZATION dbo;');
IF SCHEMA_ID(N'rpt') IS NULL EXEC (N'CREATE SCHEMA rpt AUTHORIZATION dbo;');
IF SCHEMA_ID(N'etl') IS NULL EXEC (N'CREATE SCHEMA etl AUTHORIZATION dbo;');
GO

/* ---------- staging ---------- */

IF OBJECT_ID(N'stg.RVDWeekly', N'U') IS NULL
CREATE TABLE stg.RVDWeekly
(
    Region           nvarchar(50)  NOT NULL,
    GeographyName    nvarchar(60)  NOT NULL,
    GeographyLevel   nvarchar(20)  NOT NULL,
    EpiYear          smallint      NOT NULL,
    EpiWeek          tinyint       NOT NULL,
    WeekOrder        tinyint       NOT NULL,
    WeekEndDate      date          NOT NULL,
    SeasonLabel      char(9)       NOT NULL,
    Virus            nvarchar(30)  NOT NULL,
    Tests            int           NULL,
    Detections       int           NULL,
    PercentPositive  decimal(5,2)  NULL
);
GO

IF OBJECT_ID(N'stg.RVDBaseline', N'U') IS NULL
CREATE TABLE stg.RVDBaseline
(
    Region           nvarchar(50)  NOT NULL,
    EpiWeek          tinyint       NOT NULL,
    WeekOrder        tinyint       NOT NULL,
    WeekEndDate      date          NOT NULL,
    Virus            nvarchar(30)  NOT NULL,
    SeriesName       nvarchar(40)  NOT NULL,
    PercentPositive  decimal(5,2)  NOT NULL
);
GO

/* ---------- dimensions ---------- */

IF OBJECT_ID(N'dim.Geography', N'U') IS NULL
CREATE TABLE dim.Geography
(
    GeographyKey    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_Geography PRIMARY KEY,
    GeographyName   nvarchar(60) NOT NULL CONSTRAINT UQ_dim_Geography_Name UNIQUE,
    RegionName      nvarchar(50) NOT NULL,
    GeographyLevel  nvarchar(20) NOT NULL
        CONSTRAINT CK_dim_Geography_Level CHECK (GeographyLevel IN (N'Country', N'Region', N'Province/Territory'))
);
GO

IF OBJECT_ID(N'dim.Virus', N'U') IS NULL
CREATE TABLE dim.Virus
(
    VirusKey    int IDENTITY(1,1) NOT NULL CONSTRAINT PK_dim_Virus PRIMARY KEY,
    VirusName   nvarchar(30) NOT NULL CONSTRAINT UQ_dim_Virus_Name UNIQUE,
    VirusGroup  nvarchar(30) NOT NULL,
    IsSubtype   bit          NOT NULL
);
GO

IF OBJECT_ID(N'dim.SurveillanceWeek', N'U') IS NULL
CREATE TABLE dim.SurveillanceWeek
(
    WeekEndDate      date     NOT NULL CONSTRAINT PK_dim_SurveillanceWeek PRIMARY KEY,
    EpiYear          smallint NOT NULL,
    EpiWeek          tinyint  NOT NULL,
    SeasonLabel      char(9)  NOT NULL,
    SeasonWeekOrder  tinyint  NOT NULL,
    CONSTRAINT UQ_dim_SurveillanceWeek_YearWeek UNIQUE (EpiYear, EpiWeek)
);
GO

/* ---------- facts ---------- */

IF OBJECT_ID(N'fct.LabDetections', N'U') IS NULL
CREATE TABLE fct.LabDetections
(
    WeekEndDate            date NOT NULL CONSTRAINT FK_fct_LabDetections_Week REFERENCES dim.SurveillanceWeek (WeekEndDate),
    GeographyKey           int  NOT NULL CONSTRAINT FK_fct_LabDetections_Geography REFERENCES dim.Geography (GeographyKey),
    VirusKey               int  NOT NULL CONSTRAINT FK_fct_LabDetections_Virus REFERENCES dim.Virus (VirusKey),
    Tests                  int  NULL,
    Detections             int  NULL,
    PercentPositive        AS CAST(CASE WHEN Tests > 0 THEN 100.0 * Detections / Tests END AS decimal(5,2)) PERSISTED,
    SourcePercentPositive  decimal(5,2) NULL,
    LastBatchID            uniqueidentifier NOT NULL,
    InsertedAt             datetime2(3) NOT NULL CONSTRAINT DF_fct_LabDetections_InsertedAt DEFAULT SYSUTCDATETIME(),
    UpdatedAt              datetime2(3) NULL,
    CONSTRAINT PK_fct_LabDetections PRIMARY KEY (WeekEndDate, GeographyKey, VirusKey),
    CONSTRAINT CK_fct_LabDetections_Counts CHECK (Tests >= 0 AND Detections >= 0 AND Detections <= Tests)
);
GO

IF OBJECT_ID(N'fct.PercentPositiveBaseline', N'U') IS NULL
CREATE TABLE fct.PercentPositiveBaseline
(
    GeographyKey     int          NOT NULL CONSTRAINT FK_fct_Baseline_Geography REFERENCES dim.Geography (GeographyKey),
    VirusKey         int          NOT NULL CONSTRAINT FK_fct_Baseline_Virus REFERENCES dim.Virus (VirusKey),
    SeasonWeekOrder  tinyint      NOT NULL,
    EpiWeek          tinyint      NOT NULL,
    SeriesName       nvarchar(40) NOT NULL,
    PercentPositive  decimal(5,2) NOT NULL,
    CONSTRAINT PK_fct_PercentPositiveBaseline PRIMARY KEY (GeographyKey, VirusKey, SeasonWeekOrder, SeriesName)
);
GO

/* ---------- etl ---------- */

IF OBJECT_ID(N'etl.LoadLog', N'U') IS NULL
CREATE TABLE etl.LoadLog
(
    BatchID        uniqueidentifier NOT NULL CONSTRAINT PK_etl_LoadLog PRIMARY KEY,
    StartedAt      datetime2(3)     NOT NULL CONSTRAINT DF_etl_LoadLog_StartedAt DEFAULT SYSUTCDATETIME(),
    CompletedAt    datetime2(3)     NULL,
    SourceUpdated  datetime2(0)     NULL,
    RowsWeekly     int              NULL,
    RowsBaseline   int              NULL,
    Inserted       int              NULL,
    Updated        int              NULL,
    Unchanged      int              NULL
);
GO
