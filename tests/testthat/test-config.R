test_that("read_config parses the repo config.yml", {
  cfg <- read_config(testthat::test_path("..", "..", "config.yml"))
  expect_type(cfg, "list")
  expect_match(cfg$vintage, "^\\d{4}\\.\\d{2}$")
  expect_match(cfg$inputs$bmf, "^s3://")
  expect_equal(cfg$output$bucket, "nccsdata")
  expect_equal(cfg$output$prefix, "sector-in-brief")
  expect_equal(cfg$aws$profile, "thiya")
})

test_that("vintage_prefix builds the canonical S3 URI", {
  cfg <- list(
    vintage = "2026.05",
    output = list(bucket = "nccsdata", prefix = "sector-in-brief",
                  sandbox_prefix = "sector-in-brief-sandbox")
  )
  expect_equal(vintage_prefix(cfg),
               "s3://nccsdata/sector-in-brief/v2026.05")
  expect_equal(vintage_prefix(cfg, sandbox = TRUE),
               "s3://nccsdata/sector-in-brief-sandbox/v2026.05")
})
