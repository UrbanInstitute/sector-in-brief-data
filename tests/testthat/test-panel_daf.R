.daf_org <- function(eins = c("A", "B")) {
  tibble::tibble(
    ein = eins,
    org_year_first = 2020L,
    org_year_last  = 2024L,
    `Organization Type` = "501(c)(3) Public Charities",
    Subsector = "PHIL",
    Size = 4L,
    `Census Region` = "Northeast",
    `Census State`  = "NY",
    `Census County` = "Cook County",
    `Metro/Micro Area` = NA_character_
  )
}

.daf_row <- function(ein, tax_year, num = 1, contr = 100, grants = 50,
                     value = 1000) {
  tibble::tibble(
    ein = ein, tax_year = as.integer(tax_year),
    num_dafs = num, contributions = contr, grants = grants, value = value
  )
}

test_that("build_daf aggregates the four dollar/count metrics", {
  daf <- dplyr::bind_rows(
    .daf_row("A", 2022, num = 2, contr = 100, grants = 50, value = 1000),
    .daf_row("B", 2022, num = 3, contr = 200, grants = 75, value = 4000)
  )
  out <- build_daf(daf, .daf_org(), years = 2022L)
  expect_equal(nrow(out), 1L)
  expect_equal(out$`Number of Nonprofits`, 2L)
  expect_equal(out$`Number of DAFs`,       5)
  expect_equal(out$`Total Contributions`,  300)
  expect_equal(out$`Total Grants`,         125)
  expect_equal(out$`Total Value`,          5000)
})

test_that("build_daf emits cells with zero DAF activity (Has DAF=0, NA dollars)", {
  # Two BMF-active orgs in 2022, only A files a DAF. Cell shows both orgs but
  # Has DAF = 1.
  daf <- .daf_row("A", 2022, num = 2, contr = 100, grants = 50, value = 1000)
  out <- build_daf(daf, .daf_org(c("A","B")), years = 2022L)
  expect_equal(out$`Number of Nonprofits`, 2L)  # both BMF-active
  expect_equal(out$`Has DAF`,              1L)  # only A files DAF
  # Now a year with no DAF filings — cell should still appear (BMF orgs active)
  out_2023 <- build_daf(daf, .daf_org(c("A","B")), years = 2023L)
  expect_equal(nrow(out_2023), 1L)
  expect_equal(out_2023$`Has DAF`, 0L)
  expect_true(is.na(out_2023$`Number of DAFs`))
  expect_true(is.na(out_2023$`Total Contributions`))
})

test_that("build_daf counts orgs in a cell with num_dafs > 0 for Has DAF", {
  daf <- dplyr::bind_rows(
    .daf_row("A", 2022, num = 2),       # has DAF
    .daf_row("B", 2022, num = 0),       # filed but no DAFs
    .daf_row("C", 2022, num = NA_real_) # NA → not "Has DAF"
  )
  out <- build_daf(daf, .daf_org(c("A","B","C")), years = 2022L)
  expect_equal(out$`Has DAF`, 1L)
  expect_equal(out$`Number of Nonprofits`, 3L)
})

test_that("build_daf groups by Year", {
  daf <- dplyr::bind_rows(
    .daf_row("A", 2022, contr = 100),
    .daf_row("A", 2023, contr = 200)
  )
  out <- build_daf(daf, .daf_org("A"), years = c(2022L, 2023L))
  by_year <- stats::setNames(out$`Total Contributions`, out$Year)
  expect_equal(by_year[["2022"]], 100)
  expect_equal(by_year[["2023"]], 200)
})

test_that("build_daf inner-joins DAF on EIN (orphan DAF rows are dropped)", {
  daf <- dplyr::bind_rows(
    .daf_row("A", 2022, contr = 100),
    .daf_row("ORPHAN", 2022, contr = 9999)
  )
  out <- build_daf(daf, .daf_org("A"), years = 2022L)
  expect_equal(out$`Total Contributions`, 100)
})

test_that("build_daf preserves NA for an all-NA metric column", {
  daf <- dplyr::bind_rows(
    .daf_row("A", 2022, contr = NA_real_),
    .daf_row("B", 2022, contr = NA_real_)
  )
  out <- build_daf(daf, .daf_org(), years = 2022L)
  expect_true(is.na(out$`Total Contributions`))
})

test_that("build_daf emits the contract schema", {
  daf <- .daf_row("A", 2022)
  out <- build_daf(daf, .daf_org("A"), years = 2022L)
  expect_equal(colnames(out),
               c("Organization Type", "Subsector", "Size",
                 "Census Region", "Census State", "Census County",
                 "Metro/Micro Area", "Year",
                 "Number of Nonprofits",
                 "Number of DAFs", "Total Contributions",
                 "Total Grants", "Total Value", "Has DAF"))
  expect_type(out$Year, "integer")
  expect_type(out$`Has DAF`, "integer")
  expect_type(out$`Total Value`, "double")
})
