.fin_org <- function(eins = c("A", "B")) {
  tibble::tibble(
    ein = eins,
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "ART",
    Size = 1L,
    `Census Region` = "Northeast",
    `Census State`  = "NY",
    `Census County` = "Cook County",
    `Metro/Micro Area` = NA_character_,
    `County FIPS` = NA_character_,
    `CBSA Code` = NA_character_
  )
}

.fin_core_row <- function(ein, tax_year, rev = 100, exp = 80, ast = 1000, ben = 20) {
  tibble::tibble(
    ein = ein, tax_year = as.integer(tax_year), source_form = "990combined",
    total_revenue = rev, total_expenses = exp, total_assets = ast,
    total_contributions = NA_real_, total_benefits = ben
  )
}

test_that("build_finances sums metrics across EINs sharing a dimension cell", {
  core <- dplyr::bind_rows(
    .fin_core_row("A", 2020, rev = 100, exp = 80,  ast = 1000, ben = 20),
    .fin_core_row("B", 2020, rev = 200, exp = 150, ast = 5000, ben = 40)
  )
  out <- build_finances(core, NULL, .fin_org(), years = 2020L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$`Total Revenues`, 300)
  expect_equal(out$`Total Expenses`, 230)
  expect_equal(out$`Total Assets`,   6000)
  expect_equal(out$`Total Benefits`, 60)
})

test_that("build_finances groups by Year", {
  core <- dplyr::bind_rows(
    .fin_core_row("A", 2020, rev = 100),
    .fin_core_row("A", 2021, rev = 200)
  )
  out <- build_finances(core, NULL, .fin_org("A"), years = c(2020L, 2021L))
  expect_setequal(out$Year, c(2020L, 2021L))
  rev_by_year <- stats::setNames(out$`Total Revenues`, out$Year)
  expect_equal(rev_by_year[["2020"]], 100)
  expect_equal(rev_by_year[["2021"]], 200)
})

test_that("build_finances filters out years outside the requested range", {
  core <- dplyr::bind_rows(
    .fin_core_row("A", 2010, rev = 1),
    .fin_core_row("A", 2020, rev = 100)
  )
  out <- build_finances(core, NULL, .fin_org("A"), years = 2020L)
  expect_equal(unique(out$Year), 2020L)
})

test_that("build_finances keeps Total Benefits NA when every row is NA", {
  # Mirrors the pre-2012 case: lines 6/8/9 absent, so total_benefits is NA
  # on every row. The aggregate must stay NA, not collapse to 0.
  core <- dplyr::bind_rows(
    .fin_core_row("A", 1995, ben = NA_real_),
    .fin_core_row("B", 1995, ben = NA_real_)
  )
  out <- build_finances(core, NULL, .fin_org(), years = 1995L)
  expect_true(is.na(out$`Total Benefits`))
  expect_equal(out$`Total Revenues`, 200)  # other metrics still aggregate
})

test_that("build_finances stacks 990 and 990PF rows", {
  c990 <- .fin_core_row("A", 2020, rev = 100, ben = 20)
  cpf  <- tibble::tibble(
    ein = "B", tax_year = 2020L, source_form = "990pf",
    total_revenue = 500, total_expenses = 300, total_assets = 9000,
    total_contributions = NA_real_, total_benefits = NA_real_
  )
  out <- build_finances(c990, cpf, .fin_org(), years = 2020L)
  expect_equal(out$`Total Revenues`, 600)
  expect_equal(out$`Total Benefits`, 20)  # PF contributes NA, 990 contributes 20
})

test_that("build_finances drops core rows whose EIN isn't in org_metadata", {
  core <- dplyr::bind_rows(
    .fin_core_row("A", 2020, rev = 100),
    .fin_core_row("ORPHAN", 2020, rev = 999)
  )
  out <- build_finances(core, NULL, .fin_org("A"), years = 2020L)
  expect_equal(out$`Total Revenues`, 100)
})

test_that("build_finances emits the contract schema", {
  core <- .fin_core_row("A", 2020)
  out <- build_finances(core, NULL, .fin_org("A"), years = 2020L)
  expect_equal(colnames(out),
               c("Organization Type", "Subsector", "Size",
                 "Census Region", "Census State", "Census County", "County FIPS",
                 "Metro/Micro Area", "CBSA Code", "Year",
                 "Total Revenues", "Total Expenses",
                 "Total Assets", "Total Benefits"))
  expect_type(out$Year, "integer")
  expect_type(out$`Total Revenues`, "double")
  expect_type(out$`Total Benefits`, "double")
})
