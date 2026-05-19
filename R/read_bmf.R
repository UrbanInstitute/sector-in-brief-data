#' Read bmf-master-geocoded and emit canonical pipeline schema
#'
#' Single source-of-truth boundary between the new BMF column names and the
#' rest of this pipeline. No other R file in this package should reference
#' new-BMF column names (`subsection_code`, `foundation_code`, `geo_*`, etc.).
#' Panel builders consume only the canonical output of this function.
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
#'   \item `Census County` — character, county name.
#'   \item `Metro/Micro Area` — character, CBSA name from the crosswalk; NA on
#'         miss (no CBSA assignment, e.g. rural counties).
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
#' @param cbsa_crosswalk Path to the (state, county) → CBSA parquet. Defaults
#'   to the package's `inst/lookups/cbsa_crosswalk.parquet`.
#' @return tibble with the canonical schema above.
#' @export
read_bmf <- function(path,
                     cbsa_crosswalk = system.file("lookups", "cbsa_crosswalk.parquet",
                                                  package = "sectorinbriefdata")) {
  if (!nzchar(cbsa_crosswalk) || !file.exists(cbsa_crosswalk)) {
    # When running pre-install (e.g. during dev tests), fall back to repo path.
    cbsa_crosswalk <- file.path("inst", "lookups", "cbsa_crosswalk.parquet")
  }
  stopifnot(file.exists(cbsa_crosswalk))

  bmf <- arrow::read_parquet(path)
  cbsa <- arrow::read_parquet(cbsa_crosswalk)

  # Upstream BMF occasionally emits "" instead of NA for ungeocoded geo cells.
  # Normalize so downstream filters and joins treat them consistently.
  na_if_blank <- function(x) ifelse(!is.na(x) & nzchar(trimws(x)), x, NA_character_)
  bmf$geo_state_abbr <- na_if_blank(bmf$geo_state_abbr)
  bmf$geo_county     <- na_if_blank(bmf$geo_county)

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
    `Census State`   = bmf$geo_state_abbr,
    `Census County`  = bmf$geo_county
  )

  # Join CBSA name; NA when no match (rural counties, or missing geo).
  out <- dplyr::left_join(
    out,
    dplyr::select(cbsa, state_abbr, county, `Metro/Micro Area`),
    by = c("Census State" = "state_abbr", "Census County" = "county")
  )

  out$`Census Region`     <- derive_census_region(out$`Census State`)
  out$Subsector           <- derive_subsector(out$nteev2)
  out$`Organization Type` <- derive_organization_type(out$subsection_code,
                                                     out$foundation_code)

  out[, c("ein", "nteev2", "subsection_code", "foundation_code",
          "asset_amount", "org_year_first", "org_year_last",
          "Census State", "Census County", "Metro/Micro Area",
          "Census Region", "Subsector", "Organization Type")]
}
