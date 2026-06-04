.FIN_DIMS <- c("Organization Type", "Subsector", "Size",
               "Census Region", "Census State", "Census County", "County FIPS",
               "Metro/Micro Area", "CBSA Code")
.FIN_METRICS <- c("Total Revenues", "Total Expenses",
                  "Total Assets", "Total Benefits")

# Sum that preserves NA for all-NA groups. `sum(x, na.rm=TRUE)` collapses
# all-NA inputs to 0, which would silently fabricate a $0 Total Benefits
# value for every pre-2012 (Year, dim) cell — the discontinuity must remain
# visible (see [[project-total-benefits-pre-2012]]).
.na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the finances panel
#'
#' Stacks the canonical CORE 990combined + 990PF rows, joins BMF-derived
#' dimensions via `org_metadata`, and sums the four finance metrics by
#' (Year, dimensions). Aggregate grain — no `ein` in output.
#'
#' `Size` is the static per-EIN value attached upstream by
#' [build_org_metadata]; it does **not** float with per-year expenses.
#'
#' @param core_990 tibble in `.CORE_CANONICAL` schema (one or more years
#'   of 990combined), or NULL.
#' @param core_990pf tibble in `.CORE_CANONICAL` schema (one or more years
#'   of 990PF), or NULL.
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.FIN_DIMS`, `Year` (int32), and the four metrics
#'   (double).
#' @export
build_finances <- function(core_990, core_990pf, org_metadata, years) {
  stopifnot(all(c("ein", .FIN_DIMS) %in% names(org_metadata)))
  years <- as.integer(years)

  keep_cols <- c("ein", "tax_year", "total_revenue", "total_expenses",
                 "total_assets", "total_benefits")
  parts <- list()
  if (!is.null(core_990))   parts$c990 <- core_990[,   keep_cols, drop = FALSE]
  if (!is.null(core_990pf)) parts$cpf  <- core_990pf[, keep_cols, drop = FALSE]
  core <- dplyr::bind_rows(parts)
  core <- core[!is.na(core$tax_year) & core$tax_year %in% years, , drop = FALSE]

  org <- org_metadata[, c("ein", .FIN_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(core, org, by = "ein")

  out <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(.FIN_DIMS, "tax_year")))) |>
    dplyr::summarise(
      `Total Revenues` = .na_sum(.data$total_revenue),
      `Total Expenses` = .na_sum(.data$total_expenses),
      `Total Assets`   = .na_sum(.data$total_assets),
      `Total Benefits` = .na_sum(.data$total_benefits),
      .groups = "drop"
    ) |>
    dplyr::rename(Year = "tax_year")

  out$Year <- as.integer(out$Year)
  out[, c(.FIN_DIMS, "Year", .FIN_METRICS)]
}
