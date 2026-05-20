.ng_bmf <- function(rows) {
  tibble::tibble(
    ein = sprintf("%02d-%07d", seq_len(rows), seq_len(rows)),
    `Census State` = NA_character_,
    `Census County` = NA_character_,
    `Metro/Micro Area` = NA_character_,
    `Census Region` = NA_character_
  )
}

test_that("build_nested_geographies emits distinct geo tuples", {
  bmf <- .ng_bmf(4)
  bmf$`Census State`     <- c("NY", "NY", "NY", "CA")
  bmf$`Census County`    <- c("Kings", "Kings", "Queens", "Los Angeles")
  bmf$`Metro/Micro Area` <- c("New York, NY", "New York, NY", "New York, NY", "Los Angeles, CA")
  bmf$`Census Region`    <- c("Northeast", "Northeast", "Northeast", "West")
  out <- build_nested_geographies(bmf)
  expect_equal(nrow(out), 3L)
  expect_setequal(out$`Census County`, c("Kings", "Queens", "Los Angeles"))
})

test_that("build_nested_geographies drops all-NA rows but keeps partial-NA", {
  bmf <- .ng_bmf(3)
  bmf$`Census State`     <- c("NY", NA, "TX")
  bmf$`Census County`    <- c("Kings", NA, NA)
  bmf$`Metro/Micro Area` <- c(NA, NA, "Houston, TX")
  bmf$`Census Region`    <- c("Northeast", NA, "South")
  out <- build_nested_geographies(bmf)
  expect_equal(nrow(out), 2L)
  expect_true(any(is.na(out$`Metro/Micro Area`)))    # rural county kept
  expect_false(any(out$`Census State` %in% NA))      # the all-NA row dropped
})

test_that("build_nested_geographies produces the contract column names", {
  bmf <- .ng_bmf(1)
  bmf$`Census State` <- "NY"
  bmf$`Census County` <- "Kings"
  bmf$`Metro/Micro Area` <- "New York, NY"
  bmf$`Census Region` <- "Northeast"
  out <- build_nested_geographies(bmf)
  expect_equal(colnames(out),
               c("Census State", "Census County",
                 "Metro/Micro Area", "Census Region"))
})
