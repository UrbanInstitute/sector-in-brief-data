test_that("year_row_counts produces named integer list", {
  df <- tibble::tibble(Year = c(2020L, 2020L, 2021L, 2022L, 2022L, 2022L))
  out <- year_row_counts(df)
  expect_equal(out$`2020`, 2L)
  expect_equal(out$`2021`, 1L)
  expect_equal(out$`2022`, 3L)
})

test_that("build_manifest captures sha256, row counts, and year counts", {
  tmp <- tempfile()
  dir.create(tmp)
  df <- tibble::tibble(Year = c(2020L, 2020L, 2021L), x = 1:3)
  pq <- file.path(tmp, "panel.parquet")
  arrow::write_parquet(df, pq)

  m <- build_manifest("2026.05",
                      outputs = list(`panel.parquet` = list(path = pq, df = df)),
                      inputs = list(),
                      aws_profile = NULL)
  expect_equal(m$vintage, "2026.05")
  expect_match(m$files$`panel.parquet`$sha256, "^[0-9a-f]{64}$")
  expect_equal(m$files$`panel.parquet`$row_count, 3L)
  expect_equal(m$files$`panel.parquet`$year_counts$`2020`, 2L)
})

test_that("write_manifest produces parseable JSON next to the outputs", {
  tmp <- tempfile()
  dir.create(tmp)
  m <- list(vintage = "2026.05", files = list(), inputs = list())
  out <- write_manifest(m, tmp)
  expect_true(file.exists(out))
  parsed <- jsonlite::read_json(out)
  expect_equal(parsed$vintage, "2026.05")
})
