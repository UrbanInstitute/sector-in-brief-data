fixture <- testthat::test_path("..", "..", "inst", "fixtures",
                               "bmf_master_geocoded_sample.parquet")
crosswalk <- testthat::test_path("..", "..", "inst", "lookups",
                                 "cbsa_crosswalk.parquet")

test_that("read_bmf returns the canonical schema", {
  skip_if_not(file.exists(fixture))
  skip_if_not(file.exists(crosswalk))

  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)

  expected <- c("ein", "nteev2", "subsection_code", "foundation_code",
                "asset_amount", "org_year_first", "org_year_last",
                "Census State", "Census County", "Metro/Micro Area",
                "Census Region", "Subsector", "Organization Type")
  expect_equal(colnames(out), expected)
})

test_that("read_bmf normalizes ein to XX-XXXXXXX", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  # nccs_normalize_ein produces 10-char dashed form for valid inputs.
  good <- out$ein[!is.na(out$ein)]
  expect_true(all(nchar(good) == 10))
  expect_true(all(grepl("^[0-9]{2}-[0-9]{7}$", good)))
})

test_that("read_bmf parses org_year_last from last_vintage_ym YYYY-MM", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  yrs <- stats::na.omit(out$org_year_last)
  expect_true(all(yrs >= 1989 & yrs <= as.integer(format(Sys.Date(), "%Y"))))
  expect_type(yrs, "integer")
})

test_that("read_bmf produces dashboard-canonical dimension values", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  expect_true(all(stats::na.omit(out$`Census Region`) %in%
                    c("Northeast", "Midwest", "South", "West")))
  expect_false(any(is.na(out$`Organization Type`)))
})

test_that("read_bmf joins CBSA with reasonable coverage on the fixture", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  geocoded <- out[!is.na(out$`Census State`) & !is.na(out$`Census County`), ]
  match_rate <- mean(!is.na(geocoded$`Metro/Micro Area`))
  # 70% of geocoded rows should land in some CBSA. (Rest are rural counties.)
  expect_gt(match_rate, 0.70)
})

test_that("read_bmf NA-on-miss for Metro/Micro Area when geo is missing", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  no_geo <- is.na(out$`Census State`) | is.na(out$`Census County`)
  expect_true(all(is.na(out$`Metro/Micro Area`[no_geo])))
})
