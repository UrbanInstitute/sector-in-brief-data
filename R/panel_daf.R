.DAF_DIMS <- c("Organization Type", "Subsector", "Size",
               "Census Region", "Census State", "Census County", "County FIPS",
               "Metro/Micro Area", "CBSA Code")

.daf_na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the daf panel
#'
#' Produces one row per (Year, dim) cell that has at least one BMF-active org
#' in the year. Dim cells with no DAF activity appear with `Has DAF = 0` and
#' NA dollar metrics — necessary so the dashboard's "% of nonprofits with
#' DAFs" computation has a denominator everywhere.
#'
#' `Number of Nonprofits` is the BMF active-window count per cell (same
#' semantics as the number_nonprofits panel). `Has DAF` is the count of orgs
#' in the cell with `num_dafs > 0`. The DAF Proportion view divides one by
#' the other.
#'
#' @param daf tibble from [read_daf] (canonical schema:
#'   `ein`, `tax_year`, `num_dafs`, `contributions`, `grants`, `value`).
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.DAF_DIMS`, `Year` (int32), `Number of Nonprofits`
#'   (int32), and the five DAF metrics.
#' @export
build_daf <- function(daf, org_metadata, years) {
  stopifnot(all(c("ein", .DAF_DIMS) %in% names(org_metadata)))
  stopifnot(all(c("ein", "tax_year", "num_dafs", "contributions",
                  "grants", "value") %in% names(daf)))
  years <- as.integer(years)

  # Denominator cells: BMF active-window counts per (Year, dim) — same shape
  # as the number_nonprofits panel.
  nn <- build_number_nonprofits(org_metadata, years)

  # Numerator: per-cell DAF aggregates.
  daf <- daf[!is.na(daf$tax_year) & daf$tax_year %in% years, , drop = FALSE]
  org <- org_metadata[, c("ein", .DAF_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(daf, org, by = "ein")
  joined$has_daf <- as.integer(!is.na(joined$num_dafs) & joined$num_dafs > 0)

  daf_agg <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(.DAF_DIMS, "tax_year")))) |>
    dplyr::summarise(
      `Number of DAFs`      = .daf_na_sum(.data$num_dafs),
      `Total Contributions` = .daf_na_sum(.data$contributions),
      `Total Grants`        = .daf_na_sum(.data$grants),
      `Total Value`         = .daf_na_sum(.data$value),
      `Has DAF`             = sum(.data$has_daf),
      .groups = "drop"
    ) |>
    dplyr::rename(Year = "tax_year")
  daf_agg$Year <- as.integer(daf_agg$Year)

  out <- dplyr::left_join(nn, daf_agg, by = c(.DAF_DIMS, "Year"))
  out$`Has DAF` <- dplyr::coalesce(as.integer(out$`Has DAF`), 0L)
  # Dollar metrics and Number of DAFs stay NA for cells with no DAF activity
  # — don't fabricate $0 when the org didn't file.

  out[, c(.DAF_DIMS, "Year",
          "Number of Nonprofits",
          "Number of DAFs", "Total Contributions",
          "Total Grants", "Total Value", "Has DAF")]
}
