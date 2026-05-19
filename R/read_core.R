# Canonical column emitted by both read_core_990combined and read_core_990pf.
# Add new metrics here if you also map them in the per-form helpers below.
.CORE_CANONICAL <- c(
  "ein", "tax_year", "source_form",
  "total_revenue", "total_expenses", "total_assets",
  "total_contributions", "total_benefits"
)

# Optional NA filler — used so downstream `bind_rows` doesn't fail when a
# given year's parquet is missing a column (e.g. total_functional_expenses
# pre-upstream-patch in processed_merged 2012-2024).
.fill_missing <- function(df, cols) {
  for (col in cols) {
    if (!col %in% names(df)) df[[col]] <- NA_real_
  }
  df
}

# Form 990 Part IX personnel-cost lines (sum yields "Total Benefits").
# Pre-2008 forms only had lines 5 and 7 (`.BENEFIT_PRE2008_COMPONENTS`);
# the 2008 redesign added lines 6, 8, 9 (`.BENEFIT_POST2008_COMPONENTS`).
.BENEFIT_PRE2008_COMPONENTS  <- c("compensation_current_officers",        # Pt IX-5
                                  "other_salaries_wages")                 # Pt IX-7
.BENEFIT_POST2008_COMPONENTS <- c("compensation_disqualified_persons",    # Pt IX-6
                                  "pension_plan_contributions",           # Pt IX-8
                                  "other_employee_benefits")              # Pt IX-9
.BENEFIT_ALL_COMPONENTS      <- c(.BENEFIT_PRE2008_COMPONENTS,
                                  .BENEFIT_POST2008_COMPONENTS)

#' Read merged CORE 990/990EZ for a year (canonical schema)
#'
#' Reads `processed_merged/core/{year}/990combined/core_{year}_990combined.parquet`
#' (or a local fixture) and returns a tibble in the pipeline's canonical
#' schema. Missing source columns (e.g. `total_functional_expenses` for years
#' where the upstream merge dropped it) are filled with NA so the row maths
#' degrade gracefully.
#'
#' Canonical mapping:
#' \itemize{
#'   \item `total_revenue` ← `total_revenue`
#'   \item `total_expenses` ← `total_functional_expenses` (NA where absent)
#'   \item `total_assets` ← `total_assets_eoy`
#'   \item `total_contributions` ← `total_contributions`
#'   \item `total_benefits` ← rowSum of Pt IX lines 5+6+7+8+9. Emits NA when
#'         any of lines 6/8/9 are NA on the row (i.e. pre-2012 rows whose
#'         source extract didn't carry those columns, and 990EZ filers who
#'         don't report at that granularity). See
#'         [[project-total-benefits-pre-2012]] for rationale — we deliberately
#'         do not emit a 2-line proxy because it would silently undercount
#'         vs. 2012+ values.
#' }
#'
#' @param path path to the 990combined parquet (S3 URI or local).
#' @return tibble with `.CORE_CANONICAL` columns.
#' @export
read_core_990combined <- function(path) {
  df <- arrow::read_parquet(path)
  df <- .fill_missing(df, c("total_functional_expenses", "total_revenue",
                            "total_assets_eoy", "total_contributions",
                            .BENEFIT_ALL_COMPONENTS))

  # Total Benefits = rowSums(lines 5+6+7+8+9), but emit NA when any of the
  # post-2008 lines (6/8/9) is missing — those rows can't yield a value
  # comparable to fully-reported 2012+ rows.
  benefit_mat <- as.matrix(as.data.frame(df)[, .BENEFIT_ALL_COMPONENTS])
  total_benefits <- rowSums(benefit_mat, na.rm = TRUE)
  post2008_mat <- as.matrix(as.data.frame(df)[, .BENEFIT_POST2008_COMPONENTS])
  any_post2008_missing <- apply(post2008_mat, 1, function(r) any(is.na(r)))
  total_benefits[any_post2008_missing] <- NA_real_

  tibble::tibble(
    ein                 = nccsdata::nccs_normalize_ein(df$ein),
    tax_year            = as.integer(df$tax_year),
    source_form         = "990combined",
    total_revenue       = as.numeric(df$total_revenue),
    total_expenses      = as.numeric(df$total_functional_expenses),
    total_assets        = as.numeric(df$total_assets_eoy),
    total_contributions = as.numeric(df$total_contributions),
    total_benefits      = total_benefits
  )
}

#' Read CORE 990PF for a year (canonical schema)
#'
#' Reads `processed_merged/core/{year}/990pf/core_{year}_990pf.parquet`.
#'
#' Canonical mapping (PF-specific):
#' \itemize{
#'   \item `total_revenue` ← `total_revenue_col_a`
#'   \item `total_expenses` ← `total_expenses_col_a`
#'   \item `total_assets` ← `total_assets_eoy`
#'   \item `total_contributions` ← `contributions_received`
#'         (note: `contributions_paid` is the grants-out metric used by the
#'         `pf_grants` panel — kept as an extra column in [read_core_990pf_raw])
#'   \item `total_benefits` ← NA (not applicable to PFs)
#' }
#'
#' @param path path to the 990pf parquet (S3 URI or local).
#' @return tibble with `.CORE_CANONICAL` columns.
#' @export
read_core_990pf <- function(path) {
  df <- arrow::read_parquet(path)
  df <- .fill_missing(df, c("total_revenue_col_a", "total_expenses_col_a",
                            "total_assets_eoy", "contributions_received"))

  tibble::tibble(
    ein                 = nccsdata::nccs_normalize_ein(df$ein),
    tax_year            = as.integer(df$tax_year),
    source_form         = "990pf",
    total_revenue       = as.numeric(df$total_revenue_col_a),
    total_expenses      = as.numeric(df$total_expenses_col_a),
    total_assets        = as.numeric(df$total_assets_eoy),
    total_contributions = as.numeric(df$contributions_received),
    total_benefits      = NA_real_
  )
}

#' Read 990PF with PF-specific metric columns preserved
#'
#' Same source file as [read_core_990pf], but keeps PF-specific metrics that
#' the pf_grants and pf_pri panels need (`contributions_paid`,
#' `contributions_received`). Used by the PF-panel builders.
#'
#' @param path path to the 990pf parquet.
#' @return tibble with canonical columns plus `contributions_paid`,
#'   `contributions_received` (raw PF metrics).
#' @export
read_core_990pf_raw <- function(path) {
  df <- arrow::read_parquet(path)
  df <- .fill_missing(df, c("contributions_paid", "contributions_received"))

  out <- read_core_990pf(path)
  out$contributions_paid     <- as.numeric(df$contributions_paid)
  out$contributions_received <- as.numeric(df$contributions_received)
  out
}

#' Build S3 paths for a CORE form across a year range
#'
#' @param config a config list (from [read_config]).
#' @param form one of `"990combined"`, `"990pf"`.
#' @param years integer vector of tax years.
#' @return named character vector of S3 URIs, names = years.
#' @export
core_paths <- function(config, form, years) {
  base <- sub("/+$", "", config$inputs$core_harmonized)
  out <- sprintf("%s/%d/%s/core_%d_%s.parquet", base, years, form, years, form)
  stats::setNames(out, as.character(years))
}

#' Read multiple years of CORE 990combined and stack
#'
#' @param paths character vector of parquet paths (S3 or local).
#' @return tibble in `.CORE_CANONICAL` schema, one row per (ein, tax_year).
#' @export
read_core <- function(paths) {
  dplyr::bind_rows(lapply(paths, read_core_990combined))
}
