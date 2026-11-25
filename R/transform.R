# Transform: type, tidy and enrich the raw RVDSS files into the shape of the staging tables.

WEEKLY_COLUMNS <- c(
  "region", "province", "week", "weekorder", "year", "date",
  "virus", "tests", "detections", "percentpositive"
)

BASELINE_ID_COLUMNS <- c("region", "Week", "weekorder", "current_week_end_date", "virus")

AGGREGATE_REGIONS <- c("Atlantic", "Prairies", "Territories")

# Surveillance seasons start in epidemiological week 35 (late August).
SEASON_START_WEEK <- 35L

require_columns <- function(df, columns, what) {
  missing <- setdiff(columns, names(df))
  if (length(missing) > 0) {
    stop(what, " is missing columns: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  invisible(df)
}

geography_level <- function(name) {
  dplyr::case_when(
    name == "Canada" ~ "Country",
    name %in% AGGREGATE_REGIONS ~ "Region",
    TRUE ~ "Province/Territory"
  )
}

season_label <- function(epi_year, epi_week) {
  start <- ifelse(epi_week >= SEASON_START_WEEK, epi_year, epi_year - 1L)
  paste0(start, "-", start + 1L)
}

as_whole_number <- function(x, what) {
  out <- suppressWarnings(as.numeric(x))
  bad <- !is.na(x) & (is.na(out) | out != round(out))
  if (any(bad)) {
    stop(what, " has non-integer values: ", paste(utils::head(unique(x[bad]), 5), collapse = ", "),
         call. = FALSE)
  }
  as.integer(out)
}

as_number <- function(x, what) {
  out <- suppressWarnings(as.numeric(x))
  bad <- !is.na(x) & is.na(out)
  if (any(bad)) {
    stop(what, " has non-numeric values: ", paste(utils::head(unique(x[bad]), 5), collapse = ", "),
         call. = FALSE)
  }
  out
}

transform_weekly <- function(raw) {
  require_columns(raw, WEEKLY_COLUMNS, "Weekly data")

  out <- dplyr::transmute(
    raw,
    Region          = region,
    GeographyName   = province,
    GeographyLevel  = geography_level(province),
    EpiYear         = as_whole_number(year, "year"),
    EpiWeek         = as_whole_number(week, "week"),
    WeekOrder       = as_whole_number(weekorder, "weekorder"),
    WeekEndDate     = as.Date(date),
    Virus           = virus,
    Tests           = as_whole_number(tests, "tests"),
    Detections      = as_whole_number(detections, "detections"),
    PercentPositive = as_number(percentpositive, "percentpositive")
  )

  if (any(is.na(out$WeekEndDate))) {
    stop("Weekly data has unparseable dates.", call. = FALSE)
  }

  out$SeasonLabel <- season_label(out$EpiYear, out$EpiWeek)
  out[, c("Region", "GeographyName", "GeographyLevel", "EpiYear", "EpiWeek", "WeekOrder",
          "WeekEndDate", "SeasonLabel", "Virus", "Tests", "Detections", "PercentPositive")]
}

series_name <- function(column) {
  dplyr::case_when(
    grepl("^Season_\\d{4}_\\d{4}$", column) ~ sub("^Season_(\\d{4})_(\\d{4})$", "\\1-\\2", column),
    column == "PrePandemicMaximum" ~ "Pre-pandemic maximum",
    column == "PrePandemicAverage" ~ "Pre-pandemic average",
    column == "PrePandemicMinimum" ~ "Pre-pandemic minimum",
    TRUE ~ NA_character_
  )
}

transform_baseline <- function(raw) {
  require_columns(raw, BASELINE_ID_COLUMNS, "Baseline data")
  value_columns <- setdiff(names(raw), c(BASELINE_ID_COLUMNS, "current_year_week"))
  unknown <- value_columns[is.na(series_name(value_columns))]
  if (length(unknown) > 0) {
    stop("Baseline data has unrecognised series columns: ", paste(unknown, collapse = ", "),
         call. = FALSE)
  }

  long <- tidyr::pivot_longer(
    raw,
    cols = dplyr::all_of(value_columns),
    names_to = "SeriesColumn",
    values_to = "Value",
    values_drop_na = TRUE
  )

  out <- dplyr::transmute(
    long,
    Region          = region,
    EpiWeek         = as_whole_number(Week, "Week"),
    WeekOrder       = as_whole_number(weekorder, "weekorder"),
    WeekEndDate     = as.Date(current_week_end_date),
    Virus           = virus,
    SeriesName      = series_name(SeriesColumn),
    PercentPositive = as_number(Value, "baseline value")
  )
  as.data.frame(out)
}
