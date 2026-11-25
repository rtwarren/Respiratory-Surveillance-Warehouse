# Validate: data quality checks run before anything is written to the database.
# Each check returns the number of failing rows. "error" checks stop the load;
# "warning" checks are reported and recorded but do not block it.

check_result <- function(check, severity, failed, detail = "") {
  data.frame(check = check, severity = severity, failed = as.integer(failed), detail = detail,
             stringsAsFactors = FALSE)
}

validate_weekly <- function(weekly, pct_tolerance = 0.15) {
  key <- paste(weekly$WeekEndDate, weekly$GeographyName, weekly$Virus, sep = "|")
  both <- !is.na(weekly$Tests) & !is.na(weekly$Detections)
  recomputed <- ifelse(both & weekly$Tests > 0, 100 * weekly$Detections / weekly$Tests, NA_real_)
  pct_gap <- abs(recomputed - weekly$PercentPositive)

  region_per_geo <- tapply(weekly$Region, weekly$GeographyName, function(x) length(unique(x)))
  weeks_per_date <- tapply(paste(weekly$EpiYear, weekly$EpiWeek), weekly$WeekEndDate,
                           function(x) length(unique(x)))

  rbind(
    check_result("has rows", "error", as.integer(nrow(weekly) == 0)),
    check_result("unique week/geography/virus", "error", sum(duplicated(key))),
    check_result("counts are non-negative", "error",
                 sum(weekly$Tests < 0 | weekly$Detections < 0, na.rm = TRUE)),
    check_result("detections do not exceed tests", "error",
                 sum(both & weekly$Detections > weekly$Tests)),
    check_result("percent positive within 0-100", "error",
                 sum(weekly$PercentPositive < 0 | weekly$PercentPositive > 100, na.rm = TRUE)),
    check_result("each geography belongs to one region", "error", sum(region_per_geo > 1)),
    check_result("each week end date maps to one epi week", "error", sum(weeks_per_date > 1)),
    check_result("published percent matches detections/tests", "warning",
                 sum(pct_gap > pct_tolerance, na.rm = TRUE),
                 sprintf("tolerance %.2f points", pct_tolerance)),
    check_result("Canada total present every week", "warning",
                 length(setdiff(unique(weekly$WeekEndDate),
                                unique(weekly$WeekEndDate[weekly$GeographyName == "Canada"]))))
  )
}

validate_baseline <- function(baseline) {
  key <- paste(baseline$Virus, baseline$WeekOrder, baseline$SeriesName, sep = "|")
  rbind(
    check_result("baseline has rows", "error", as.integer(nrow(baseline) == 0)),
    check_result("unique baseline virus/week/series", "error", sum(duplicated(key))),
    check_result("baseline percent within 0-100", "error",
                 sum(baseline$PercentPositive < 0 | baseline$PercentPositive > 100, na.rm = TRUE))
  )
}

stop_on_errors <- function(results) {
  failed <- results[results$severity == "error" & results$failed > 0, , drop = FALSE]
  if (nrow(failed) > 0) {
    stop("Validation failed:\n",
         paste0("  - ", failed$check, " (", failed$failed, ")", collapse = "\n"),
         call. = FALSE)
  }
  invisible(results)
}
