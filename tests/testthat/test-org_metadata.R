test_that("build_org_metadata attaches Size from most recent CORE expense", {
  bmf <- tibble::tibble(
    ein = c("12-3456789", "98-7654321", "00-0000001"),
    `Census State` = c("NY", "CA", "TX"),
    `Census County` = NA_character_, `Metro/Micro Area` = NA_character_,
    `Census Region` = c("Northeast", "West", "South"),
    Subsector = NA_character_, `Organization Type` = NA_character_,
    nteev2 = NA_character_, subsection_code = NA_character_,
    foundation_code = NA_character_, asset_amount = NA_real_,
    org_year_first = c(2000L, 1995L, 2020L),
    org_year_last  = c(2024L, 2024L, 2024L)
  )
  core <- tibble::tibble(
    ein = c("12-3456789", "12-3456789", "98-7654321"),
    tax_year = c(2018L, 2022L, 2020L),
    source_form = "990combined",
    total_revenue = NA_real_, total_expenses = c(50000, 7500000, NA_real_),
    total_assets = NA_real_, total_contributions = NA_real_,
    total_benefits = NA_real_
  )

  out <- build_org_metadata(bmf, core_990 = core)
  expect_equal(out$Size[out$ein == "12-3456789"], 5L)   # most recent: 7.5M
  expect_equal(out$Size[out$ein == "98-7654321"], 0L)   # only non-NA was filtered out
  expect_equal(out$Size[out$ein == "00-0000001"], 0L)   # no CORE row at all
})

test_that("build_org_metadata returns Size=0 for everyone when CORE is empty", {
  bmf <- tibble::tibble(
    ein = c("12-3456789", "98-7654321"),
    `Census State` = NA_character_, `Census County` = NA_character_,
    `Metro/Micro Area` = NA_character_, `Census Region` = NA_character_,
    Subsector = NA_character_, `Organization Type` = NA_character_,
    nteev2 = NA_character_, subsection_code = NA_character_,
    foundation_code = NA_character_, asset_amount = NA_real_,
    org_year_first = 2000L, org_year_last = 2024L
  )
  out <- build_org_metadata(bmf)
  expect_true(all(out$Size == 0L))
})

test_that("build_org_metadata picks the latest year across 990 + 990PF", {
  bmf <- tibble::tibble(
    ein = "12-3456789",
    `Census State` = NA_character_, `Census County` = NA_character_,
    `Metro/Micro Area` = NA_character_, `Census Region` = NA_character_,
    Subsector = NA_character_, `Organization Type` = NA_character_,
    nteev2 = NA_character_, subsection_code = NA_character_,
    foundation_code = NA_character_, asset_amount = NA_real_,
    org_year_first = 2000L, org_year_last = 2024L
  )
  c990 <- tibble::tibble(ein = "12-3456789", tax_year = 2018L,
                         source_form = "990combined", total_revenue = NA_real_,
                         total_expenses = 50000, total_assets = NA_real_,
                         total_contributions = NA_real_, total_benefits = NA_real_)
  cpf  <- tibble::tibble(ein = "12-3456789", tax_year = 2023L,
                         source_form = "990pf",       total_revenue = NA_real_,
                         total_expenses = 12000000, total_assets = NA_real_,
                         total_contributions = NA_real_, total_benefits = NA_real_)
  out <- build_org_metadata(bmf, core_990 = c990, core_990pf = cpf)
  expect_equal(out$Size, 6L)   # PF row in 2023 wins over 990 row in 2018
})
