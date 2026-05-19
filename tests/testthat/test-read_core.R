fx_2023 <- testthat::test_path("..", "..", "inst", "fixtures",
                               "core_990combined_2023_sample.parquet")
fx_1995 <- testthat::test_path("..", "..", "inst", "fixtures",
                               "core_990combined_1995_sample.parquet")
fx_pf   <- testthat::test_path("..", "..", "inst", "fixtures",
                               "core_990pf_2023_sample.parquet")

CANON <- c("ein", "tax_year", "source_form",
           "total_revenue", "total_expenses", "total_assets",
           "total_contributions", "total_benefits")

test_that("read_core_990combined returns the canonical schema", {
  skip_if_not(file.exists(fx_2023))
  out <- read_core_990combined(fx_2023)
  expect_equal(colnames(out), CANON)
  expect_true(all(out$source_form == "990combined"))
})

test_that("read_core_990combined normalizes ein to XX-XXXXXXX", {
  skip_if_not(file.exists(fx_2023))
  out <- read_core_990combined(fx_2023)
  good <- out$ein[!is.na(out$ein)]
  expect_true(all(grepl("^[0-9]{2}-[0-9]{7}$", good)))
})

test_that("read_core_990combined fills missing total_functional_expenses with NA (2023)", {
  # 2023 processed_merged 990combined currently lacks total_functional_expenses.
  # Once the upstream patch lands this assertion will start passing values; the
  # second assertion below will then need flipping. Leave as a tripwire.
  skip_if_not(file.exists(fx_2023))
  out <- read_core_990combined(fx_2023)
  expect_true(all(is.na(out$total_expenses)),
              info = "If this fails, upstream processed_merged has added total_functional_expenses for 2023 — update the test and remove the .fill_missing tripwire.")
})

test_that("read_core_990combined emits NA total_benefits when post-2008 components missing", {
  # Current 990combined has none of the 5 Pt IX components; every row should
  # see NA total_benefits because lines 6/8/9 are absent. Tripwire #2.
  skip_if_not(file.exists(fx_2023))
  out <- read_core_990combined(fx_2023)
  expect_true(all(is.na(out$total_benefits)),
              info = "If this fails, upstream processed_merged has added Pt IX-6/8/9 — confirm 2012+ rows now have real values and pre-2012 rows still NA.")
})

test_that("read_core_990combined emits NA total_benefits for 1995 (pre-redesign era)", {
  # 1995 990combined carries 2 of 5 components (lines 5 and 7). Lines 6/8/9
  # never existed pre-2008. Therefore total_benefits must be NA for every row,
  # NOT a 2-line proxy. This is the visible-discontinuity guarantee.
  skip_if_not(file.exists(fx_1995))
  out <- read_core_990combined(fx_1995)
  expect_true(all(is.na(out$total_benefits)))
})

test_that("read_core_990combined populates total_expenses for 1995 (pre-merge era)", {
  skip_if_not(file.exists(fx_1995))
  out <- read_core_990combined(fx_1995)
  expect_true(any(!is.na(out$total_expenses)))
  expect_true(any(out$total_expenses > 0, na.rm = TRUE))
})

test_that("read_core_990pf returns canonical schema with source_form='990pf'", {
  skip_if_not(file.exists(fx_pf))
  out <- read_core_990pf(fx_pf)
  expect_equal(colnames(out), CANON)
  expect_true(all(out$source_form == "990pf"))
  expect_true(all(is.na(out$total_benefits)))  # PFs don't report benefits
})

test_that("read_core_990pf_raw keeps PF grants-paid and contributions-received", {
  skip_if_not(file.exists(fx_pf))
  out <- read_core_990pf_raw(fx_pf)
  expect_true(all(c("contributions_paid", "contributions_received") %in% colnames(out)))
  expect_true(any(!is.na(out$contributions_paid)))
})

test_that("core_paths builds correctly from config", {
  cfg <- list(inputs = list(core_harmonized = "s3://nccsdata/processed_merged/core/"))
  paths <- core_paths(cfg, "990combined", c(2020, 2023))
  expect_equal(
    unname(paths),
    c("s3://nccsdata/processed_merged/core/2020/990combined/core_2020_990combined.parquet",
      "s3://nccsdata/processed_merged/core/2023/990combined/core_2023_990combined.parquet")
  )
  expect_equal(names(paths), c("2020", "2023"))
})

test_that("read_core stacks multiple years", {
  skip_if_not(file.exists(fx_2023) && file.exists(fx_1995))
  out <- read_core(c(fx_1995, fx_2023))
  expect_setequal(unique(out$tax_year), c(1995L, 2023L))
  expect_equal(colnames(out), CANON)
})
