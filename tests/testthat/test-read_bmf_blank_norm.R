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
    geo_county         = c("Erie", "", "Foo County",   NA_character_)
  )
  arrow::write_parquet(df, tmp)

  crosswalk <- system.file("lookups", "cbsa_crosswalk.parquet",
                           package = "sectorinbriefdata")
  skip_if(!nzchar(crosswalk) || !file.exists(crosswalk),
          "cbsa_crosswalk.parquet not found in installed package")
  out <- read_bmf(tmp, cbsa_crosswalk = crosswalk)
  expect_equal(out$`Census State`,
               c("NY", NA_character_, NA_character_, NA_character_))
  expect_equal(out$`Census County`,
               c("Erie", NA_character_, "Foo County", NA_character_))
})
