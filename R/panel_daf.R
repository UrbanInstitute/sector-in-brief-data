.DAF_DIMS <- c("Organization Type", "Subsector", "Size",
               "Census Region", "Census State", "Census County",
               "Metro/Micro Area")

.daf_na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the daf panel
#'
#' Aggregates the DAF e-file orgs schedule by (Year, dimensions). Inner-joins
#' on `ein` — cells with no DAF activity simply don't appear (the dashboard
#' treats missing cells as zero activity).
#'
#' `Has DAF` is a count of DAF-filing orgs in the cell (per-org boolean
#' summed across orgs), not a rate. Old pipeline produced this from a BMF
#' left-join with case_when; here we just count rows where `num_dafs > 0`.
#'
#' @param daf tibble from [read_daf] (canonical schema:
#'   `ein`, `tax_year`, `num_dafs`, `contributions`, `grants`, `value`).
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.DAF_DIMS`, `Year` (int32), and the five metrics.
#' @export
build_daf <- function(daf, org_metadata, years) {
  stopifnot(all(c("ein", .DAF_DIMS) %in% names(org_metadata)))
  stopifnot(all(c("ein", "tax_year", "num_dafs", "contributions",
                  "grants", "value") %in% names(daf)))
  years <- as.integer(years)

  daf <- daf[!is.na(daf$tax_year) & daf$tax_year %in% years, , drop = FALSE]
  org <- org_metadata[, c("ein", .DAF_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(daf, org, by = "ein")
  joined$has_daf <- as.integer(!is.na(joined$num_dafs) & joined$num_dafs > 0)

  out <- joined |>
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

  out$Year <- as.integer(out$Year)
  out$`Has DAF` <- as.integer(out$`Has DAF`)
  out[, c(.DAF_DIMS, "Year",
          "Number of DAFs", "Total Contributions",
          "Total Grants", "Total Value", "Has DAF")]
}
