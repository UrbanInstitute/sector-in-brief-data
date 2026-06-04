.NN_DIMS <- c("Organization Type", "Subsector", "Size",
              "Census Region", "Census State", "Census County", "County FIPS",
              "Metro/Micro Area", "CBSA Code")

#' Build the number_nonprofits panel
#'
#' For each year in `years`, counts organizations whose BMF window covers
#' that year (`org_year_first <= year <= org_year_last`) and groups by the
#' canonical dashboard dimensions. Aggregate grain — no `ein` in output.
#'
#' Active-org rule: BMF window. Locked in 2026-05-19.
#'
#' @param org_metadata tibble from [build_org_metadata].
#' @param years integer vector of years to expand the panel over.
#' @return tibble with columns: `.NN_DIMS`, `Year` (int32),
#'   `Number of Nonprofits` (int32).
#' @export
build_number_nonprofits <- function(org_metadata, years) {
  stopifnot(all(c("org_year_first", "org_year_last", .NN_DIMS) %in% names(org_metadata)))
  years <- as.integer(years)

  # For memory: drop columns we don't need, then expand active-EIN-by-year via
  # an interval join. Equivalent to:
  #   tidyr::crossing(org, Year=years) |> filter(first<=Year<=last) |> count(...)
  # but the lapply/bind form avoids materializing a giant cross product.
  slim <- org_metadata[, c("org_year_first", "org_year_last", .NN_DIMS)]

  per_year <- lapply(years, function(y) {
    active <- slim[!is.na(slim$org_year_first) & !is.na(slim$org_year_last) &
                     slim$org_year_first <= y & slim$org_year_last >= y, ]
    if (nrow(active) == 0) return(NULL)
    counts <- dplyr::count(active, dplyr::across(dplyr::all_of(.NN_DIMS)),
                           name = "Number of Nonprofits")
    counts$Year <- y
    counts
  })

  out <- dplyr::bind_rows(per_year)
  out$Year <- as.integer(out$Year)
  out$`Number of Nonprofits` <- as.integer(out$`Number of Nonprofits`)
  out[, c(.NN_DIMS, "Year", "Number of Nonprofits")]
}
