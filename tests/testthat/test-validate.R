root <- normalizePath(file.path("..", ".."))
for (f in list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE)) source(f)
fixture <- function(...) file.path(root, "tests", "fixtures", ...)

weekly_fixture <- function() transform_weekly(read_rvd_csv(fixture("RVD_WeeklyData.csv")))
failed <- function(results, check) results$failed[results$check == check]

test_that("fixture data passes every check", {
  results <- validate_weekly(weekly_fixture())
  expect_true(all(results$failed == 0))
  expect_silent(stop_on_errors(results))
})

test_that("duplicate rows are caught", {
  weekly <- weekly_fixture()
  results <- validate_weekly(rbind(weekly, weekly[1, ]))
  expect_equal(failed(results, "unique week/geography/virus"), 1)
  expect_error(stop_on_errors(results), "unique week/geography/virus")
})

test_that("detections above tests are caught", {
  weekly <- weekly_fixture()
  weekly$Detections[1] <- weekly$Tests[1] + 1L
  expect_equal(failed(validate_weekly(weekly), "detections do not exceed tests"), 1)
})

test_that("a geography moving between regions is caught", {
  weekly <- weekly_fixture()
  weekly$Region[weekly$GeographyName == "Northwest Territories"][1] <- "Prairies"
  expect_equal(failed(validate_weekly(weekly), "each geography belongs to one region"), 1)
})

test_that("published percent that disagrees with counts is a warning, not an error", {
  weekly <- weekly_fixture()
  weekly$PercentPositive[1] <- weekly$PercentPositive[1] + 2
  results <- validate_weekly(weekly)
  expect_equal(failed(results, "published percent matches detections/tests"), 1)
  expect_silent(stop_on_errors(results))
})

test_that("empty input is an error", {
  results <- validate_weekly(weekly_fixture()[0, ])
  expect_error(stop_on_errors(results), "has rows")
})

test_that("baseline checks pass on fixture and catch duplicates", {
  baseline <- transform_baseline(read_rvd_csv(fixture("RVD_BaselineData.csv")))
  expect_true(all(validate_baseline(baseline)$failed == 0))
  expect_equal(failed(validate_baseline(rbind(baseline, baseline[1, ])), "unique baseline virus/week/series"), 1)
})
