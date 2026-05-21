.publish_cfg <- function(also_latest, tmp) {
  list(
    vintage = "2099.01",
    output  = list(bucket = "test-bucket",
                   prefix = "sector-in-brief",
                   sandbox_prefix = "sector-in-brief-sandbox",
                   also_publish_latest = also_latest),
    aws     = list(profile = "test"),
    inputs  = list(bmf = "s3://x/y", core_legacy = "", core_modern = "",
                   core_pf = ""),
    local   = list(cache_dir = tmp)
  )
}

test_that("publish_vintage (prod, also_publish_latest=TRUE) plans a latest/ mirror", {
  tmp <- tempfile(); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  out <- publish_vintage(
    list(panel_x = tibble::tibble(Year = 2020L, x = 1)),
    config = .publish_cfg(TRUE, tmp), sandbox = FALSE, dry_run = TRUE
  )
  expect_equal(out$s3_prefix,
               "s3://test-bucket/sector-in-brief/v2099.01")
  expect_equal(out$latest_prefix,
               "s3://test-bucket/sector-in-brief/latest/")
})

test_that("publish_vintage (sandbox) never mirrors to latest/", {
  tmp <- tempfile(); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  out <- publish_vintage(
    list(panel_x = tibble::tibble(Year = 2020L, x = 1)),
    config = .publish_cfg(TRUE, tmp), sandbox = TRUE, dry_run = TRUE
  )
  expect_null(out$latest_prefix)
})

test_that("publish_vintage (prod, also_publish_latest=FALSE) skips mirror", {
  tmp <- tempfile(); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  out <- publish_vintage(
    list(panel_x = tibble::tibble(Year = 2020L, x = 1)),
    config = .publish_cfg(FALSE, tmp), sandbox = FALSE, dry_run = TRUE
  )
  expect_null(out$latest_prefix)
})
