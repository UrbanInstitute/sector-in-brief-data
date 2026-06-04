fixture <- testthat::test_path("..", "..", "inst", "fixtures",
                               "bmf_master_geocoded_sample.parquet")
county_xw <- testthat::test_path("..", "..", "inst", "fixtures",
                                 "county_fips_crosswalk_sample.parquet")
cbsa_xw <- testthat::test_path("..", "..", "inst", "fixtures",
                               "cbsa_crosswalk_sample.parquet")

read_full <- function() read_bmf(fixture, cbsa_crosswalk = cbsa_xw,
                                 county_crosswalk = county_xw)

test_that("read_bmf returns the canonical schema (incl. codes)", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw) && file.exists(cbsa_xw))
  out <- read_full()
  expected <- c("ein", "nteev2", "subsection_code", "foundation_code",
                "asset_amount", "org_year_first", "org_year_last",
                "Census State", "Census County", "County FIPS",
                "Metro/Micro Area", "CBSA Code",
                "Census Region", "Subsector", "Organization Type")
  expect_equal(colnames(out), expected)
})

test_that("read_bmf normalizes ein to XX-XXXXXXX", {
  skip_if_not(file.exists(fixture))
  out <- read_full()
  good <- out$ein[!is.na(out$ein)]
  expect_true(all(nchar(good) == 10))
  expect_true(all(grepl("^[0-9]{2}-[0-9]{7}$", good)))
})

test_that("read_bmf parses org_year_last from last_vintage_ym YYYY-MM", {
  skip_if_not(file.exists(fixture))
  out <- read_full()
  yrs <- stats::na.omit(out$org_year_last)
  expect_true(all(yrs >= 1989 & yrs <= as.integer(format(Sys.Date(), "%Y"))))
  expect_type(yrs, "integer")
})

test_that("read_bmf produces dashboard-canonical dimension values", {
  skip_if_not(file.exists(fixture))
  out <- read_full()
  expect_true(all(stats::na.omit(out$`Census Region`) %in%
                    c("Northeast", "Midwest", "South", "West")))
  expect_false(any(is.na(out$`Organization Type`)))
})

test_that("read_bmf attaches County FIPS; NA exactly where Census County is NA", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw))
  out <- read_full()
  expect_true(all(is.na(out$`County FIPS`) == is.na(out$`Census County`)))
  expect_gt(sum(!is.na(out$`County FIPS`)), 0L)
  # FIPS are 5-char strings with leading zeros preserved
  fips <- out$`County FIPS`[!is.na(out$`County FIPS`)]
  expect_true(all(nchar(fips) == 5))
})

test_that("read_bmf is collision-proof: Baltimore city vs County keep distinct FIPS", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw))
  out <- read_full()
  balt <- unique(out[!is.na(out$`Census County`) &
                       grepl("Baltimore", out$`Census County`),
                     c("Census County", "County FIPS")])
  expect_true(all(c("24510", "24005") %in% balt$`County FIPS`))
  expect_equal(length(unique(balt$`County FIPS`)),
               nrow(balt))  # one FIPS per distinct county name
})

test_that("read_bmf nulls ambiguous labels (unassigned), not pass them through raw", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw))
  out  <- read_full()
  base <- read_bmf(fixture)                     # no crosswalk -> raw passthrough
  # ambiguous bare 'Baltimore' is present (raw) in base but resolved away in out
  expect_gt(sum(base$`Census County` == "Baltimore", na.rm = TRUE), 0L)
  expect_equal(sum(out$`Census County` == "Baltimore", na.rm = TRUE), 0L)
  # nulling ambiguous labels strictly increases the unassigned count
  expect_gt(sum(is.na(out$`Census County`)), sum(is.na(base$`Census County`)))
})

test_that("read_bmf FIPS-keyed CBSA join has reasonable coverage", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw) && file.exists(cbsa_xw))
  out <- read_full()
  assigned <- out[!is.na(out$`Census County`), ]
  match_rate <- mean(!is.na(assigned$`Metro/Micro Area`))
  expect_gt(match_rate, 0.80)                          # rest are rural counties
  # CBSA Code present iff Metro/Micro Area present
  expect_true(all(is.na(out$`CBSA Code`) == is.na(out$`Metro/Micro Area`)))
})

test_that("read_bmf NA-on-miss for CBSA when county is unassigned/absent", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw) && file.exists(cbsa_xw))
  out <- read_full()
  no_county <- is.na(out$`Census County`)
  expect_true(all(is.na(out$`Metro/Micro Area`[no_county])))
})

test_that("read_bmf graceful degradation: no crosswalks -> raw county, NA codes", {
  skip_if_not(file.exists(fixture))
  out <- read_bmf(fixture)
  expect_true(all(is.na(out$`County FIPS`)))
  expect_true(all(is.na(out$`Metro/Micro Area`)))
  expect_true(all(is.na(out$`CBSA Code`)))
})

test_that("read_bmf does not drop or fan out rows under canonicalization", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw))
  expect_equal(nrow(read_full()), nrow(read_bmf(fixture)))
})
