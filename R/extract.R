# Extract: download the RVDSS files published on Health Infobase.
#
# Source: Public Health Agency of Canada, Respiratory Virus Detection Surveillance
# System (RVDSS), Canadian respiratory virus surveillance report.
# Licence: Open Government Licence - Canada.

RVD_BASE_URL <- "https://health-infobase.canada.ca/src/data/respiratory-virus-detections"

RVD_FILES <- c(
  weekly   = "RVD_WeeklyData.csv",
  baseline = "RVD_BaselineData.csv",
  updated  = "RVD_UpdateDate.csv"
)

# Values the source uses for "no data"; all become NA.
RVD_NA_STRINGS <- c("", "NA", "N/A", "N.R.", "N.C.")

download_rvd <- function(dest_dir, base_url = RVD_BASE_URL, files = RVD_FILES) {
  dir.create(dest_dir, showWarnings = FALSE, recursive = TRUE)
  paths <- file.path(dest_dir, files)
  names(paths) <- names(files)
  for (i in seq_along(files)) {
    url <- paste0(base_url, "/", files[[i]])
    utils::download.file(url, paths[[i]], mode = "wb", quiet = TRUE)
  }
  paths
}

local_rvd <- function(source_dir, files = RVD_FILES) {
  paths <- file.path(source_dir, files)
  names(paths) <- names(files)
  missing <- paths[!file.exists(paths)]
  if (length(missing) > 0) {
    stop("Source files not found: ", paste(missing, collapse = ", "), call. = FALSE)
  }
  paths
}

read_rvd_csv <- function(path) {
  readr::read_csv(
    path,
    col_types = readr::cols(.default = readr::col_character()),
    na = RVD_NA_STRINGS,
    trim_ws = TRUE,
    progress = FALSE
  )
}

read_update_date <- function(path) {
  text <- trimws(readLines(path, n = 1L, warn = FALSE))
  stamp <- as.POSIXct(text, format = "%Y-%m-%d %H:%M:%S", tz = "UTC")
  if (is.na(stamp)) {
    stop("Could not parse source update date: '", text, "'", call. = FALSE)
  }
  stamp
}
