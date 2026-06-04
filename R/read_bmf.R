#' Read bmf-master-geocoded and emit canonical pipeline schema
#'
#' Single source-of-truth boundary between the new BMF column names and the
#' rest of this pipeline. No other R file in this package should reference
#' new-BMF column names (`subsection_code`, `foundation_code`, `geo_*`, etc.).
#' Panel builders consume only the canonical output of this function.
#'
#' Geography is resolved here via two crosswalks (both optional; absent → graceful
#' pass-through). The county crosswalk canonicalizes the dirty free-text county
#' label to a single Census name + stable `County FIPS` (NA for ambiguous /
#' unresolved labels, which become honest "unassigned"). The CBSA crosswalk then
#' rolls the county up to its Metro/Micro area by FIPS (collision-proof). FIPS /
#' CBSA codes are the identity key; the names are for display.
#'
#' Output columns:
#' \itemize{
#'   \item `ein` — character, canonical `XX-XXXXXXX` form (normalized via
#'         `nccsdata::nccs_normalize_ein`).
#'   \item `nteev2` — character, full NTEEv2 code.
#'   \item `subsection_code` — character, raw IRS subsection code.
#'   \item `foundation_code` — character, raw IRS foundation code.
#'   \item `asset_amount` — double, total assets in dollars.
#'   \item `org_year_first` — integer, first BMF observation year.
#'   \item `org_year_last`  — integer, last BMF observation year (parsed from
#'         `last_vintage_ym`'s `YYYY-MM`).
#'   \item `Census State` — character, 2-letter postal code.
#'   \item `Census County` — character, canonical county name; NA when the label
#'         was ambiguous / unresolved (unassigned) or no county crosswalk given.
#'   \item `County FIPS` — character, 5-char county GEOID; NA when unassigned.
#'   \item `Metro/Micro Area` — character, CBSA name; NA when rural (no CBSA) or
#'         the county is unassigned.
#'   \item `CBSA Code` — character, OMB CBSA code; NA likewise.
#'   \item `Census Region` — character, derived from state.
#'   \item `Subsector` — character, 3-character NTEE major.
#'   \item `Organization Type` — character, dashboard-canonical label.
#' }
#'
#' Size is intentionally **not** computed here; it is an org-level static
#' derived from CORE expenses and joined in by `build_org_metadata()` once
#' both readers have run.
#'
#' @param path Either an S3 URI (`s3://...`), a local path to the parquet, or
#'   a path to a fixture. The function only does parquet read + dplyr
#'   transformations; the caller is responsible for materializing S3 inputs
#'   to a local cache if needed.
#' @param cbsa_crosswalk Path (or pre-read tibble from [read_cbsa_crosswalk]) to
#'   the county-FIPS → CBSA crosswalk, or `NULL` to skip CBSA assignment (Metro/
#'   Micro Area + CBSA Code become NA).
#' @param county_crosswalk Path (or pre-read tibble from [read_county_crosswalk])
#'   to the county FIPS crosswalk, or `NULL` to pass county labels through raw
#'   (no canonicalization, no FIPS, no CBSA).
#' @return tibble with the canonical schema above.
#' @export
read_bmf <- function(path, cbsa_crosswalk = NULL, county_crosswalk = NULL) {
  bmf <- arrow::read_parquet(path)

  # Upstream BMF occasionally emits "" instead of NA for ungeocoded geo cells.
  # Normalize so downstream filters and joins treat them consistently.
  na_if_blank <- function(x) ifelse(!is.na(x) & nzchar(trimws(x)), x, NA_character_)
  geo_state  <- na_if_blank(bmf$geo_state_abbr)
  geo_county <- na_if_blank(bmf$geo_county)

  # Canonicalize the county label against the published FIPS crosswalk and pull
  # the stable County FIPS. Non-resolved / unknown labels resolve to NA (honest
  # "unassigned") rather than passing the raw text through. Without a crosswalk
  # we pass the raw label through and have no FIPS.
  if (!is.null(county_crosswalk)) {
    cxw <- if (is.character(county_crosswalk))
      read_county_crosswalk(county_crosswalk) else county_crosswalk
    census_county <- canonicalize_county_label(geo_state, geo_county, cxw)
    county_fips   <- county_fips_for_label(geo_state, geo_county, cxw)
  } else {
    census_county <- geo_county
    county_fips   <- rep(NA_character_, length(geo_county))
  }

  # Parse "YYYY-MM" → integer YYYY for org_year_last.
  org_year_last <- suppressWarnings(
    as.integer(substr(bmf$last_vintage_ym, 1, 4))
  )

  out <- tibble::tibble(
    ein              = nccsdata::nccs_normalize_ein(bmf$ein),
    nteev2           = bmf$nteev2,
    subsection_code  = bmf$subsection_code,
    foundation_code  = bmf$foundation_code,
    asset_amount     = suppressWarnings(as.numeric(bmf$asset_amount)),
    org_year_first   = as.integer(bmf$first_year_in_bmf),
    org_year_last    = org_year_last,
    `Census State`   = geo_state,
    `Census County`  = census_county,
    `County FIPS`    = county_fips
  )

  # Roll county up to its CBSA by FIPS (collision-proof). NA when no FIPS
  # (unassigned county), no CBSA (rural), or no crosswalk supplied.
  if (!is.null(cbsa_crosswalk)) {
    cbsa <- if (is.character(cbsa_crosswalk))
      read_cbsa_crosswalk(cbsa_crosswalk) else cbsa_crosswalk
    idx <- match(out$`County FIPS`, cbsa$county_fips)
    out$`Metro/Micro Area` <- cbsa$cbsa_title[idx]
    out$`CBSA Code`        <- cbsa$cbsa_code[idx]
  } else {
    out$`Metro/Micro Area` <- NA_character_
    out$`CBSA Code`        <- NA_character_
  }

  out$`Census Region`     <- derive_census_region(out$`Census State`)
  out$Subsector           <- derive_subsector(out$nteev2)
  out$`Organization Type` <- derive_organization_type(out$subsection_code,
                                                     out$foundation_code)

  out[, c("ein", "nteev2", "subsection_code", "foundation_code",
          "asset_amount", "org_year_first", "org_year_last",
          "Census State", "Census County", "County FIPS",
          "Metro/Micro Area", "CBSA Code",
          "Census Region", "Subsector", "Organization Type")]
}
