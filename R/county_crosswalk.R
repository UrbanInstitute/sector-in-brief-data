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

#' Read the Connecticut planning-region crosswalk (canonical schema)
#'
#' Source: `ct_planning_region_crosswalk.parquet` from nccs-data-bmf. Connecticut
#' retired its 8 historical counties for 9 Census planning regions (GEOIDs
#' `09110`–`09190`) effective 2022, and each old county spans MULTIPLE planning
#' regions — so CT cannot be resolved at the `(state, county-label)` grain the
#' county FIPS crosswalk uses (all 8 CT labels are `ambiguous`/deferred → NA FIPS
#' there). CT is instead resolved by COORDINATE: this artifact is one row per
#' CT-land 0.01-degree grid cell, cut from TIGER 2023 planning-region polygons,
#' so every CT coordinate lands on a cell.
#'
#' Grain: unique on `(lat2, lon2)` — the assigned region is the area-majority
#' when a cell straddles a boundary (`straddle = TRUE`, advisory, ~1.3% of land
#' cells). Vintage-coupled with the county FIPS + CBSA crosswalks (TIGER/OMB
#' 2023); do not mix vintages across the three.
#'
#' @param path local path or S3 URI to `ct_planning_region_crosswalk.parquet`.
#' @return tibble with `geo_state_abbr`, `geo_county_fips`, `state_fips`,
#'   `geo_county_canonical` (character — GEOIDs keep leading zeros), `lat2`,
#'   `lon2`, `area_share` (numeric), `straddle` (logical), `tiger_year`
#'   (integer).
#' @export
read_ct_planning_region_crosswalk <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  req <- c("geo_state_abbr", "lat2", "lon2", "geo_county_fips", "state_fips",
           "geo_county_canonical", "area_share", "straddle", "tiger_year")
  for (col in req) {
    if (!col %in% names(df)) {
      stop("read_ct_planning_region_crosswalk: expected column '", col,
           "' missing from ", path, call. = FALSE)
    }
  }
  tibble::tibble(
    geo_state_abbr       = as.character(df$geo_state_abbr),
    lat2                 = as.numeric(df$lat2),
    lon2                 = as.numeric(df$lon2),
    geo_county_fips      = as.character(df$geo_county_fips),
    state_fips           = as.character(df$state_fips),
    geo_county_canonical = as.character(df$geo_county_canonical),
    area_share           = as.numeric(df$area_share),
    straddle             = as.logical(df$straddle),
    tiger_year           = as.integer(df$tiger_year)
  )
}

#' Resolve Connecticut rows to a planning region by coordinate
#'
#' Companion to the label-based [canonicalize_county_label] /
#' [county_fips_for_label], for Connecticut only. Rounds each row's geocoded
#' `(geo_lat, geo_lon)` to the 0.01-degree grid and joins the CT crosswalk to
#' recover the planning-region GEOID + canonical name. Only `geo_state_abbr ==
#' "CT"` rows with non-NA coordinates are resolved; every other row returns NA
#' so the caller keeps its label-resolved value untouched. The crosswalk is
#' unique on `(lat2, lon2)`, so `match()` never fans rows out.
#'
#' Grid keys are formatted to exactly 2 decimals on BOTH sides (`sprintf`),
#' making the join robust to floating-point noise.
#'
#' @param state_abbr character vector (BMF geocoded state abbr).
#' @param geo_lat,geo_lon numeric vectors (BMF geocoded coordinates).
#' @param crosswalk tibble from [read_ct_planning_region_crosswalk].
#' @return tibble with `Census County` (canonical planning-region name) and
#'   `County FIPS` (091xx GEOID), NA outside CT / where the coordinate is
#'   missing, same length as the inputs.
#' @export
ct_planning_region_for_coord <- function(state_abbr, geo_lat, geo_lon, crosswalk) {
  n <- length(state_abbr)
  fips <- rep(NA_character_, n)
  name <- rep(NA_character_, n)

  is_ct <- !is.na(state_abbr) & state_abbr == "CT" &
           !is.na(geo_lat) & !is.na(geo_lon)
  if (any(is_ct)) {
    key_in <- paste(sprintf("%.2f", geo_lat[is_ct]),
                    sprintf("%.2f", geo_lon[is_ct]))
    key_xw <- paste(sprintf("%.2f", crosswalk$lat2),
                    sprintf("%.2f", crosswalk$lon2))
    idx <- match(key_in, key_xw)
    fips[is_ct] <- crosswalk$geo_county_fips[idx]
    name[is_ct] <- crosswalk$geo_county_canonical[idx]
  }
  tibble::tibble(`Census County` = name, `County FIPS` = fips)
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
