test_that("read_bmf normalizes empty-string geo cells to NA", {
  # Build a tiny in-memory fixture with mixed blank/NA/valid geo cells
  tmp <- tempfile(fileext = ".parquet")
  df <- tibble::tibble(
    ein                = c("11-1111111", "22-2222222", "33-3333333", "44-4444444"),
    nteev2             = "ART-A01-RG",
    subsection_code    = "3",
    foundation_code    = "15",
    asset_amount       = 100,
    first_year_in_bmf  = 2000L,
    last_vintage_ym    = "2024-12",
    geo_state_abbr     = c("NY", "",   NA_character_, "  "),
    geo_county         = c("Erie County", "", "Foo County",   NA_character_)
  )
  arrow::write_parquet(df, tmp)

  # county crosswalk recognizing only NY/Erie County (resolved); others -> NA.
  cxw <- tibble::tibble(
    geo_state_abbr = "NY", geo_county_raw = "Erie County",
    geo_county_fips = "36029", state_fips = "36",
    geo_county_canonical = "Erie County",
    resolution = "resolved", tiger_year = 2023L
  )

  out <- read_bmf(tmp, county_crosswalk = cxw)
  expect_equal(out$`Census State`,
               c("NY", NA_character_, NA_character_, NA_character_))
  # blank/NA county -> NA; "Foo County" not in crosswalk -> NA (unassigned)
  expect_equal(out$`Census County`,
               c("Erie County", NA_character_, NA_character_, NA_character_))
  expect_equal(out$`County FIPS`,
               c("36029", NA_character_, NA_character_, NA_character_))
})
