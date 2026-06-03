.xw <- function() tibble::tibble(
  geo_state_abbr       = c("MI", "MI", "MI", "NY"),
  geo_county_raw       = c("Wayne", "Wayne County", "Oakland County", "Monroe County"),
  geo_county_fips      = c("26163", "26163", "26125", "36055"),
  state_fips           = c("26", "26", "26", "36"),
  geo_county_canonical = c("Wayne County", "Wayne County", "Oakland County", "Monroe County")
)

test_that("read_county_crosswalk validates schema and coerces to character", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(
      geo_state_abbr = "MI", geo_county_raw = "Wayne",
      geo_county_fips = 26163L, state_fips = 26L,        # ints on disk
      geo_county_canonical = "Wayne County"
    ), tmp)
  out <- read_county_crosswalk(tmp)
  expect_equal(names(out), c("geo_state_abbr", "geo_county_raw", "geo_county_fips",
                             "state_fips", "geo_county_canonical"))
  expect_type(out$geo_county_fips, "character")  # leading zeros must survive
  expect_equal(out$geo_county_fips, "26163")
})

test_that("read_county_crosswalk errors on a missing expected column", {
  tmp <- tempfile(fileext = ".parquet")
  # all columns present except geo_county_fips
  arrow::write_parquet(
    tibble::tibble(geo_state_abbr = "MI", geo_county_raw = "Wayne",
                   state_fips = "26", geo_county_canonical = "Wayne County"), tmp)
  expect_error(read_county_crosswalk(tmp), "geo_county_fips")
})

test_that("canonicalize_county_label maps bare to suffixed, same-name across states stays scoped", {
  xw <- .xw()
  out <- canonicalize_county_label(c("MI", "MI", "NY"),
                                   c("Wayne", "Oakland County", "Monroe County"), xw)
  expect_equal(out, c("Wayne County", "Oakland County", "Monroe County"))
})

test_that("canonicalize_county_label leaves unmatched labels and NA unchanged", {
  xw <- .xw()
  out <- canonicalize_county_label(c("MI", "CA", NA),
                                   c("Nonesuch County", "Los Angeles County", NA), xw)
  expect_equal(out, c("Nonesuch County", "Los Angeles County", NA))
})

test_that("canonicalize_county_label does not merge across states (no MI->NY bleed)", {
  xw <- .xw()
  # "Monroe County" only canonical for NY in this xw; an MI "Monroe County" with
  # no MI entry must NOT pick up the NY mapping — it stays as given.
  out <- canonicalize_county_label("MI", "Monroe County", xw)
  expect_equal(out, "Monroe County")
})

test_that("build_county_crosswalk emits distinct canonical (state, county, FIPS)", {
  out <- build_county_crosswalk(.xw())
  expect_equal(names(out), c("Census State", "Census County", "County FIPS"))
  # the two raw Wayne rows collapse to one canonical row
  expect_equal(nrow(out), 3L)
  wayne <- out[out$`Census County` == "Wayne County", ]
  expect_equal(nrow(wayne), 1L)
  expect_equal(wayne$`County FIPS`, "26163")
})

# --- integration with read_bmf -------------------------------------------------

fixture <- testthat::test_path("..", "..", "inst", "fixtures",
                               "bmf_master_geocoded_sample.parquet")
crosswalk <- testthat::test_path("..", "..", "inst", "lookups",
                                 "cbsa_crosswalk.parquet")

test_that("read_bmf canonicalizes Census County via the crosswalk", {
  skip_if_not(file.exists(fixture))
  base <- read_bmf(fixture, cbsa_crosswalk = crosswalk)
  pick <- base[!is.na(base$`Census State`) & !is.na(base$`Census County`), ][1, ]

  xw <- tibble::tibble(
    geo_state_abbr       = pick$`Census State`,
    geo_county_raw       = pick$`Census County`,
    geo_county_fips      = "99999",
    state_fips           = "99",
    geo_county_canonical = "Canon Sentinel County"
  )
  out <- read_bmf(fixture, cbsa_crosswalk = crosswalk, county_crosswalk = xw)

  expect_gt(sum(out$`Census County` == "Canon Sentinel County", na.rm = TRUE), 0L)
  # the original (state, county) label was remapped, not duplicated
  expect_equal(sum(out$`Census State` == pick$`Census State` &
                     out$`Census County` == pick$`Census County`, na.rm = TRUE), 0L)
  # row count is unchanged — canonicalization relabels, never drops/fans out
  expect_equal(nrow(out), nrow(base))
})
