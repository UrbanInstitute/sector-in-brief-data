#' Census region from 2-letter state abbreviation
#'
#' Ported verbatim from `nccs-dataexplorer-data/R/01_bmf_data.R:16-21`.
#' Returns one of "Northeast", "Midwest", "South", "West", or NA for
#' unmatched states (territories, military codes, etc.).
#'
#' @param state_abbr character vector of 2-letter postal codes.
#' @return character vector of region names.
#' @export
derive_census_region <- function(state_abbr) {
  dplyr::case_when(
    state_abbr %in% c("CT", "ME", "MA", "NH", "RI", "VT", "NJ", "NY", "PA") ~ "Northeast",
    state_abbr %in% c("IL", "IN", "MI", "OH", "WI", "IA", "KS", "MN", "MO", "NE", "ND", "SD") ~ "Midwest",
    state_abbr %in% c("DE", "DC", "FL", "GA", "MD", "NC", "SC", "VA", "WV", "AL", "KY", "MS", "TN", "AR", "LA", "OK", "TX") ~ "South",
    state_abbr %in% c("AZ", "CO", "ID", "MT", "NV", "NM", "UT", "WY", "AK", "CA", "HI", "OR", "WA") ~ "West"
  )
}

#' NTEE major subsector (3-character code) from full NTEEv2
#'
#' Returns one of 12 NTEE majors: ART EDU HEL HMS IFA PSB REL MMB UNI HOS ENV UNU.
#' Equivalent to bmf-master-geocoded's `nteev2_subsector` column; we derive it
#' from `nteev2` for parity with the old pipeline and so it works on any
#' upstream that exposes only the full NTEEv2 string.
#'
#' @param nteev2 character vector of NTEEv2 codes.
#' @return character vector of 3-character subsector codes.
#' @export
derive_subsector <- function(nteev2) {
  out <- substr(nteev2, 1, 3)
  out[is.na(nteev2)] <- NA_character_
  out
}

#' Size band (ordinal 0-6) from total expenses
#'
#' Ported verbatim from `nccs-dataexplorer-data/R/03_extract_expenses.R:72-82`.
#' Keyed on expenses (NOT assets — old `01_bmf_data.R` keyed on assets, which
#' was inconsistent with the dashboard's documented bands; expenses is the
#' canonical rule per ADR 0010). Returns an integer ordinal:
#'
#' \tabular{rl}{
#'   0 \tab NA / unknown \cr
#'   1 \tab Under $100,000 \cr
#'   2 \tab $100,000 - $499,999 \cr
#'   3 \tab $500,000 - $999,999 \cr
#'   4 \tab $1M - $4.99M \cr
#'   5 \tab $5M - $9.99M \cr
#'   6 \tab $10M+
#' }
#'
#' @param total_expenses numeric vector of total annual expenses in dollars.
#' @return integer vector of band codes (0-6).
#' @export
derive_size <- function(total_expenses) {
  as.integer(dplyr::case_when(
    is.na(total_expenses)        ~ 0,
    total_expenses < 100000      ~ 1,
    total_expenses < 499999      ~ 2,
    total_expenses < 999999      ~ 3,
    total_expenses < 4999999     ~ 4,
    total_expenses < 9999999     ~ 5,
    total_expenses > 9999999     ~ 6,
    .default = 0
  ))
}

# bmf-master-geocoded foundation_code values that indicate a private foundation
# (confirmed empirically from the fixture: codes 2, 3, 4 map to
# "Private operating foundation exempt...", "Private operating foundation",
# "Private non-operating foundation" respectively).
.PRIVATE_FOUNDATION_FOUNDATION_CODES <- c("2", "3", "4")

#' Organization Type label
#'
#' Adapts the old `01_bmf_data.R:23-33` `case_when` to the new BMF, which
#' exposes `foundation_code` instead of the old `NCCS_LEVEL_1` flag. For
#' `subsection_code == 3`, distinguishes private foundations (foundation_code
#' in {2, 3, 4}) from public charities; for other subsections, returns the
#' generic `501(c)(N)` label or one of the special-subsection labels.
#'
#' Values are the exact strings the dashboard `options_nogeo.R` expects.
#'
#' @param subsection_code character or integer vector.
#' @param foundation_code character vector (matched against the codes listed
#'   in `.PRIVATE_FOUNDATION_FOUNDATION_CODES`).
#' @return character vector of organization-type labels.
#' @export
derive_organization_type <- function(subsection_code, foundation_code) {
  sc <- suppressWarnings(as.integer(subsection_code))
  is_pf <- foundation_code %in% .PRIVATE_FOUNDATION_FOUNDATION_CODES
  dplyr::case_when(
    is.na(sc)                ~ "501(c)(3) Public Charities",
    sc == 3 &  is_pf         ~ "501(c)(3) Private Foundations",
    sc == 3 & !is_pf         ~ "501(c)(3) Public Charities",
    sc >= 1 & sc < 30        ~ sprintf("501(c)(%d)", sc),
    sc == 40                 ~ "501(c)(d)",
    sc == 50                 ~ "501(c)(e)",
    sc == 60                 ~ "501(c)(f)",
    sc == 70                 ~ "501(c)(k)",
    .default = "501(c)(3) Public Charities"
  )
}
