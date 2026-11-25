# Load: truncate-and-reload the staging tables inside one transaction, then call the
# stored procedure that merges staging into the dimensions and facts.
# If anything fails, the transaction rolls back and the warehouse is unchanged.

connect_warehouse <- function(connection_string = Sys.getenv("RSW_CONNECTION")) {
  if (!nzchar(connection_string)) {
    stop("Set RSW_CONNECTION to an ODBC connection string.", call. = FALSE)
  }
  DBI::dbConnect(odbc::odbc(), .connection_string = connection_string, timeout = 30)
}

load_rvd <- function(con, weekly, baseline, source_updated) {
  DBI::dbBegin(con)
  tryCatch({
    DBI::dbExecute(con, "TRUNCATE TABLE stg.RVDWeekly;")
    DBI::dbExecute(con, "TRUNCATE TABLE stg.RVDBaseline;")
    DBI::dbAppendTable(con, DBI::Id(schema = "stg", table = "RVDWeekly"), weekly)
    DBI::dbAppendTable(con, DBI::Id(schema = "stg", table = "RVDBaseline"), baseline)

    result <- DBI::dbGetQuery(
      con,
      "EXEC etl.usp_LoadRVD @SourceUpdated = ?;",
      params = list(format(source_updated, "%Y-%m-%d %H:%M:%S"))
    )
    DBI::dbCommit(con)
    result
  }, error = function(e) {
    try(DBI::dbRollback(con), silent = TRUE)
    stop("Load rolled back: ", conditionMessage(e), call. = FALSE)
  })
}
