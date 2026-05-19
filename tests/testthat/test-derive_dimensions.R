test_that("derive_census_region maps every census-region state correctly", {
  expect_equal(derive_census_region("NY"), "Northeast")
  expect_equal(derive_census_region("OH"), "Midwest")
  expect_equal(derive_census_region("TX"), "South")
  expect_equal(derive_census_region("CA"), "West")
  expect_equal(derive_census_region(c("ME", "WI", "FL", "WA")),
               c("Northeast", "Midwest", "South", "West"))
})

test_that("derive_census_region puts AK and HI in West", {
  expect_equal(derive_census_region(c("AK", "HI")), c("West", "West"))
})

test_that("derive_census_region puts DC in South (Census Bureau classification)", {
  expect_equal(derive_census_region("DC"), "South")
})

test_that("derive_census_region returns NA for unmatched inputs", {
  expect_equal(derive_census_region("PR"), NA_character_)
  expect_equal(derive_census_region(NA_character_), NA_character_)
  expect_equal(derive_census_region(""), NA_character_)
})

test_that("derive_subsector takes first three characters", {
  expect_equal(derive_subsector("ART-A01-RG"), "ART")
  expect_equal(derive_subsector("UNI-B40-RG"), "UNI")
  expect_equal(derive_subsector(c("HOS-E20-RG", "ENV-C30-AA")), c("HOS", "ENV"))
})

test_that("derive_subsector preserves NA", {
  expect_equal(derive_subsector(NA_character_), NA_character_)
})

test_that("derive_size returns correct band for each boundary", {
  expect_equal(derive_size(50000),     1L)
  expect_equal(derive_size(99999),     1L)
  expect_equal(derive_size(100000),    2L)
  expect_equal(derive_size(499998),    2L)
  expect_equal(derive_size(499999),    3L)  # case_when: first match (<999999) wins
  expect_equal(derive_size(750000),    3L)
  expect_equal(derive_size(1500000),   4L)
  expect_equal(derive_size(7500000),   5L)
  expect_equal(derive_size(20000000),  6L)
})

test_that("derive_size returns 0 for NA expenses", {
  expect_equal(derive_size(NA_real_), 0L)
})

test_that("derive_size returns integer type", {
  expect_type(derive_size(c(50000, 1500000, NA)), "integer")
})

test_that("derive_organization_type splits 501(c)(3) by foundation_code", {
  expect_equal(derive_organization_type("3", "4"),
               "501(c)(3) Private Foundations")
  expect_equal(derive_organization_type("3", "2"),
               "501(c)(3) Private Foundations")
  expect_equal(derive_organization_type("3", "3"),
               "501(c)(3) Private Foundations")
  expect_equal(derive_organization_type("3", "15"),
               "501(c)(3) Public Charities")
  expect_equal(derive_organization_type("3", NA_character_),
               "501(c)(3) Public Charities")
})

test_that("derive_organization_type formats generic subsections 1-29", {
  expect_equal(derive_organization_type("4", "0"),  "501(c)(4)")
  expect_equal(derive_organization_type("19", "0"), "501(c)(19)")
  expect_equal(derive_organization_type("29", "0"), "501(c)(29)")
})

test_that("derive_organization_type maps special subsection codes", {
  expect_equal(derive_organization_type("40", NA_character_), "501(c)(d)")
  expect_equal(derive_organization_type("50", NA_character_), "501(c)(e)")
  expect_equal(derive_organization_type("60", NA_character_), "501(c)(f)")
  expect_equal(derive_organization_type("70", NA_character_), "501(c)(k)")
})

test_that("derive_organization_type defaults NA subsection to Public Charities", {
  expect_equal(derive_organization_type(NA_character_, NA_character_),
               "501(c)(3) Public Charities")
})

test_that("derive_organization_type vectorizes across mixed inputs", {
  sc <- c("3", "3", "4", "40", NA, "3")
  fc <- c("4", "15", "0",  NA,  NA, NA)
  expect_equal(
    derive_organization_type(sc, fc),
    c("501(c)(3) Private Foundations",
      "501(c)(3) Public Charities",
      "501(c)(4)",
      "501(c)(d)",
      "501(c)(3) Public Charities",
      "501(c)(3) Public Charities")
  )
})

test_that("dimension derivations produce expected distributions on the fixture", {
  fixture_path <- testthat::test_path("..", "..", "inst", "fixtures",
                                      "bmf_master_geocoded_sample.parquet")
  skip_if_not(file.exists(fixture_path), "BMF fixture not present")
  df <- arrow::read_parquet(fixture_path)

  region <- derive_census_region(df$geo_state_abbr)
  expect_true(all(unique(stats::na.omit(region)) %in%
                    c("Northeast", "Midwest", "South", "West")))

  subsector <- derive_subsector(df$nteev2)
  expect_setequal(unique(stats::na.omit(subsector)),
                  unique(stats::na.omit(df$nteev2_subsector)))

  org_type <- derive_organization_type(df$subsection_code, df$foundation_code)
  expect_true("501(c)(3) Public Charities" %in% org_type)
  expect_true("501(c)(3) Private Foundations" %in% org_type)
  expect_false(any(is.na(org_type)))
})
