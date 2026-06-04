# County FIPS + CBSA crosswalks: consume the nccs-data-bmf artifacts, canonicalize
# the county dimension, attach stable FIPS / CBSA codes, and re-publish clean
# canonical references.
#
# The crosswalks are produced upstream by nccs-data-bmf (county identity resolved
# from the geocoded lat/lon via a spatial join to Census TIGER counties; CBSA
# membership from the OMB delineation). This repo only CONSUMES them: it maps the
# BMF's dirty free-text geo_county to a canonical Census name + stable FIPS, rolls
# counties up to CBSAs by FIPS, and emits small audit references for downstream
# FIPS-keyed filtering.
#
# This is the only file that knows the crosswalks' source column names.

#' Read the county FIPS crosswalk (canonical schema)
#'
#' Source: `county_fips_crosswalk.parquet` from nccs-data-bmf. One row per
#' distinct raw `(geo_state_abbr, geo_county_raw)` label the geocoder emits.
#' `resolution` is the upstream verdict on whether the label maps to exactly one
#' Census county:
#' \itemize{
#'   \item `resolved` — unambiguous; `geo_county_fips` + `geo_county_canonical`
#'         populated.
#'   \item `ambiguous` — the label could be more than one county (e.g. bare
#'         "Baltimore" = city 24510 vs county 24005; the CT planning-region
#'         labels). FIPS + canonical are NA.
#'   \item `unresolved` — cross-state mislabel (county not in the stated state).
#'         FIPS + canonical are NA.
#' }
#'
#' @param path local path or S3 URI to `county_fips_crosswalk.parquet`.
#' @return tibble with `geo_state_abbr`, `geo_county_raw`, `geo_county_fips`,
#'   `state_fips`, `geo_county_canonical`, `resolution` (all character) and
#'   `tiger_year` (integer). FIPS columns are character so leading zeros survive.
#' @export
read_county_crosswalk <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  req <- c("geo_state_abbr", "geo_county_raw", "geo_county_fips", "state_fips",
           "geo_county_canonical", "resolution", "tiger_year")
  for (col in req) {
    if (!col %in% names(df)) {
      stop("read_county_crosswalk: expected column '", col,
           "' missing from ", path, call. = FALSE)
    }
  }
  tibble::tibble(
    geo_state_abbr       = as.character(df$geo_state_abbr),
    geo_county_raw       = as.character(df$geo_county_raw),
    geo_county_fips      = as.character(df$geo_county_fips),
    state_fips           = as.character(df$state_fips),
    geo_county_canonical = as.character(df$geo_county_canonical),
    resolution           = as.character(df$resolution),
    tiger_year           = as.integer(df$tiger_year)
  )
}

#' Read the CBSA crosswalk (canonical schema)
#'
#' Source: `cbsa_crosswalk.parquet` from nccs-data-bmf. One row per county FIPS,
#' mapping it to its OMB CBSA (Metropolitan/Micropolitan area) and CSA.
#'
#' Caveat: this universe is DATA-DERIVED — only counties with `resolution ==
#' "resolved"` that appear in our geocoded data, left-joined to OMB. It is fine
#' for record-level joins but is NOT the full OMB county/CBSA universe; do not
#' reuse it as a complete allowlist for UI dropdowns.
#'
#' @param path local path or S3 URI to `cbsa_crosswalk.parquet`.
#' @return tibble with `county_fips`, `county_name`, `cbsa_code`, `cbsa_title`,
#'   `cbsa_type`, `central_outlying`, `csa_code`, `csa_title` (character) and
#'   `delineation_year` (integer). FIPS/codes are character (leading zeros).
#' @export
read_cbsa_crosswalk <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  req <- c("county_fips", "county_name", "cbsa_code", "cbsa_title", "cbsa_type",
           "central_outlying", "csa_code", "csa_title", "delineation_year")
  for (col in req) {
    if (!col %in% names(df)) {
      stop("read_cbsa_crosswalk: expected column '", col,
           "' missing from ", path, call. = FALSE)
    }
  }
  tibble::tibble(
    county_fips      = as.character(df$county_fips),
    county_name      = as.character(df$county_name),
    cbsa_code        = as.character(df$cbsa_code),
    cbsa_title       = as.character(df$cbsa_title),
    cbsa_type        = as.character(df$cbsa_type),
    central_outlying = as.character(df$central_outlying),
    csa_code         = as.character(df$csa_code),
    csa_title        = as.character(df$csa_title),
    delineation_year = as.integer(df$delineation_year)
  )
}

#' Map raw `(state, county)` labels to their canonical county name
#'
#' Vectorized lookup against the crosswalk. Returns the canonical name, or `NA`
#' when the label is non-resolved (ambiguous/unresolved — canonical is NA in the
#' crosswalk) or absent from the crosswalk. A non-resolved or unknown label is
#' therefore treated as **unassigned** rather than passed through verbatim, so an
#' ambiguous "Baltimore" never masquerades as a clean county. The crosswalk is
#' unique on `(geo_state_abbr, geo_county_raw)`; `match()` takes the first hit
#' and never fans rows out.
#'
#' @param state_abbr,county_raw character vectors (BMF geocoded state + county).
#' @param crosswalk tibble from [read_county_crosswalk].
#' @return character vector of canonical county names (NA where unresolved/
#'   unknown), same length as input.
#' @export
canonicalize_county_label <- function(state_abbr, county_raw, crosswalk) {
  idx <- match(paste(state_abbr, county_raw),
               paste(crosswalk$geo_state_abbr, crosswalk$geo_county_raw))
  crosswalk$geo_county_canonical[idx]
}

#' Map raw `(state, county)` labels to their county FIPS
#'
#' Companion to [canonicalize_county_label]. Returns the 5-character county
#' GEOID, or `NA` for non-resolved/unknown labels. Same `match()` semantics.
#'
#' @param state_abbr,county_raw character vectors.
#' @param crosswalk tibble from [read_county_crosswalk].
#' @return character vector of county FIPS (NA where unresolved/unknown).
#' @export
county_fips_for_label <- function(state_abbr, county_raw, crosswalk) {
  idx <- match(paste(state_abbr, county_raw),
               paste(crosswalk$geo_state_abbr, crosswalk$geo_county_raw))
  crosswalk$geo_county_fips[idx]
}

#' Build the published county FIPS crosswalk artifact
#'
#' Audit reference: one row per distinct raw `(state, county)` label and its
#' fate. Carries the raw label, the canonical name + FIPS (NA when unresolved),
#' and the `resolution` verdict so consumers can (a) join a canonical county name
#' to its stable FIPS and (b) explain every NA FIPS. Column names follow the
#' dashboard-facing convention.
#'
#' @param crosswalk tibble from [read_county_crosswalk].
#' @return tibble with `Census State`, `County (raw)`, `Census County`,
#'   `County FIPS`, `Resolution`.
#' @export
build_county_crosswalk <- function(crosswalk) {
  out <- tibble::tibble(
    `Census State`  = crosswalk$geo_state_abbr,
    `County (raw)`  = crosswalk$geo_county_raw,
    `Census County` = crosswalk$geo_county_canonical,
    `County FIPS`   = crosswalk$geo_county_fips,
    Resolution      = crosswalk$resolution
  )
  out <- dplyr::distinct(out)
  dplyr::arrange(out, .data$`Census State`, .data$`County (raw)`)
}

#' Build the published CBSA crosswalk artifact
#'
#' County FIPS -> OMB Metro/Micro area + CSA, for FIPS-keyed metro rollups and
#' audit. Drops the crosswalk's `county_name` (a duplicate of the canonical
#' county name already published in [build_county_crosswalk]).
#'
#' Caveat (carried in the data dictionary too): DATA-DERIVED universe — only
#' resolved counties present in our geocoded data, left-joined to OMB. Not the
#' full OMB universe; not a dropdown allowlist source.
#'
#' @param cbsa tibble from [read_cbsa_crosswalk].
#' @return tibble with `County FIPS`, `CBSA Code`, `Metro/Micro Area`,
#'   `CBSA Type`, `Central/Outlying`, `CSA Code`, `CSA Title`,
#'   `Delineation Year`.
#' @export
build_cbsa_crosswalk <- function(cbsa) {
  out <- tibble::tibble(
    `County FIPS`      = cbsa$county_fips,
    `CBSA Code`        = cbsa$cbsa_code,
    `Metro/Micro Area` = cbsa$cbsa_title,
    `CBSA Type`        = cbsa$cbsa_type,
    `Central/Outlying` = cbsa$central_outlying,
    `CSA Code`         = cbsa$csa_code,
    `CSA Title`        = cbsa$csa_title,
    `Delineation Year` = cbsa$delineation_year
  )
  out <- dplyr::distinct(out)
  dplyr::arrange(out, .data$`County FIPS`)
}
