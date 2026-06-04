.xw <- function() tibble::tibble(
  geo_state_abbr       = c("MI", "MI", "MI", "NY", "MD"),
  geo_county_raw       = c("Wayne", "Wayne County", "Oakland County", "Monroe County", "Baltimore"),
  geo_county_fips      = c("26163", "26163", "26125", "36055", NA),
  state_fips           = c("26", "26", "26", "36", "24"),
  geo_county_canonical = c("Wayne County", "Wayne County", "Oakland County", "Monroe County", NA),
  resolution           = c("resolved", "resolved", "resolved", "resolved", "ambiguous"),
  tiger_year           = c(2023L, 2023L, 2023L, 2023L, 2023L)
)

test_that("read_county_crosswalk validates schema and coerces FIPS to character", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(
      geo_state_abbr = "MI", geo_county_raw = "Wayne",
      geo_county_fips = 26163L, state_fips = 26L,        # ints on disk
      geo_county_canonical = "Wayne County",
      resolution = "resolved", tiger_year = 2023L
    ), tmp)
  out <- read_county_crosswalk(tmp)
  expect_equal(names(out), c("geo_state_abbr", "geo_county_raw", "geo_county_fips",
                             "state_fips", "geo_county_canonical",
                             "resolution", "tiger_year"))
  expect_type(out$geo_county_fips, "character")  # leading zeros must survive
  expect_equal(out$geo_county_fips, "26163")
  expect_type(out$tiger_year, "integer")
})

test_that("read_county_crosswalk errors on a missing expected column", {
  tmp <- tempfile(fileext = ".parquet")
  # all columns present except resolution
  arrow::write_parquet(
    tibble::tibble(geo_state_abbr = "MI", geo_county_raw = "Wayne",
                   geo_county_fips = "26163", state_fips = "26",
                   geo_county_canonical = "Wayne County", tiger_year = 2023L), tmp)
  expect_error(read_county_crosswalk(tmp), "resolution")
})

test_that("canonicalize_county_label maps bare to suffixed, scoped per state", {
  xw <- .xw()
  out <- canonicalize_county_label(c("MI", "MI", "NY"),
                                   c("Wayne", "Oakland County", "Monroe County"), xw)
  expect_equal(out, c("Wayne County", "Oakland County", "Monroe County"))
})

test_that("canonicalize_county_label returns NA for non-resolved / unknown labels", {
  xw <- .xw()
  # ambiguous "Baltimore" -> NA (unassigned); unknown label -> NA; NA stays NA
  out <- canonicalize_county_label(c("MD", "MI", NA),
                                   c("Baltimore", "Nonesuch County", NA), xw)
  expect_equal(out, c(NA_character_, NA_character_, NA_character_))
})

test_that("canonicalize_county_label does not merge across states (no MI->NY bleed)", {
  xw <- .xw()
  out <- canonicalize_county_label("MI", "Monroe County", xw)
  expect_equal(out, NA_character_)
})

test_that("county_fips_for_label returns FIPS, NA for non-resolved/unknown", {
  xw <- .xw()
  out <- county_fips_for_label(c("MI", "MI", "MD", "MI"),
                               c("Wayne", "Oakland County", "Baltimore", "Nope"), xw)
  expect_equal(out, c("26163", "26125", NA_character_, NA_character_))
})

test_that("build_county_crosswalk emits the audit schema incl. raw + resolution", {
  out <- build_county_crosswalk(.xw())
  expect_equal(names(out), c("Census State", "County (raw)", "Census County",
                             "County FIPS", "Resolution"))
  # the two raw Wayne labels each keep their raw row, both pointing at one FIPS
  wayne <- out[out$`Census County` %in% "Wayne County", ]
  expect_setequal(wayne$`County (raw)`, c("Wayne", "Wayne County"))
  expect_true(all(wayne$`County FIPS` == "26163"))
  # ambiguous Baltimore is preserved with NA FIPS + its resolution verdict
  balt <- out[out$`County (raw)` == "Baltimore", ]
  expect_true(is.na(balt$`County FIPS`))
  expect_equal(balt$Resolution, "ambiguous")
})

# --- CBSA crosswalk ------------------------------------------------------------

.cb <- function() tibble::tibble(
  county_fips      = c("26163", "48301"),
  county_name      = c("Wayne County", "Loving County"),
  cbsa_code        = c("19820", NA),
  cbsa_title       = c("Detroit-Warren-Dearborn, MI", NA),
  cbsa_type        = c("Metropolitan Statistical Area", NA),
  central_outlying = c("Central", NA),
  csa_code         = c("220", NA),
  csa_title        = c("Detroit-Warren-Ann Arbor, MI", NA),
  delineation_year = c(2023L, 2023L)
)

test_that("read_cbsa_crosswalk validates schema and keeps FIPS as character", {
  tmp <- tempfile(fileext = ".parquet")
  cb <- .cb()
  cb$county_fips <- as.integer(c(26163L, 48301L))  # ints on disk -> must coerce
  arrow::write_parquet(cb, tmp)
  out <- read_cbsa_crosswalk(tmp)
  expect_type(out$county_fips, "character")
  expect_equal(out$county_fips[1], "26163")
  expect_type(out$delineation_year, "integer")
})

test_that("read_cbsa_crosswalk errors on a missing expected column", {
  tmp <- tempfile(fileext = ".parquet")
  cb <- .cb()[, setdiff(names(.cb()), "cbsa_code")]
  arrow::write_parquet(cb, tmp)
  expect_error(read_cbsa_crosswalk(tmp), "cbsa_code")
})

test_that("build_cbsa_crosswalk drops county_name and emits dashboard names", {
  out <- build_cbsa_crosswalk(.cb())
  expect_equal(names(out), c("County FIPS", "CBSA Code", "Metro/Micro Area",
                             "CBSA Type", "Central/Outlying", "CSA Code",
                             "CSA Title", "Delineation Year"))
  expect_false("county_name" %in% names(out))
  detroit <- out[out$`County FIPS` == "26163", ]
  expect_equal(detroit$`Metro/Micro Area`, "Detroit-Warren-Dearborn, MI")
})

# --- integration with read_bmf -------------------------------------------------

fixture <- testthat::test_path("..", "..", "inst", "fixtures",
                               "bmf_master_geocoded_sample.parquet")
county_xw <- testthat::test_path("..", "..", "inst", "fixtures",
                                 "county_fips_crosswalk_sample.parquet")
cbsa_xw <- testthat::test_path("..", "..", "inst", "fixtures",
                               "cbsa_crosswalk_sample.parquet")

test_that("read_bmf canonicalizes Census County + attaches FIPS via the crosswalk", {
  skip_if_not(file.exists(fixture) && file.exists(county_xw))
  base <- read_bmf(fixture)                                   # no crosswalk
  out  <- read_bmf(fixture, cbsa_crosswalk = cbsa_xw, county_crosswalk = county_xw)

  # row count is unchanged — canonicalization relabels, never drops/fans out
  expect_equal(nrow(out), nrow(base))
  # every non-NA county now carries a FIPS; FIPS NA exactly where county is NA
  expect_true(all(is.na(out$`County FIPS`) == is.na(out$`Census County`)))
  # at least one bare->suffixed canonicalization happened
  expect_gt(sum(out$`Census County` == "Wayne County", na.rm = TRUE), 0L)
})
