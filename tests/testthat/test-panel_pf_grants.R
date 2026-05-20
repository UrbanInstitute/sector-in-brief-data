.pfg_org <- function(eins = c("A", "B")) {
  tibble::tibble(
    ein = eins,
    `Organization Type` = "Private Foundation",
    Subsector = "PHIL",
    Size = 4L,
    `Census Region` = "Northeast",
    `Census State`  = "NY",
    `Census County` = "Cook County",
    `Metro/Micro Area` = NA_character_
  )
}

.pfg_pf_row <- function(ein, tax_year, paid = 1000) {
  tibble::tibble(
    ein = ein, tax_year = as.integer(tax_year), source_form = "990pf",
    total_revenue = NA_real_, total_expenses = NA_real_,
    total_assets = NA_real_, total_contributions = NA_real_,
    total_benefits = NA_real_,
    contributions_paid = paid, contributions_received = NA_real_
  )
}

test_that("build_pf_grants sums contributions_paid across EINs in a cell", {
  pf <- dplyr::bind_rows(
    .pfg_pf_row("A", 2020, paid = 1000),
    .pfg_pf_row("B", 2020, paid = 2500)
  )
  out <- build_pf_grants(pf, .pfg_org(), years = 2020L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$`Total Contributions`, 3500)
})

test_that("build_pf_grants groups by Year", {
  pf <- dplyr::bind_rows(
    .pfg_pf_row("A", 2020, paid = 100),
    .pfg_pf_row("A", 2021, paid = 200)
  )
  out <- build_pf_grants(pf, .pfg_org("A"), years = c(2020L, 2021L))
  by_year <- stats::setNames(out$`Total Contributions`, out$Year)
  expect_equal(by_year[["2020"]], 100)
  expect_equal(by_year[["2021"]], 200)
})

test_that("build_pf_grants filters years outside the requested range", {
  pf <- dplyr::bind_rows(
    .pfg_pf_row("A", 1995, paid = 1),
    .pfg_pf_row("A", 2020, paid = 999)
  )
  out <- build_pf_grants(pf, .pfg_org("A"), years = 2020L)
  expect_equal(unique(out$Year), 2020L)
  expect_equal(out$`Total Contributions`, 999)
})

test_that("build_pf_grants preserves NA when every row is NA", {
  pf <- dplyr::bind_rows(
    .pfg_pf_row("A", 2020, paid = NA_real_),
    .pfg_pf_row("B", 2020, paid = NA_real_)
  )
  out <- build_pf_grants(pf, .pfg_org(), years = 2020L)
  expect_true(is.na(out$`Total Contributions`))
})

test_that("build_pf_grants drops PF rows whose EIN isn't in org_metadata", {
  pf <- dplyr::bind_rows(
    .pfg_pf_row("A", 2020, paid = 100),
    .pfg_pf_row("ORPHAN", 2020, paid = 9999)
  )
  out <- build_pf_grants(pf, .pfg_org("A"), years = 2020L)
  expect_equal(out$`Total Contributions`, 100)
})

test_that("build_pf_grants emits the contract schema", {
  pf <- .pfg_pf_row("A", 2020)
  out <- build_pf_grants(pf, .pfg_org("A"), years = 2020L)
  expect_equal(colnames(out),
               c("Organization Type", "Subsector", "Size",
                 "Census Region", "Census State", "Census County",
                 "Metro/Micro Area", "Year", "Total Contributions"))
  expect_type(out$Year, "integer")
  expect_type(out$`Total Contributions`, "double")
})
