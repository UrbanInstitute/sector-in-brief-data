# Reader boundary for the efile Phase 0 vertical slice
# (s3://nccsdata/processed/efile/phase0/). Two filing-grain single-metric
# tables, each already filtered to the one form its field applies to:
#   government_grants.parquet              990 only   (Form 990 Pt VIII line 1e)
#   program_related_investments.parquet    990-PF only (Form 990-PF Pt IX-B)
#
# This is the only file in the package that knows the efile source column
# names. Panel builders (panel_gov_grants.R / panel_pf_pri.R) consume the
# canonical names emitted here. See [[efile]] contract and ADR 0017.

#' Read the efile government-grants table (canonical schema)
#'
#' Source: `government_grants.parquet` (990 only). The metric is government
#' grants/contributions **RECEIVED** (Form 990 Part VIII line 1e), NOT
#' Schedule I grants paid out to governments — distinct concept, see the data
#' dictionary entry for the `gov_grants` panel.
#'
#' @param path local path or S3 URI to `government_grants.parquet`.
#' @return tibble with `ein` (canonical `XX-XXXXXXX`), `tax_year` (int),
#'   `government_grants` (double).
#' @export
read_gov_grants_raw <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  for (col in c("ein", "tax_year", "government_grants")) {
    if (!col %in% names(df)) {
      stop("read_gov_grants_raw: expected column '", col,
           "' missing from ", path, call. = FALSE)
    }
  }
  tibble::tibble(
    ein              = nccsdata::nccs_normalize_ein(df$ein),
    tax_year         = suppressWarnings(as.integer(df$tax_year)),
    government_grants = suppressWarnings(as.numeric(df$government_grants))
  )
}

#' Read the efile program-related-investments table (canonical schema)
#'
#' Source: `program_related_investments.parquet` (990-PF only). The metric is
#' the Form 990-PF Part IX-B aggregate total of program-related investments
#' (renumbered Part VIII-B for TY2021+; the version-agnostic upstream XPath
#' resolves regardless — see [[efile]]).
#'
#' @param path local path or S3 URI to `program_related_investments.parquet`.
#' @return tibble with `ein` (canonical `XX-XXXXXXX`), `tax_year` (int),
#'   `program_related_investments_total` (double).
#' @export
read_pf_pri_raw <- function(path) {
  df <- arrow::read_parquet(path) |> as.data.frame()
  for (col in c("ein", "tax_year", "program_related_investments_total")) {
    if (!col %in% names(df)) {
      stop("read_pf_pri_raw: expected column '", col,
           "' missing from ", path, call. = FALSE)
    }
  }
  tibble::tibble(
    ein      = nccsdata::nccs_normalize_ein(df$ein),
    tax_year = suppressWarnings(as.integer(df$tax_year)),
    program_related_investments_total =
      suppressWarnings(as.numeric(df$program_related_investments_total))
  )
}
