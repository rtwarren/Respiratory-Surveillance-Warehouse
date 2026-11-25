#!/usr/bin/env Rscript
# Usage:
#   Rscript run_etl.R                       download the latest files and load them
#   Rscript run_etl.R --source-dir <dir>    load files already on disk (used by the tests)
#   Rscript run_etl.R --validate-only       download and validate, no database
#
# The warehouse connection comes from the RSW_CONNECTION environment variable.

suppressPackageStartupMessages({
  library(DBI)
})

for (f in list.files("R", pattern = "\\.R$", full.names = TRUE)) source(f)

args <- commandArgs(trailingOnly = TRUE)
arg_value <- function(flag) {
  i <- match(flag, args)
  if (is.na(i) || i == length(args)) NULL else args[[i + 1L]]
}
source_dir <- arg_value("--source-dir")
validate_only <- "--validate-only" %in% args

paths <- if (is.null(source_dir)) {
  message("Downloading RVDSS files from Health Infobase")
  download_rvd(file.path(tempdir(), "rvd"))
} else {
  message("Using files in ", source_dir)
  local_rvd(source_dir)
}

weekly <- transform_weekly(read_rvd_csv(paths[["weekly"]]))
baseline <- transform_baseline(read_rvd_csv(paths[["baseline"]]))
source_updated <- read_update_date(paths[["updated"]])

checks <- rbind(validate_weekly(weekly), validate_baseline(baseline))
print(checks, row.names = FALSE)
stop_on_errors(checks)

message(sprintf(
  "Validated %d weekly rows (%s to %s) and %d baseline rows. Source updated %s.",
  nrow(weekly), min(weekly$WeekEndDate), max(weekly$WeekEndDate), nrow(baseline),
  format(source_updated, "%Y-%m-%d %H:%M")
))

if (validate_only) quit(status = 0)

con <- connect_warehouse()
result <- tryCatch(
  load_rvd(con, weekly, baseline, source_updated),
  finally = DBI::dbDisconnect(con)
)
print(result, row.names = FALSE)
