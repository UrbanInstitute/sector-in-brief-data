.pri_org <- function(eins = c("A", "B")) {
  tibble::tibble(
    ein = eins,
    `Organization Type` = "Private Foundation",
    Subsector = "PHIL",
    Size = 5L,
    `Census Region` = "West",
    `Census State`  = "CA",
    `Census County` = "Los Angeles County",
    `Metro/Micro Area` = "Los Angeles-Long Beach-Anaheim, CA"
  )
}

.pri_row <- function(ein, tax_year, amt = 1000) {
  tibble::tibble(
    ein = ein, tax_year = as.integer(tax_year),
    program_related_investments_total = amt
  )
}

test_that("build_pf_pri sums PRI totals across EINs in a cell", {
  pri <- dplyr::bind_rows(.pri_row("A", 2021, 1000), .pri_row("B", 2021, 2500))
  out <- build_pf_pri(pri, .pri_org(), years = 2021L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$`Total Program-Related Investments`, 3500)
})

test_that("build_pf_pri groups by Year", {
  pri <- dplyr::bind_rows(.pri_row("A", 2021, 100), .pri_row("A", 2022, 200))
  out <- build_pf_pri(pri, .pri_org("A"), years = c(2021L, 2022L))
  by_year <- stats::setNames(out$`Total Program-Related Investments`, out$Year)
  expect_equal(by_year[["2021"]], 100)
  expect_equal(by_year[["2022"]], 200)
})

test_that("build_pf_pri filters years outside the requested range", {
  pri <- dplyr::bind_rows(.pri_row("A", 2020, 1), .pri_row("A", 2021, 999))
  out <- build_pf_pri(pri, .pri_org("A"), years = 2021L)
  expect_equal(unique(out$Year), 2021L)
  expect_equal(out$`Total Program-Related Investments`, 999)
})

test_that("build_pf_pri preserves NA when every row is NA", {
  pri <- dplyr::bind_rows(.pri_row("A", 2021, NA_real_), .pri_row("B", 2021, NA_real_))
  out <- build_pf_pri(pri, .pri_org(), years = 2021L)
  expect_true(is.na(out$`Total Program-Related Investments`))
})

test_that("build_pf_pri drops rows whose EIN isn't in org_metadata", {
  pri <- dplyr::bind_rows(.pri_row("A", 2021, 100), .pri_row("ORPHAN", 2021, 9999))
  out <- build_pf_pri(pri, .pri_org("A"), years = 2021L)
  expect_equal(out$`Total Program-Related Investments`, 100)
})

test_that("build_pf_pri emits the contract schema", {
  out <- build_pf_pri(.pri_row("A", 2021), .pri_org("A"), years = 2021L)
  expect_equal(colnames(out),
               c("Organization Type", "Subsector", "Size",
                 "Census Region", "Census State", "Census County",
                 "Metro/Micro Area", "Year", "Total Program-Related Investments"))
  expect_type(out$Year, "integer")
  expect_type(out$`Total Program-Related Investments`, "double")
})
