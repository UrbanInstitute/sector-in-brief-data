CANON <- c("ein", "tax_year", "source_form",
           "total_revenue", "total_expenses", "total_assets",
           "total_contributions", "total_benefits")

.write_pq <- function(df) {
  p <- tempfile(fileext = ".parquet")
  arrow::write_parquet(df, p)
  p
}

# --- Modern: 990combined base + 990 full file with Pt IX -------------------

test_that("read_core_990_modern returns canonical schema with Pt IX joined", {
  combined <- data.frame(
    ein = c("10-0000001", "20-0000002", "30-0000003"),
    tax_year = c(2020L, 2020L, 2020L),
    total_revenue       = c(1000, 2000, 3000),
    total_expenses      = c(900, 1900, 2900),
    total_assets_eoy    = c(5000, 6000, 7000),
    total_contributions = c(500, 600, 700)
  )
  full <- data.frame(
    ein = c("10-0000001", "20-0000002"),  # 990 filers only — 30 is 990EZ
    tax_year = c(2020L, 2020L),
    compensation_current_officers     = c(100, 200),
    compensation_disqualified_persons = c(10, 20),
    other_salaries_wages              = c(300, 400),
    pension_plan_contributions        = c(50, 60),
    other_employee_benefits           = c(40, 50)
  )
  out <- read_core_990_modern(.write_pq(combined), .write_pq(full))
  expect_equal(colnames(out), CANON)
  expect_true(all(out$source_form == "990combined"))
  benefits <- stats::setNames(out$total_benefits, out$ein)
  expect_equal(benefits[["10-0000001"]], 500)   # 100+10+300+50+40
  expect_equal(benefits[["20-0000002"]], 730)   # 200+20+400+60+50
  expect_true(is.na(benefits[["30-0000003"]]))  # 990EZ filer — no Pt IX
})

test_that("read_core_990_modern preserves NA when all Pt IX components NA", {
  combined <- data.frame(
    ein = "10-0000001", tax_year = 2020L,
    total_revenue = 1000, total_expenses = 900,
    total_assets_eoy = 5000, total_contributions = 500
  )
  full <- data.frame(
    ein = "10-0000001", tax_year = 2020L,
    compensation_current_officers     = NA_real_,
    compensation_disqualified_persons = NA_real_,
    other_salaries_wages              = NA_real_,
    pension_plan_contributions        = NA_real_,
    other_employee_benefits           = NA_real_
  )
  out <- read_core_990_modern(.write_pq(combined), .write_pq(full))
  expect_true(is.na(out$total_benefits))
})

test_that("read_core_990_modern degrades gracefully when full_path is missing", {
  combined <- data.frame(
    ein = "10-0000001", tax_year = 2020L,
    total_revenue = 1000, total_expenses = 900,
    total_assets_eoy = 5000, total_contributions = 500
  )
  out <- read_core_990_modern(.write_pq(combined), full_path = NULL)
  expect_equal(out$total_revenue, 1000)
  expect_true(is.na(out$total_benefits))
})

# --- Legacy: 990combined with Pt IX 5+7 inline -----------------------------

test_that("read_core_990_legacy computes partial 2-line proxy Total Benefits", {
  df <- data.frame(
    ein = c("10-0000001", "20-0000002", "30-0000003"),
    tax_year = c(1995L, 1995L, 1995L),
    total_revenue = c(100, 200, 300),
    total_expenses = c(90, 190, 290),
    total_assets_eoy = c(500, 600, 700),
    total_contributions = c(50, 60, 70),
    compensation_current_officers = c(10, 20, NA_real_),
    other_salaries_wages          = c(30, NA_real_, NA_real_)
  )
  out <- read_core_990_legacy(.write_pq(df))
  expect_equal(colnames(out), CANON)
  expect_true(all(out$source_form == "990combined_legacy"))
  benefits <- stats::setNames(out$total_benefits, out$ein)
  expect_equal(benefits[["10-0000001"]], 40)   # 10 + 30
  expect_equal(benefits[["20-0000002"]], 20)   # 20 + NA → 20 (one component present)
  expect_true(is.na(benefits[["30-0000003"]])) # both NA → NA
})

test_that("read_core_990_legacy handles missing benefit columns gracefully", {
  df <- data.frame(
    ein = "10-0000001", tax_year = 1989L,
    total_revenue = 100, total_expenses = 90,
    total_assets_eoy = 500, total_contributions = 50
  )
  out <- read_core_990_legacy(.write_pq(df))
  expect_true(is.na(out$total_benefits))
  expect_equal(out$total_revenue, 100)
})

# --- PF --------------------------------------------------------------------

test_that("read_core_990pf returns canonical schema", {
  df <- data.frame(
    ein = "10-0000001", tax_year = 2023L,
    total_revenue_col_a  = 1000, total_expenses_col_a = 900,
    total_assets_eoy = 5000, contributions_received = 500
  )
  out <- read_core_990pf(.write_pq(df))
  expect_equal(colnames(out), CANON)
  expect_true(all(out$source_form == "990pf"))
  expect_true(all(is.na(out$total_benefits)))
})

test_that("read_core_990pf_raw preserves PF-specific columns", {
  df <- data.frame(
    ein = "10-0000001", tax_year = 2023L,
    total_revenue_col_a  = 1000, total_expenses_col_a = 900,
    total_assets_eoy = 5000,
    contributions_received = 500, contributions_paid = 250
  )
  out <- read_core_990pf_raw(.write_pq(df))
  expect_true(all(c("contributions_paid", "contributions_received") %in% colnames(out)))
  expect_equal(out$contributions_paid, 250)
})

# --- Path builders ---------------------------------------------------------

test_that("core_990_paths dispatches by era", {
  cfg <- list(inputs = list(
    core_legacy = "s3://b/legacy/",
    core_modern = "s3://b/modern/"
  ))
  out <- core_990_paths(cfg, c(2011, 2012))
  expect_equal(out$era, c("legacy", "modern"))
  expect_equal(out$combined_uri[1], "s3://b/legacy/2011/990combined/core_2011_990combined.parquet")
  expect_equal(out$combined_uri[2], "s3://b/modern/2012/990combined/core_2012_990combined.parquet")
  expect_true(is.na(out$full_uri[1]))   # no separate /990/ in legacy era
  expect_equal(out$full_uri[2], "s3://b/modern/2012/990/core_2012_990.parquet")
})

test_that("core_pf_paths builds processed_merged URIs", {
  cfg <- list(inputs = list(core_pf = "s3://b/pm/"))
  out <- core_pf_paths(cfg, c(2020, 2023))
  expect_equal(unname(out),
               c("s3://b/pm/2020/990pf/core_2020_990pf.parquet",
                 "s3://b/pm/2023/990pf/core_2023_990pf.parquet"))
  expect_equal(names(out), c("2020", "2023"))
})

test_that("read_core_990_year dispatches to legacy vs modern by year", {
  legacy_df <- data.frame(
    ein = "10-0000001", tax_year = 2010L,
    total_revenue = 100, total_expenses = 90,
    total_assets_eoy = 500, total_contributions = 50,
    compensation_current_officers = 10, other_salaries_wages = 30
  )
  modern_df <- data.frame(
    ein = "10-0000001", tax_year = 2020L,
    total_revenue = 1000, total_expenses = 900,
    total_assets_eoy = 5000, total_contributions = 500
  )
  out_l <- read_core_990_year(2010, .write_pq(legacy_df))
  out_m <- read_core_990_year(2020, .write_pq(modern_df), full_local = NULL)
  expect_equal(out_l$source_form, "990combined_legacy")
  expect_equal(out_m$source_form, "990combined")
  expect_equal(out_l$total_benefits, 40)
  expect_true(is.na(out_m$total_benefits))
})
