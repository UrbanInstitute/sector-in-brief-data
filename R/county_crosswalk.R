# County FIPS crosswalk: consume the nccs-data-bmf artifact, canonicalize the
# county dimension, and re-publish a clean canonical reference.
#
# The crosswalk is produced upstream (nccs-data-bmf resolves county identity from
# the geocoded lat/lon via a spatial join to Census TIGER counties). This repo
# only CONSUMES it: it maps the BMF's dirty free-text `geo_county` to the
# canonical Census name, and emits a small (Census State, Census County, County
# FIPS) reference so consumers (e.g. the dashboard) can filter by stable FIPS.
#
# This is the only file that knows the crosswalk's source column names.

#' Read the county FIPS crosswalk (canonical schema)
#'
#' Source: `county_fips_crosswalk.parquet` from nccs-data-bmf. One row per
#' distinct raw `(geo_state_abbr, geo_county_raw)` label the geocoder emits.
#'
#' @param path local path or S3 URI to `county_fips_crosswalk.parquet`.
#' @return tibble with `geo_state_abbr`, `geo_county_raw`, `geo_county_fips`,
#'   `state_fips`, `geo_county_canonical` (all character).
#' @export
read_county_crosswalk <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  req <- c("geo_state_abbr", "geo_county_raw", "geo_county_fips",
           "state_fips", "geo_county_canonical")
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
    geo_county_canonical = as.character(df$geo_county_canonical)
  )
}

#' Map raw `(state, county)` labels to their canonical county name
#'
#' Vectorized lookup against the crosswalk. Labels with no crosswalk match are
#' returned unchanged (NA stays NA). The crosswalk is unique on
#' `(geo_state_abbr, geo_county_raw)`; `match()` takes the first hit and never
#' fans rows out.
#'
#' @param state_abbr,county_raw character vectors (BMF geocoded state + county).
#' @param crosswalk tibble from [read_county_crosswalk].
#' @return character vector of canonical county names, same length as input.
#' @export
canonicalize_county_label <- function(state_abbr, county_raw, crosswalk) {
  idx <- match(paste(state_abbr, county_raw),
               paste(crosswalk$geo_state_abbr, crosswalk$geo_county_raw))
  canon <- crosswalk$geo_county_canonical[idx]
  ifelse(!is.na(canon), canon, county_raw)
}

#' Build the published county FIPS crosswalk artifact
#'
#' Distinct canonical `(Census State, Census County, County FIPS)` for downstream
#' FIPS-keyed county filtering. Column names follow the dashboard-facing
#' convention so the artifact joins directly onto the panels' geo dimensions.
#'
#' @param crosswalk tibble from [read_county_crosswalk].
#' @return tibble with `Census State`, `Census County`, `County FIPS`.
#' @export
build_county_crosswalk <- function(crosswalk) {
  out <- tibble::tibble(
    `Census State`  = crosswalk$geo_state_abbr,
    `Census County` = crosswalk$geo_county_canonical,
    `County FIPS`   = crosswalk$geo_county_fips
  )
  out <- dplyr::distinct(out)
  dplyr::arrange(out, .data$`Census State`, .data$`Census County`)
}
