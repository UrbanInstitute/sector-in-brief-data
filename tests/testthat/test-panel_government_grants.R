.gg_org <- function(eins = c("A", "B")) {
  tibble::tibble(
    ein = eins,
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "EDU",
    Size = 4L,
    `Census Region` = "Northeast",
    `Census State`  = "NY",
    `Census County` = "Kings County",
    `Metro/Micro Area` = NA_character_
  )
}

.gg_row <- function(ein, tax_year, amt = 1000) {
  tibble::tibble(
    ein = ein, tax_year = as.integer(tax_year),
    government_grants = amt
  )
}

test_that("build_government_grants sums government_grants across EINs in a cell", {
  gg <- dplyr::bind_rows(.gg_row("A", 2021, 1000), .gg_row("B", 2021, 2500))
  out <- build_government_grants(gg, .gg_org(), years = 2021L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$`Total Government Grants`, 3500)
})

test_that("build_government_grants groups by Year", {
  gg <- dplyr::bind_rows(.gg_row("A", 2021, 100), .gg_row("A", 2022, 200))
  out <- build_government_grants(gg, .gg_org("A"), years = c(2021L, 2022L))
  by_year <- stats::setNames(out$`Total Government Grants`, out$Year)
  expect_equal(by_year[["2021"]], 100)
  expect_equal(by_year[["2022"]], 200)
})

test_that("build_government_grants filters years outside the requested range", {
  gg <- dplyr::bind_rows(.gg_row("A", 2020, 1), .gg_row("A", 2021, 999))
  out <- build_government_grants(gg, .gg_org("A"), years = 2021L)
  expect_equal(unique(out$Year), 2021L)
  expect_equal(out$`Total Government Grants`, 999)
})

test_that("build_government_grants preserves NA when every row is NA", {
  gg <- dplyr::bind_rows(.gg_row("A", 2021, NA_real_), .gg_row("B", 2021, NA_real_))
  out <- build_government_grants(gg, .gg_org(), years = 2021L)
  expect_true(is.na(out$`Total Government Grants`))
})

test_that("build_government_grants drops rows whose EIN isn't in org_metadata", {
  gg <- dplyr::bind_rows(.gg_row("A", 2021, 100), .gg_row("ORPHAN", 2021, 9999))
  out <- build_government_grants(gg, .gg_org("A"), years = 2021L)
  expect_equal(out$`Total Government Grants`, 100)
})

test_that("build_government_grants emits the contract schema", {
  out <- build_government_grants(.gg_row("A", 2021), .gg_org("A"), years = 2021L)
  expect_equal(colnames(out),
               c("Organization Type", "Subsector", "Size",
                 "Census Region", "Census State", "Census County",
                 "Metro/Micro Area", "Year", "Total Government Grants"))
  expect_type(out$Year, "integer")
  expect_type(out$`Total Government Grants`, "double")
})
