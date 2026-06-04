.ng_bmf <- function(rows) {
  tibble::tibble(
    ein = sprintf("%02d-%07d", seq_len(rows), seq_len(rows)),
    `Census State` = NA_character_,
    `Census County` = NA_character_,
    `County FIPS` = NA_character_,
    `Metro/Micro Area` = NA_character_,
    `CBSA Code` = NA_character_,
    `Census Region` = NA_character_
  )
}

test_that("build_nested_geographies emits distinct geo tuples with codes", {
  bmf <- .ng_bmf(4)
  bmf$`Census State`     <- c("NY", "NY", "NY", "CA")
  bmf$`Census County`    <- c("Kings County", "Kings County", "Queens County", "Los Angeles County")
  bmf$`County FIPS`      <- c("36047", "36047", "36081", "06037")
  bmf$`Metro/Micro Area` <- c("New York, NY", "New York, NY", "New York, NY", "Los Angeles, CA")
  bmf$`CBSA Code`        <- c("35620", "35620", "35620", "31080")
  bmf$`Census Region`    <- c("Northeast", "Northeast", "Northeast", "West")
  out <- build_nested_geographies(bmf)
  expect_equal(nrow(out), 3L)
  expect_setequal(out$`Census County`,
                  c("Kings County", "Queens County", "Los Angeles County"))
  expect_setequal(out$`County FIPS`, c("36047", "36081", "06037"))
})

test_that("build_nested_geographies drops unassigned (NA-county) rows, keeps rural", {
  bmf <- .ng_bmf(3)
  bmf$`Census State`     <- c("NY", NA, "TX")
  bmf$`Census County`    <- c("Kings County", NA, "Loving County")  # TX = rural
  bmf$`County FIPS`      <- c("36047", NA, "48301")
  bmf$`Metro/Micro Area` <- c("New York, NY", NA, NA)               # rural: NA CBSA
  bmf$`CBSA Code`        <- c("35620", NA, NA)
  bmf$`Census Region`    <- c("Northeast", NA, "South")
  out <- build_nested_geographies(bmf)
  expect_equal(nrow(out), 2L)                       # the NA-county row dropped
  expect_false(any(is.na(out$`Census County`)))     # no unassigned rows
  expect_true(any(is.na(out$`Metro/Micro Area`)))   # rural county kept
})

test_that("build_nested_geographies produces the contract column names", {
  bmf <- .ng_bmf(1)
  bmf$`Census State`     <- "NY"
  bmf$`Census County`    <- "Kings County"
  bmf$`County FIPS`      <- "36047"
  bmf$`Metro/Micro Area` <- "New York, NY"
  bmf$`CBSA Code`        <- "35620"
  bmf$`Census Region`    <- "Northeast"
  out <- build_nested_geographies(bmf)
  expect_equal(colnames(out),
               c("Census State", "Census County", "County FIPS",
                 "Metro/Micro Area", "CBSA Code", "Census Region"))
})
