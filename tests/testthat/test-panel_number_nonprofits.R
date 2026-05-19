test_that("build_number_nonprofits counts orgs active in each year", {
  org <- tibble::tibble(
    ein = c("A","B","C"),
    org_year_first = c(2000L, 2005L, 2010L),
    org_year_last  = c(2024L, 2010L, 2024L),
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "ART",
    Size = 1L,
    `Census Region` = "Northeast",
    `Census State` = "NY",
    `Census County` = "Cook County",
    `Metro/Micro Area` = NA_character_
  )
  out <- build_number_nonprofits(org, years = c(2003L, 2008L, 2015L))
  expect_setequal(unique(out$Year), c(2003L, 2008L, 2015L))
  # 2003: only A; 2008: A+B; 2015: A+C
  counts <- stats::setNames(out$`Number of Nonprofits`, out$Year)
  expect_equal(counts[["2003"]], 1L)
  expect_equal(counts[["2008"]], 2L)
  expect_equal(counts[["2015"]], 2L)
})

test_that("build_number_nonprofits groups across all 7 dimensions", {
  org <- tibble::tibble(
    ein = c("A","B"),
    org_year_first = 2000L, org_year_last = 2024L,
    `Organization Type` = c("501(c)(3) Public Charities", "501(c)(4)"),
    Subsector = "ART", Size = 1L,
    `Census Region` = "Northeast", `Census State` = "NY",
    `Census County` = "Cook County", `Metro/Micro Area` = NA_character_
  )
  out <- build_number_nonprofits(org, years = 2020L)
  expect_equal(nrow(out), 2L)
  expect_setequal(out$`Organization Type`,
                  c("501(c)(3) Public Charities", "501(c)(4)"))
})

test_that("build_number_nonprofits drops rows missing the BMF window", {
  org <- tibble::tibble(
    ein = c("A","B"),
    org_year_first = c(2000L, NA_integer_),
    org_year_last  = c(2024L, 2024L),
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "ART", Size = 1L,
    `Census Region` = "Northeast", `Census State` = "NY",
    `Census County` = "Cook County", `Metro/Micro Area` = NA_character_
  )
  out <- build_number_nonprofits(org, years = 2020L)
  expect_equal(sum(out$`Number of Nonprofits`), 1L)
})

test_that("build_number_nonprofits emits expected schema (columns + types)", {
  org <- tibble::tibble(
    ein = "A",
    org_year_first = 2000L, org_year_last = 2024L,
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "ART", Size = 1L,
    `Census Region` = "Northeast", `Census State` = "NY",
    `Census County` = "Cook County", `Metro/Micro Area` = NA_character_
  )
  out <- build_number_nonprofits(org, years = 2020L)
  expect_equal(colnames(out), c("Organization Type", "Subsector", "Size",
                                "Census Region", "Census State", "Census County",
                                "Metro/Micro Area", "Year", "Number of Nonprofits"))
  expect_type(out$Year, "integer")
  expect_type(out$`Number of Nonprofits`, "integer")
})
