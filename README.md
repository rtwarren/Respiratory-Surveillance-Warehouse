# Respiratory-Surveillance-Warehouse

A small surveillance data warehouse for Canadian respiratory virus laboratory data, with a dashboard that rebuilds itself every week.

**Live dashboard:** https://rtwarren.github.io/Respiratory-Surveillance-Warehouse/

Every Friday, GitHub Actions downloads the latest Respiratory Virus Detection Surveillance System (RVDSS) files from the Public Health Agency of Canada. It validates them, loads them into a SQL Server star schema with an R ETL, renders a Quarto dashboard from the reporting views, and publishes it to GitHub Pages.

## Architecture

```
Health Infobase (PHAC)          R ETL                         SQL Server                   Quarto
----------------------          -----                         ----------                   ------
RVD_WeeklyData.csv     -->  extract.R   download        -->  stg.RVDWeekly              rpt views
RVD_BaselineData.csv        transform.R type, tidy,          stg.RVDBaseline       -->  dashboard/index.qmd
RVD_UpdateDate.csv                      enrich                    | etl.usp_LoadRVD          |
                            validate.R  quality checks            v                          v
                            load.R      truncate-and-       dim.Geography              GitHub Pages
                                        reload staging      dim.Virus
                                        in one transaction  dim.SurveillanceWeek
                                                            fct.LabDetections
                                                            fct.PercentPositiveBaseline
                                                            etl.LoadLog
```

## Design decisions

**Star schema with conventional layers.** `stg` holds typed copies of the source files and is replaced on every load. `dim` and `fct` hold the model, `rpt` holds the views the dashboard reads, and `etl` holds the load log. The dashboard never touches the base tables.

**Transactional loads.** The R loader truncates and reloads staging, then calls `etl.usp_LoadRVD`, all inside one `dbBegin`/`dbCommit` with rollback on error. A failed load leaves the warehouse exactly as it was.

**Revisions are expected.** Recent weeks change as late lab results arrive. Facts are upserted on (week, geography, virus): changed counts are updated in place, unchanged rows are left alone, and every load records inserted, updated and unchanged counts in `etl.LoadLog`.

**Validation before load.** Checks run in R before anything touches the database:

| Check | Severity |
| --- | --- |
| Unique week, geography and virus | error |
| Counts non-negative; detections never exceed tests | error |
| Percent positive within 0 to 100 | error |
| Each geography belongs to exactly one region | error |
| Each week end date maps to one epidemiological week | error |
| Published percent positive matches detections divided by tests | warning |
| Canada total present every week | warning |

**Geography hierarchy.** The source mixes national, regional (Atlantic, Prairies, Territories) and provincial or territorial rows in one column. The transform tags each with a level, so reports can't double count.

**Source quirks handled explicitly.** `N/A` becomes `NULL`, never zero. Season labels are derived from epidemiological week 35. Percent positive is recomputed from counts in a persisted computed column, and the published value is kept alongside it for comparison.

## Tests

| Layer | What runs | Where |
| --- | --- | --- |
| R unit tests | transforms, season logic, NA handling, every validation rule | `tests/testthat` |
| Integration: initial load | fixture files through the full ETL, then SQL assertions on dimensions, facts, hierarchy and views | `tests/sql/test_load.sql` |
| Integration: re-run | loading the same files again must insert and update nothing | same |
| Integration: revision | a revised count must update exactly one row | same |

The integration tests run against a real SQL Server 2022 container in CI, using small synthetic fixture files in the same format as the source (`tests/fixtures`).

## Run it locally

Requirements: R 4.3+, Quarto 1.4+, SQL Server (Docker is fine) and Microsoft ODBC Driver 18.

```bash
# 1. database
docker run -e ACCEPT_EULA=Y -e MSSQL_SA_PASSWORD='<strong password>' -p 1433:1433 -d mcr.microsoft.com/mssql/server:2022-latest
sqlcmd -S localhost -U sa -P '<strong password>' -C -Q "CREATE DATABASE RSW"
for f in sql/01_schema.sql sql/02_procedures.sql sql/03_rpt_views.sql; do sqlcmd -S localhost -U sa -P '<strong password>' -C -b -d RSW -i "$f"; done

# 2. load
export RSW_CONNECTION="Driver={ODBC Driver 18 for SQL Server};Server=localhost,1433;Database=RSW;UID=sa;PWD=<strong password>;TrustServerCertificate=yes;"
Rscript run_etl.R                     # download latest and load
Rscript run_etl.R --validate-only     # download and validate only

# 3. dashboard
quarto render dashboard/index.qmd
```

## Project layout

```
R/            extract, transform, validate and load functions
run_etl.R     command-line entry point
sql/          schema, load procedure, reporting views
dashboard/    Quarto dashboard
tests/        testthat unit tests, SQL assertions, fixture files
```

## Data source and licence

Public Health Agency of Canada, Respiratory Virus Detection Surveillance System, published through the Canadian respiratory virus surveillance report on Health Infobase. Contains information licensed under the Open Government Licence - Canada. RVDSS is a sentinel laboratory system and does not capture all respiratory virus testing in Canada.

Code is MIT licensed.
