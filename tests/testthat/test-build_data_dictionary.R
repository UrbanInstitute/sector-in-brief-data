.dd_dim_cols <- list(
  `Organization Type` = "501(c)(3) Public Charities",
  Subsector = "ART",
  Size = 1L,
  `Census Region` = "Northeast",
  `Census State` = "NY",
  `Census County` = "Kings",
  `Metro/Micro Area` = NA_character_
)

.dd_make_panel <- function(extra_cols) {
  do.call(tibble::tibble, c(.dd_dim_cols, extra_cols))
}

test_that("build_data_dictionary covers every column in every panel", {
  panels <- list(
    `number_nonprofits.parquet` = .dd_make_panel(list(Year = 2020L,
                                                      `Number of Nonprofits` = 100L)),
    `finances.parquet` = .dd_make_panel(list(Year = 2020L,
                                             `Total Revenues` = 1000,
                                             `Total Expenses` = 900,
                                             `Total Assets` = 5000,
                                             `Total Benefits` = 200)),
    `pf_grants.parquet` = .dd_make_panel(list(Year = 2020L,
                                              `Total Contributions` = 500)),
    `daf.parquet` = .dd_make_panel(list(Year = 2020L,
                                        `Number of Nonprofits` = 1L,
                                        `Number of DAFs` = 1,
                                        `Total Contributions` = 100,
                                        `Total Grants` = 50,
                                        `Total Value` = 1000,
                                        `Has DAF` = 1L)),
    `nested_geographies.csv` = tibble::tibble(
      `Census State` = "NY", `Census County` = "Kings",
      `Metro/Micro Area` = "New York, NY", `Census Region` = "Northeast")
  )
  dd <- build_data_dictionary(panels)
  expect_equal(colnames(dd),
               c("file", "column", "datatype",
                 "description", "form_source",
                 "coverage", "coverage_notes"))
  expect_setequal(unique(dd$file), names(panels))
  # Total Benefits limitation should surface in coverage_notes
  tb_notes <- dd$coverage_notes[dd$file == "finances.parquet" &
                                dd$column == "Total Benefits"]
  expect_match(tb_notes, "partial 2-line proxy")
})

test_that("build_data_dictionary fails when a panel column is undocumented", {
  panels <- list(
    `finances.parquet` = .dd_make_panel(list(Year = 2020L,
                                             `Total Revenues` = 1000,
                                             `Total Expenses` = 900,
                                             `Total Assets` = 5000,
                                             `Total Benefits` = 200,
                                             `Mystery Column` = 99))
  )
  expect_error(build_data_dictionary(panels),
               "missing from data_dictionary_curation",
               fixed = FALSE)
})

test_that("build_data_dictionary computes per-file year coverage from data", {
  panels <- list(
    `finances.parquet` = .dd_make_panel(list(Year = c(2010L, 2020L, 2024L),
                                             `Total Revenues` = c(1, 2, 3),
                                             `Total Expenses` = c(1, 2, 3),
                                             `Total Assets` = c(1, 2, 3),
                                             `Total Benefits` = c(1, 2, 3)))[
      rep(1, 3), ],
    `nested_geographies.csv` = tibble::tibble(
      `Census State` = "NY", `Census County` = "Kings",
      `Metro/Micro Area` = "New York, NY", `Census Region` = "Northeast")
  )
  # Need to actually vary Year — rebuild
  fin <- tibble::tibble(
    `Organization Type` = "501(c)(3) Public Charities", Subsector = "ART",
    Size = 1L, `Census Region` = "Northeast", `Census State` = "NY",
    `Census County` = "Kings", `Metro/Micro Area` = NA_character_,
    Year = c(2010L, 2020L, 2024L),
    `Total Revenues` = c(1,2,3), `Total Expenses` = c(1,2,3),
    `Total Assets` = c(1,2,3), `Total Benefits` = c(1,2,3)
  )
  panels$finances.parquet <- fin
  dd <- build_data_dictionary(panels)
  fin_cov <- unique(dd$coverage[dd$file == "finances.parquet"])
  ng_cov  <- unique(dd$coverage[dd$file == "nested_geographies.csv"])
  expect_equal(fin_cov, "2010-2024")
  expect_equal(ng_cov, "static")
})
