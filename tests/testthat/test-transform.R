root <- normalizePath(file.path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)
fixture <- function(...) file.path(root, "tests", "fixtures", ...)

test_that("geography levels distinguish Canada, regions and provinces", {
  expect_equal(
    geography_level(c("Canada", "Atlantic", "Prairies", "Territories", "Ontario", "Northwest Territories")),
    c("Country", "Region", "Region", "Region", "Province/Territory", "Province/Territory")
  )
})

test_that("seasons start in epi week 35", {
  expect_equal(season_label(2026L, 35L), "2026-2027")
  expect_equal(season_label(2026L, 52L), "2026-2027")
  expect_equal(season_label(2027L, 1L), "2026-2027")
  expect_equal(season_label(2027L, 34L), "2026-2027")
  expect_equal(season_label(2027L, 35L), "2027-2028")
})

test_that("weekly file is typed and enriched", {
  weekly <- transform_weekly(read_rvd_csv(fixture("RVD_WeeklyData.csv")))
  expect_equal(nrow(weekly), 30)
  expect_s3_class(weekly$WeekEndDate, "Date")
  expect_type(weekly$Tests, "integer")
  expect_type(weekly$PercentPositive, "double")
  expect_true(all(weekly$SeasonLabel == "2026-2027"))

  nwt <- weekly[weekly$GeographyName == "Northwest Territories", ]
  expect_true(all(nwt$Region == "Territories"))
  expect_true(all(nwt$GeographyLevel == "Province/Territory"))
})

test_that("N/A values become NA, not zero", {
  weekly <- transform_weekly(read_rvd_csv(fixture("RVD_WeeklyData.csv")))
  hpiv <- weekly[weekly$Virus == "HPIV" & weekly$WeekEndDate == as.Date("2026-12-26"), ]
  expect_equal(nrow(hpiv), 1)
  expect_true(is.na(hpiv$Tests))
  expect_true(is.na(hpiv$Detections))
  expect_true(is.na(hpiv$PercentPositive))
})

test_that("missing columns are reported clearly", {
  raw <- read_rvd_csv(fixture("RVD_WeeklyData.csv"))
  raw$tests <- NULL
  expect_error(transform_weekly(raw), "missing columns: tests")
})

test_that("non-numeric counts are rejected", {
  raw <- read_rvd_csv(fixture("RVD_WeeklyData.csv"))
  raw$tests[1] <- "about 300"
  expect_error(transform_weekly(raw), "tests has non-integer values")
})

test_that("baseline is pivoted to one row per virus, week and series", {
  baseline <- transform_baseline(read_rvd_csv(fixture("RVD_BaselineData.csv")))
  expect_equal(nrow(baseline), 39)
  expect_setequal(
    unique(baseline$SeriesName[baseline$Virus == "SARS-CoV-2"]),
    c("2025-2026", "2024-2025", "2023-2024", "2022-2023")
  )
  expect_true("Pre-pandemic average" %in% baseline$SeriesName)
  expect_false(anyNA(baseline$PercentPositive))
})

test_that("unknown baseline series columns stop the load", {
  raw <- read_rvd_csv(fixture("RVD_BaselineData.csv"))
  raw$SomethingNew <- "1.0"
  expect_error(transform_baseline(raw), "unrecognised series columns: SomethingNew")
})

test_that("source update date is parsed", {
  stamp <- read_update_date(fixture("RVD_UpdateDate.csv"))
  expect_equal(format(stamp, "%Y-%m-%d %H:%M:%S"), "2027-01-08 10:36:15")
})
