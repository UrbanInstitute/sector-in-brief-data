.GG_DIMS <- c("Organization Type", "Subsector", "Size",
              "Census Region", "Census State", "Census County",
              "Metro/Micro Area")

.gg_na_sum <- function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)

#' Build the government_grants panel
#'
#' Aggregates government grants/contributions **received** (Form 990 Part VIII
#' line 1e, from the efile Phase 0 `government_grants` table) by (Year,
#' dimensions). 990 filers only (the source carries no other form). Aggregate
#' grain — no `ein` in output.
#'
#' `Size` is the static per-EIN band attached by [build_org_metadata]; it is
#' NOT re-derived from efile expenses (the archived dataexplorer-data draft did
#' that — superseded by the locked static-Size model).
#'
#' @param gov_grants_raw tibble from [read_government_grants_raw] (one or more years).
#'   Must carry `ein`, `tax_year`, `government_grants`.
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of tax years to keep.
#' @return tibble with `.GG_DIMS`, `Year` (int32), `Total Government Grants`
#'   (double).
#' @export
build_government_grants <- function(gov_grants_raw, org_metadata, years) {
  stopifnot(all(c("ein", .GG_DIMS) %in% names(org_metadata)))
  stopifnot(all(c("ein", "tax_year", "government_grants") %in% names(gov_grants_raw)))
  years <- as.integer(years)

  gg <- gov_grants_raw[, c("ein", "tax_year", "government_grants"), drop = FALSE]
  gg <- gg[!is.na(gg$tax_year) & gg$tax_year %in% years, , drop = FALSE]

  org <- org_metadata[, c("ein", .GG_DIMS), drop = FALSE]
  joined <- dplyr::inner_join(gg, org, by = "ein")

  out <- joined |>
    dplyr::group_by(dplyr::across(dplyr::all_of(c(.GG_DIMS, "tax_year")))) |>
    dplyr::summarise(
      `Total Government Grants` = .gg_na_sum(.data$government_grants),
      .groups = "drop"
    ) |>
    dplyr::rename(Year = "tax_year")

  out$Year <- as.integer(out$Year)
  out[, c(.GG_DIMS, "Year", "Total Government Grants")]
}
