.DAF_ORG_COLS <- c("EIN2", "TAX_YEAR",
                   "SD_01_TOT_NUM_EOY_DAF",       "SD_01_TOT_NUM_EOY_OTH",
                   "SD_01_AGGREGATE_CONTR_DAF",   "SD_01_AGGREGATE_CONTR_OTH",
                   "SD_01_AGGREGATE_GRANT_DAF",   "SD_01_AGGREGATE_GRANT_OTH",
                   "SD_01_AGGREGATE_VALUE_EOY_DAF","SD_01_AGGREGATE_VALUE_EOY_OTH")

# The DAF e-file groups counts/dollars into two sub-totals per metric — DAFs
# proper plus "other similar funds" — and the dashboard reports the combined
# value. Helper: NA-preserving sum-of-two so we don't fabricate 0s when both
# components are NA.
.daf_sum2 <- function(a, b) {
  ifelse(is.na(a) & is.na(b), NA_real_,
         ifelse(is.na(a), b,
                ifelse(is.na(b), a, a + b)))
}

#' Read the DAF "orgs" e-file CSV (one tax year)
#'
#' Source: `SD-P01-T00-ORGS-DONOR-ADVISED-FUNDS-OTH-{YYYY}.CSV`. The schedule
#' reports DAFs and "other similar funds" as parallel column families
#' (`*_DAF` / `*_OTH`); we collapse each metric to a single canonical column
#' by summing the two with NA-preservation.
#'
#' @param path local path or HTTP(S) URL to the orgs CSV.
#' @param tax_year integer; rows where the source `TAX_YEAR` does not match
#'   are dropped (the raw files contain filings reported in year YYYY whose
#'   `TAX_YEAR` is most often YYYY but can spill).
#' @return tibble with `ein`, `tax_year`, `num_dafs`, `contributions`,
#'   `grants`, `value`.
#' @export
read_daf_orgs <- function(path, tax_year) {
  tax_year <- as.integer(tax_year)
  df <- arrow::read_csv_arrow(path) |> as.data.frame()
  for (col in setdiff(.DAF_ORG_COLS, "EIN2")) {
    if (!col %in% names(df)) df[[col]] <- NA_real_
  }
  df <- df[, .DAF_ORG_COLS, drop = FALSE]

  num_cols <- setdiff(.DAF_ORG_COLS, c("EIN2", "TAX_YEAR"))
  for (col in num_cols) df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
  df$TAX_YEAR <- suppressWarnings(as.integer(df$TAX_YEAR))
  df <- df[!is.na(df$TAX_YEAR) & df$TAX_YEAR == tax_year, , drop = FALSE]

  tibble::tibble(
    ein           = nccsdata::nccs_normalize_ein(df$EIN2),
    tax_year      = df$TAX_YEAR,
    num_dafs      = .daf_sum2(df$SD_01_TOT_NUM_EOY_DAF,        df$SD_01_TOT_NUM_EOY_OTH),
    contributions = .daf_sum2(df$SD_01_AGGREGATE_CONTR_DAF,    df$SD_01_AGGREGATE_CONTR_OTH),
    grants        = .daf_sum2(df$SD_01_AGGREGATE_GRANT_DAF,    df$SD_01_AGGREGATE_GRANT_OTH),
    value         = .daf_sum2(df$SD_01_AGGREGATE_VALUE_EOY_DAF,df$SD_01_AGGREGATE_VALUE_EOY_OTH)
  )
}

#' Build the per-year DAF source URLs from config
#'
#' Returns a tibble with `tax_year` and `orgs_url`, one row per year present in
#' `config$inputs$daf$orgs`. The Schedule D "orgs" extract is the only DAF
#' source consumed (the F9-P10 balance-sheet family was never read and was
#' removed 2026-05-30).
#'
#' @param config list from [read_config].
#' @return tibble with `tax_year`, `orgs_url`.
#' @export
daf_paths <- function(config) {
  orgs  <- config$inputs$daf$orgs
  years <- names(orgs)
  tibble::tibble(
    tax_year = as.integer(years),
    orgs_url = unlist(orgs[years], use.names = FALSE)
  )
}

#' Read multiple years of DAF orgs e-files and stack
#'
#' @param paths tibble with `tax_year` and `orgs_url` (from [daf_paths] or
#'   from a local materialization step).
#' @return stacked tibble in [read_daf_orgs] schema.
#' @export
read_daf <- function(paths) {
  stopifnot(all(c("tax_year", "orgs_url") %in% names(paths)))
  dplyr::bind_rows(lapply(seq_len(nrow(paths)), function(i) {
    read_daf_orgs(paths$orgs_url[i], paths$tax_year[i])
  }))
}
