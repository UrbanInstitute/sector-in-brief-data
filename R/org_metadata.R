#' Build the org-level metadata table (BMF + static Size)
#'
#' Joins the canonical BMF output of [read_bmf] with a per-EIN static `Size`
#' derived from the most recent observed total_expenses across CORE 990 and
#' CORE 990-PF (whichever produced a non-NA value most recently). EINs with no
#' CORE filing — or no non-NA expense across any CORE filing — receive
#' `Size = 0` (the "Not reported" band). Static Size is the design locked in
#' on 2026-05-19 (see project-data-model memory): consumers downstream
#' inherit a stable per-EIN Size, so a user filtering by Size sees the same
#' EIN cohort across every panel.
#'
#' @param bmf tibble from [read_bmf].
#' @param core_990 tibble from [read_core_990_year] (one or more years of
#'   990combined, stacked), or NULL to skip the 990 contribution.
#' @param core_990pf tibble from [read_core_990pf] (one or more years), or
#'   NULL to skip the 990PF contribution.
#' @return tibble = bmf columns + `Size` (int32 0–6).
#' @export
build_org_metadata <- function(bmf, core_990 = NULL, core_990pf = NULL) {
  stopifnot("ein" %in% names(bmf))

  # Stack any provided CORE sources, keep only ein + tax_year + total_expenses.
  core_parts <- list()
  if (!is.null(core_990))   core_parts$c990   <- core_990[, c("ein", "tax_year", "total_expenses")]
  if (!is.null(core_990pf)) core_parts$cpf    <- core_990pf[, c("ein", "tax_year", "total_expenses")]
  core_long <- if (length(core_parts) > 0) dplyr::bind_rows(core_parts) else
    tibble::tibble(ein = character(0), tax_year = integer(0),
                   total_expenses = numeric(0))

  # Most-recent non-NA expense per EIN.
  size_lookup <- core_long |>
    dplyr::filter(!is.na(total_expenses)) |>
    dplyr::group_by(ein) |>
    dplyr::slice_max(tax_year, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::transmute(ein,
                     Size = derive_size(total_expenses))

  dplyr::left_join(bmf, size_lookup, by = "ein") |>
    dplyr::mutate(Size = dplyr::coalesce(.data$Size, 0L))
}
