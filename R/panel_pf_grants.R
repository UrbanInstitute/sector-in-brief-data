.PFG_DIMS <- c("Organization Type", "Subsector", "Size",
               "Census Region", "Census State", "Census County", "County FIPS",
               "Metro/Micro Area", "CBSA Code")

.pfg_na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the pf_grants panel
#'
#' Aggregates 990-PF grants paid out (`contributions_paid`) by (Year,
#' dimensions). Aggregate grain — note the old `nccs-dataexplorer-data`
#' pipeline shipped this panel at org grain; ADR 0010 mandates aggregate.
#'
#' @param core_990pf_raw tibble from [read_core_990pf_raw] (one or more
#'   years). Must carry `contributions_paid`.
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.PFG_DIMS`, `Year` (int32),
#'   `Total Contributions` (double).
#' @export
build_pf_grants <- function(core_990pf_raw, org_metadata, years) {
  stopifnot(all(c("ein", .PFG_DIMS) %in% names(org_metadata)))
  stopifnot("contributions_paid" %in% names(core_990pf_raw))
  years <- as.integer(years)

  pf <- core_990pf_raw[, c("ein", "tax_year", "contributions_paid"), drop = FALSE]
  pf <- pf[!is.na(pf$tax_year) & pf$tax_year %in% years, , drop = FALSE]

  org <- org_metadata[, c("ein", .PFG_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(pf, org, by = "ein")

  out <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(.PFG_DIMS, "tax_year")))) |>
    dplyr::summarise(
      `Total Contributions` = .pfg_na_sum(.data$contributions_paid),
      .groups = "drop"
    ) |>
    dplyr::rename(Year = "tax_year")

  out$Year <- as.integer(out$Year)
  out[, c(.PFG_DIMS, "Year", "Total Contributions")]
}
