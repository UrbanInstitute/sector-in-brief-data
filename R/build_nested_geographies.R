#' Build the nested_geographies dimension table (geography lookup)
#'
#' One row per distinct geography tuple observed in the BMF, carrying both the
#' display names and the stable codes:
#' `Census State`, `Census County`, `County FIPS`, `Metro/Micro Area`,
#' `CBSA Code`, `Census Region`. This is the single lookup the dashboard joins
#' for the cascading State → County → CBSA dropdowns and for FIPS/CBSA-keyed
#' filtering.
#'
#' It is the **data-derived allowlist**: it contains only geographies actually
#' present in our data. Rows with NA `Census County` (labels that were
#' ambiguous/unresolved upstream — "unassigned") are dropped: they are not
#' selectable counties. Rural counties (valid `County FIPS`, NA `Metro/Micro
#' Area`/`CBSA Code`) are kept. The "N records unassigned" statistic is NOT
#' derived from this table — the dashboard computes it from the NA-geography
#' cells in each panel.
#'
#' @param bmf tibble from [read_bmf] (carries the geo names + codes).
#' @return tibble with 6 columns, distinct.
#' @export
build_nested_geographies <- function(bmf) {
  cols <- c("Census State", "Census County", "County FIPS",
            "Metro/Micro Area", "CBSA Code", "Census Region")
  stopifnot(all(cols %in% names(bmf)))

  geo <- bmf[, cols, drop = FALSE]
  # Drop unassigned rows (no canonical county) — not selectable in a dropdown.
  geo <- geo[!is.na(geo$`Census County`), , drop = FALSE]
  geo <- dplyr::distinct(geo)
  geo <- dplyr::arrange(geo,
                        .data$`Census Region`,
                        .data$`Census State`,
                        .data$`Census County`,
                        .data$`Metro/Micro Area`)
  tibble::as_tibble(geo)
}
