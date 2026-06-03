test_that("read_government_grants_raw normalizes EIN and types", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(
      filing_receipt_id = c("r1", "r2"),
      ein               = c("123456789", "98-7654321"),
      tax_year          = c(2021, 2022),
      form_type         = c("990", "990"),
      government_grants = c(1000, NA)
    ), tmp)

  out <- read_government_grants_raw(tmp)
  expect_equal(names(out), c("ein", "tax_year", "government_grants"))
  expect_equal(out$ein, c("12-3456789", "98-7654321"))  # canonical XX-XXXXXXX
  expect_type(out$tax_year, "integer")
  expect_type(out$government_grants, "double")
  expect_true(is.na(out$government_grants[2]))
})

test_that("read_program_related_investments_raw normalizes EIN and types", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(
      filing_receipt_id = "r1",
      ein               = "123456789",
      tax_year          = 2021,
      form_type         = "990PF",
      program_related_investments_total = 5000
    ), tmp)

  out <- read_program_related_investments_raw(tmp)
  expect_equal(names(out),
               c("ein", "tax_year", "program_related_investments_total"))
  expect_equal(out$ein, "12-3456789")
  expect_equal(out$program_related_investments_total, 5000)
})

test_that("read_government_grants_raw errors on a missing expected column", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(tibble::tibble(ein = "123456789", tax_year = 2021), tmp)
  expect_error(read_government_grants_raw(tmp), "government_grants")
})
