# Connecticut planning-region crosswalk: reader, coordinate lookup, and the
# read_bmf integration that moves CT from "unassigned county" to a resolved
# planning region + Metro/Micro Area (handoff from nccs-data-bmf, ADR 0023).

ct_fix <- testthat::test_path("..", "..", "inst", "fixtures",
                              "ct_planning_region_crosswalk_sample.parquet")

# --- read_ct_planning_region_crosswalk ----------------------------------------

test_that("read_ct_planning_region_crosswalk validates schema, keeps GEOID chr", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(
      geo_state_abbr = "CT", lat2 = 41.12, lon2 = -73.28,
      geo_county_fips = "09120",         # string GEOID (leading zero significant)
      state_fips = "09",
      geo_county_canonical = "Greater Bridgeport Planning Region",
      area_share = 1, straddle = FALSE, tiger_year = 2023L
    ), tmp)
  out <- read_ct_planning_region_crosswalk(tmp)
  expect_equal(names(out), c("geo_state_abbr", "lat2", "lon2", "geo_county_fips",
                             "state_fips", "geo_county_canonical", "area_share",
                             "straddle", "tiger_year"))
  expect_type(out$geo_county_fips, "character")
  expect_equal(out$geo_county_fips, "09120")   # leading zero preserved
  expect_type(out$straddle, "logical")
  expect_type(out$tiger_year, "integer")
})

test_that("read_ct_planning_region_crosswalk errors on a missing expected column", {
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(
    tibble::tibble(geo_state_abbr = "CT", lat2 = 41.12, lon2 = -73.28,
                   geo_county_fips = "09120", state_fips = "09",
                   geo_county_canonical = "Greater Bridgeport Planning Region",
                   area_share = 1, tiger_year = 2023L), tmp)   # no `straddle`
  expect_error(read_ct_planning_region_crosswalk(tmp), "straddle")
})

test_that("CT fixture reads with 091xx string GEOIDs and unique grid cells", {
  skip_if_not(file.exists(ct_fix))
  ct <- read_ct_planning_region_crosswalk(ct_fix)
  expect_true(all(ct$geo_state_abbr == "CT"))
  expect_true(all(grepl("^091[0-9]{2}$", ct$geo_county_fips)))
  expect_equal(sum(duplicated(ct[, c("lat2", "lon2")])), 0L)  # one row per cell
})

# --- ct_planning_region_for_coord ---------------------------------------------

test_that("ct_planning_region_for_coord resolves a CT coordinate to its region", {
  skip_if_not(file.exists(ct_fix))
  ct <- read_ct_planning_region_crosswalk(ct_fix)
  cell <- ct[1, ]
  # a coordinate that rounds onto the cell (offset within the 0.01-deg cell)
  res <- ct_planning_region_for_coord("CT", cell$lat2 + 0.003, cell$lon2 - 0.004, ct)
  expect_equal(res$`County FIPS`, cell$geo_county_fips)
  expect_equal(res$`Census County`, cell$geo_county_canonical)
})

test_that("ct_planning_region_for_coord only touches CT rows; NA elsewhere", {
  skip_if_not(file.exists(ct_fix))
  ct   <- read_ct_planning_region_crosswalk(ct_fix)
  cell <- ct[1, ]
  res <- ct_planning_region_for_coord(
    c("CT", "MI", "CT", NA),
    c(cell$lat2, cell$lat2, NA, cell$lat2),     # MI shares coord but isn't CT
    c(cell$lon2, cell$lon2, cell$lon2, cell$lon2)
  , ct)
  expect_equal(res$`County FIPS`,
               c(cell$geo_county_fips, NA, NA, NA))   # only the CT+coord row
})

test_that("ct_planning_region_for_coord returns NA for an off-grid coordinate", {
  skip_if_not(file.exists(ct_fix))
  ct <- read_ct_planning_region_crosswalk(ct_fix)
  res <- ct_planning_region_for_coord("CT", 0, 0, ct)   # ocean — no cell
  expect_true(is.na(res$`County FIPS`))
  expect_true(is.na(res$`Census County`))
})

# --- read_bmf integration -----------------------------------------------------

# Minimal synthetic BMF (with coords) + a county crosswalk that has NO CT entry,
# so CT starts unassigned exactly as it does in production today.
.county_xw <- tibble::tibble(
  geo_state_abbr       = c("MI", "MI"),
  geo_county_raw       = c("Wayne", "Wayne County"),
  geo_county_fips      = c("26163", "26163"),
  state_fips           = c("26", "26"),
  geo_county_canonical = c("Wayne County", "Wayne County"),
  resolution           = c("resolved", "resolved"),
  tiger_year           = c(2023L, 2023L)
)

.write_bmf <- function(ct_cell, with_coords = TRUE) {
  bmf <- tibble::tibble(
    ein               = c("010000001", "020000002"),
    nteev2            = c("EDU-B", "ART-A"),
    subsection_code   = c("03", "03"),
    foundation_code   = c("15", "15"),
    asset_amount      = c(1e6, 2e6),
    first_year_in_bmf = c(2005L, 2010L),
    last_vintage_ym   = c("2024-03", "2024-03"),
    geo_state_abbr    = c("CT", "MI"),               # one CT, one non-CT
    geo_county        = c("Fairfield County", "Wayne")
  )
  if (with_coords) {
    bmf$geo_lat <- c(ct_cell$lat2 + 0.002, 42.33)    # CT coord lands on the cell
    bmf$geo_lon <- c(ct_cell$lon2 - 0.001, -83.05)
  }
  tmp <- tempfile(fileext = ".parquet")
  arrow::write_parquet(bmf, tmp)
  tmp
}

test_that("read_bmf resolves CT by coordinate into county + FIPS + Metro/Micro", {
  skip_if_not(file.exists(ct_fix))
  ct   <- read_ct_planning_region_crosswalk(ct_fix)
  cell <- ct[ct$geo_county_fips == "09120", ][1, ]
  cbsa <- tibble::tibble(                       # CT region -> a metro
    county_fips = "09120", county_name = cell$geo_county_canonical,
    cbsa_code = "14860", cbsa_title = "Bridgeport-Stamford-Norwalk, CT",
    cbsa_type = "Metropolitan Statistical Area", central_outlying = "Central",
    csa_code = "408", csa_title = "New York-Newark, NY-NJ-CT-PA",
    delineation_year = 2023L
  )
  bmf_path <- .write_bmf(cell)

  # Baseline: WITHOUT the CT crosswalk, the CT row is unassigned (the bug).
  base <- read_bmf(bmf_path, cbsa_crosswalk = cbsa, county_crosswalk = .county_xw)
  ct_base <- base[base$`Census State` == "CT", ]
  expect_true(is.na(ct_base$`Census County`))
  expect_true(is.na(ct_base$`County FIPS`))
  expect_true(is.na(ct_base$`Metro/Micro Area`))

  # WITH the CT crosswalk, the CT row resolves to its planning region + metro.
  out <- read_bmf(bmf_path, cbsa_crosswalk = cbsa, county_crosswalk = .county_xw,
                  ct_crosswalk = ct)
  ct_out <- out[out$`Census State` == "CT", ]
  expect_equal(ct_out$`County FIPS`, "09120")
  expect_equal(ct_out$`Census County`, cell$geo_county_canonical)
  expect_equal(ct_out$`Metro/Micro Area`, "Bridgeport-Stamford-Norwalk, CT")
  expect_equal(ct_out$`CBSA Code`, "14860")

  # The non-CT (MI) row is untouched by the CT override.
  mi_out <- out[out$`Census State` == "MI", ]
  expect_equal(mi_out$`Census County`, "Wayne County")
  expect_equal(mi_out$`County FIPS`, "26163")

  # Row count is preserved — override relabels, never drops/fans out.
  expect_equal(nrow(out), nrow(base))
})

test_that("read_bmf: CT coordinate is AUTHORITATIVE, overriding a label region", {
  # The upstream county crosswalk now force-maps some bare CT labels to a single
  # planning region, which is WRONG for points whose old county spans several
  # regions (~4.5% of CT). The coordinate must win.
  skip_if_not(file.exists(ct_fix))
  ct   <- read_ct_planning_region_crosswalk(ct_fix)
  cell <- ct[ct$geo_county_fips == "09120", ][1, ]   # coordinate truth: 09120

  # County crosswalk that resolves this CT label to a DIFFERENT region (09110).
  county_xw_ct <- tibble::tibble(
    geo_state_abbr = "CT", geo_county_raw = "Fairfield County",
    geo_county_fips = "09110", state_fips = "09",
    geo_county_canonical = "Capitol Planning Region",
    resolution = "resolved", tiger_year = 2023L
  )
  bmf_path <- .write_bmf(cell)

  # Without the coordinate fix, the (wrong) label region 09110 stands.
  base <- read_bmf(bmf_path, county_crosswalk = county_xw_ct)
  expect_equal(base[base$`Census State` == "CT", ]$`County FIPS`, "09110")

  # With it, the coordinate (09120) overrides the label region.
  out <- read_bmf(bmf_path, county_crosswalk = county_xw_ct, ct_crosswalk = ct)
  expect_equal(out[out$`Census State` == "CT", ]$`County FIPS`, "09120")
})

test_that("read_bmf with ct_crosswalk degrades gracefully when coords are absent", {
  skip_if_not(file.exists(ct_fix))
  ct <- read_ct_planning_region_crosswalk(ct_fix)
  cell <- ct[1, ]
  bmf_path <- .write_bmf(cell, with_coords = FALSE)   # no geo_lat/geo_lon columns
  out <- read_bmf(bmf_path, county_crosswalk = .county_xw, ct_crosswalk = ct)
  ct_out <- out[out$`Census State` == "CT", ]
  # No coordinates -> CT cannot be coordinate-resolved; stays unassigned, no error.
  expect_true(is.na(ct_out$`Census County`))
  expect_true(is.na(ct_out$`County FIPS`))
})
