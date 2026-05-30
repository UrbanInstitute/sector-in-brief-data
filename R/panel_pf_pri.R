.PRI_DIMS <- c("Organization Type", "Subsector", "Size",
               "Census Region", "Census State", "Census County",
               "Metro/Micro Area")

.pri_na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the pf_pri panel
#'
#' Aggregates the Form 990-PF Part IX-B program-related-investments total
#' (from the efile Phase 0 `program_related_investments` table) by (Year,
#' dimensions). 990-PF filers only. Aggregate grain — no `ein` in output.
#'
#' Supersedes the archived dataexplorer-data draft that sourced PRI from the
#' GivingTuesday 990-PF Data Mart `SUPRREINTOOT` column; the canonical source
#' is now the Urban-owned efile slice (ADR 0017).
#'
#' @param pf_pri_raw tibble from [read_pf_pri_raw] (one or more years). Must
#'   carry `ein`, `tax_year`, `program_related_investments_total`.
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.PRI_DIMS`, `Year` (int32),
#'   `Total Program-Related Investments` (double).
#' @export
build_pf_pri <- function(pf_pri_raw, org_metadata, years) {
  stopifnot(all(c("ein", .PRI_DIMS) %in% names(org_metadata)))
  stopifnot(all(c("ein", "tax_year", "program_related_investments_total")
                %in% names(pf_pri_raw)))
  years <- as.integer(years)

  pri <- pf_pri_raw[, c("ein", "tax_year",
                        "program_related_investments_total"), drop = FALSE]
  pri <- pri[!is.na(pri$tax_year) & pri$tax_year %in% years, , drop = FALSE]

  org <- org_metadata[, c("ein", .PRI_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(pri, org, by = "ein")

  out <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(.PRI_DIMS, "tax_year")))) |>
    dplyr::summarise(
      `Total Program-Related Investments` =
        .pri_na_sum(.data$program_related_investments_total),
      .groups = "drop"
    ) |>
    dplyr::rename(Year = "tax_year")

  out$Year <- as.integer(out$Year)
  out[, c(.PRI_DIMS, "Year", "Total Program-Related Investments")]
}
