.write_daf_fixture <- function(rows) {
  tmp <- tempfile(fileext = ".csv")
  utils::write.csv(rows, tmp, row.names = FALSE, na = "")
  tmp
}

test_that("read_daf_orgs sums DAF + OTH parallel columns", {
  fx <- .write_daf_fixture(data.frame(
    EIN2 = c("A", "B"),
    TAX_YEAR = c(2022, 2022),
    SD_01_TOT_NUM_EOY_DAF        = c(5, NA),
    SD_01_TOT_NUM_EOY_OTH        = c(2, 3),
    SD_01_AGGREGATE_CONTR_DAF    = c(100, 50),
    SD_01_AGGREGATE_CONTR_OTH    = c(50,  NA),
    SD_01_AGGREGATE_GRANT_DAF    = c(NA, NA),
    SD_01_AGGREGATE_GRANT_OTH    = c(NA, NA),
    SD_01_AGGREGATE_VALUE_EOY_DAF = c(1000, 2000),
    SD_01_AGGREGATE_VALUE_EOY_OTH = c(0,    500)
  ))
  out <- read_daf_orgs(fx, tax_year = 2022)
  expect_equal(out$num_dafs,      c(7, 3))
  expect_equal(out$contributions, c(150, 50))
  expect_true(all(is.na(out$grants)))            # both components NA → NA
  expect_equal(out$value,         c(1000, 2500))
})

test_that("read_daf_orgs filters to the requested tax_year", {
  fx <- .write_daf_fixture(data.frame(
    EIN2 = c("A", "B"),
    TAX_YEAR = c(2022, 2021),
    SD_01_TOT_NUM_EOY_DAF = c(1, 1),
    SD_01_TOT_NUM_EOY_OTH = c(0, 0),
    SD_01_AGGREGATE_CONTR_DAF = c(NA, NA), SD_01_AGGREGATE_CONTR_OTH = c(NA, NA),
    SD_01_AGGREGATE_GRANT_DAF = c(NA, NA), SD_01_AGGREGATE_GRANT_OTH = c(NA, NA),
    SD_01_AGGREGATE_VALUE_EOY_DAF = c(NA, NA), SD_01_AGGREGATE_VALUE_EOY_OTH = c(NA, NA)
  ))
  out <- read_daf_orgs(fx, tax_year = 2022)
  expect_equal(nrow(out), 1L)
  expect_equal(out$ein, nccsdata::nccs_normalize_ein("A"))
})

test_that("daf_paths returns one row per orgs year with absolute URLs", {
  cfg <- list(inputs = list(daf = list(
    orgs = list(`2022` = "u1", `2023` = "u2")
  )))
  out <- daf_paths(cfg)
  expect_equal(names(out), c("tax_year", "orgs_url"))
  expect_equal(out$tax_year, c(2022L, 2023L))
  expect_equal(out$orgs_url, c("u1", "u2"))
})
