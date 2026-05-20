# Canonical schema emitted by every read_core_* helper. Panel builders
# consume these names.
.CORE_CANONICAL <- c(
  "ein", "tax_year", "source_form",
  "total_revenue", "total_expenses", "total_assets",
  "total_contributions", "total_benefits"
)

# Form 990 Part IX personnel-cost lines that contribute to Total Benefits.
# Definition is locked to lines 5+6+7+8+9 — see [[project-total-benefits-definition]].
# Lines 6/8/9 only exist post-2008 redesign; legacy era ships a partial 2-line
# proxy (lines 5+7) per [[project-total-benefits-pre-2012]].
.BENEFIT_PRE2008_COMPONENTS  <- c("compensation_current_officers",     # Pt IX-5
                                  "other_salaries_wages")              # Pt IX-7
.BENEFIT_POST2008_COMPONENTS <- c("compensation_disqualified_persons", # Pt IX-6
                                  "pension_plan_contributions",        # Pt IX-8
                                  "other_employee_benefits")           # Pt IX-9
.BENEFIT_ALL_COMPONENTS      <- c(.BENEFIT_PRE2008_COMPONENTS,
                                  .BENEFIT_POST2008_COMPONENTS)

.fill_missing <- function(df, cols) {
  for (col in cols) if (!col %in% names(df)) df[[col]] <- NA_real_
  df
}

# NA-preserving row sum: if every component is NA on the row, emit NA;
# otherwise sum what's there. Used for partial-coverage components like
# Pt IX 5+7 in legacy years and the post-2008 columns when some are blank.
.rowsum_na_preserving <- function(df, cols) {
  m <- as.matrix(as.data.frame(df)[, cols, drop = FALSE])
  any_present <- apply(m, 1, function(r) any(!is.na(r)))
  out <- rowSums(m, na.rm = TRUE)
  out[!any_present] <- NA_real_
  out
}

#' Read modern-era 990 (2012–2024) with Pt IX detail
#'
#' Reads `processed/core/{YYYY}/990combined/` as the base (covers both 990 and
#' 990EZ filers — revenue, expenses, assets, contributions) and left-joins
#' `processed/core/{YYYY}/990/` for Pt IX lines 5–9. 990EZ rows get NA Total
#' Benefits because that form doesn't carry those lines (correct by design).
#'
#' If `full_path` is NULL or unreadable, returns the combined data with
#' `total_benefits = NA` for every row (graceful degradation when the full-990
#' file is missing for a year).
#'
#' @param combined_path path to `core_{YYYY}_990combined.parquet`.
#' @param full_path path to `core_{YYYY}_990.parquet`, or NULL.
#' @return tibble in `.CORE_CANONICAL` schema.
#' @export
read_core_990_modern <- function(combined_path, full_path = NULL) {
  base <- arrow::read_parquet(combined_path) |> as.data.frame()
  base <- .fill_missing(base, c("total_revenue", "total_expenses",
                                "total_assets_eoy", "total_contributions"))

  out <- tibble::tibble(
    ein                 = nccsdata::nccs_normalize_ein(base$ein),
    tax_year            = as.integer(base$tax_year),
    source_form         = "990combined",
    total_revenue       = as.numeric(base$total_revenue),
    total_expenses      = as.numeric(base$total_expenses),
    total_assets        = as.numeric(base$total_assets_eoy),
    total_contributions = as.numeric(base$total_contributions),
    total_benefits      = NA_real_
  )

  if (is.null(full_path) || !file.exists(full_path)) return(out)

  full <- arrow::read_parquet(full_path) |> as.data.frame()
  full <- .fill_missing(full, .BENEFIT_ALL_COMPONENTS)
  full$ein      <- nccsdata::nccs_normalize_ein(full$ein)
  full$tax_year <- as.integer(full$tax_year)
  full$total_benefits <- .rowsum_na_preserving(full, .BENEFIT_ALL_COMPONENTS)

  benefits_lookup <- full[, c("ein", "tax_year", "total_benefits"), drop = FALSE]
  benefits_lookup <- benefits_lookup[!duplicated(benefits_lookup[, c("ein","tax_year")]), ]

  out$total_benefits <- NULL
  out <- dplyr::left_join(out, benefits_lookup, by = c("ein", "tax_year"))
  out[, .CORE_CANONICAL]
}

#' Read legacy-era 990combined (1989–2011)
#'
#' `processed_legacy/core/{YYYY}/990combined/` covers both 990 and 990EZ
#' filers and carries Pt IX lines 5+7 inline. Total Benefits is computed as
#' the partial 2-line proxy (sum of 5+7, NA-preserving). Lines 6/8/9 are
#' unrecoverable for this era — see [[project-total-benefits-pre-2012]].
#'
#' @param combined_path path to legacy `core_{YYYY}_990combined.parquet`.
#' @return tibble in `.CORE_CANONICAL` schema.
#' @export
read_core_990_legacy <- function(combined_path) {
  df <- arrow::read_parquet(combined_path) |> as.data.frame()
  df <- .fill_missing(df, c("total_revenue", "total_expenses",
                            "total_assets_eoy", "total_contributions",
                            .BENEFIT_PRE2008_COMPONENTS))

  total_benefits <- .rowsum_na_preserving(df, .BENEFIT_PRE2008_COMPONENTS)

  tibble::tibble(
    ein                 = nccsdata::nccs_normalize_ein(df$ein),
    tax_year            = as.integer(df$tax_year),
    source_form         = "990combined_legacy",
    total_revenue       = as.numeric(df$total_revenue),
    total_expenses      = as.numeric(df$total_expenses),
    total_assets        = as.numeric(df$total_assets_eoy),
    total_contributions = as.numeric(df$total_contributions),
    total_benefits      = total_benefits
  )
}

#' Read CORE 990-PF for a year (canonical schema)
#'
#' Reads `processed_merged/core/{year}/990pf/core_{year}_990pf.parquet`. Only
#' one PF form exists, so no intersection issue — `processed_merged` is fine.
#'
#' @param path path to the 990pf parquet (S3 URI or local).
#' @return tibble with `.CORE_CANONICAL` columns. `total_benefits` is NA (PFs
#'   don't report Pt IX personnel detail in the same shape).
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

#' Read 990-PF with PF-specific metric columns preserved
#'
#' Same source as [read_core_990pf] but keeps `contributions_paid` (grants
#' out, used by the pf_grants panel) and `contributions_received`.
#'
#' @param path path to the 990pf parquet.
#' @return tibble with canonical columns plus `contributions_paid`,
#'   `contributions_received`.
#' @export
read_core_990pf_raw <- function(path) {
  df <- arrow::read_parquet(path)
  df <- .fill_missing(df, c("contributions_paid", "contributions_received"))
  out <- read_core_990pf(path)
  out$contributions_paid     <- as.numeric(df$contributions_paid)
  out$contributions_received <- as.numeric(df$contributions_received)
  out
}

#' Build the per-year CORE 990 source paths for a given era
#'
#' @param config a config list (from [read_config]).
#' @param years integer vector of tax years.
#' @return a tibble with `year`, `era` ("legacy" or "modern"), and the source
#'   URIs needed per era: `combined_uri` (always set) plus `full_uri` (set for
#'   modern years only).
#' @export
core_990_paths <- function(config, years) {
  years <- as.integer(years)
  legacy_base <- sub("/+$", "", config$inputs$core_legacy)
  modern_base <- sub("/+$", "", config$inputs$core_modern)

  era <- ifelse(years < 2012, "legacy", "modern")
  combined_uri <- ifelse(
    era == "legacy",
    sprintf("%s/%d/990combined/core_%d_990combined.parquet", legacy_base, years, years),
    sprintf("%s/%d/990combined/core_%d_990combined.parquet", modern_base, years, years)
  )
  full_uri <- ifelse(
    era == "modern",
    sprintf("%s/%d/990/core_%d_990.parquet", modern_base, years, years),
    NA_character_
  )
  tibble::tibble(year = years, era = era,
                 combined_uri = combined_uri, full_uri = full_uri)
}

#' Build per-year CORE 990-PF source paths
#'
#' @param config a config list.
#' @param years integer vector.
#' @return named character vector of S3 URIs (names = years).
#' @export
core_pf_paths <- function(config, years) {
  base <- sub("/+$", "", config$inputs$core_pf)
  uris <- sprintf("%s/%d/990pf/core_%d_990pf.parquet", base, years, years)
  stats::setNames(uris, as.character(years))
}

#' Read a single year of CORE 990 in canonical schema, era-aware
#'
#' Dispatches to [read_core_990_legacy] or [read_core_990_modern] based on
#' year. For modern years the `full_local` arg is optional — if NULL or
#' missing, Total Benefits is NA for that year.
#'
#' @param year tax year.
#' @param combined_local local path to the 990combined parquet.
#' @param full_local local path to the modern 990 parquet, or NULL.
#' @return tibble in `.CORE_CANONICAL` schema.
#' @export
read_core_990_year <- function(year, combined_local, full_local = NULL) {
  if (as.integer(year) < 2012L) {
    read_core_990_legacy(combined_local)
  } else {
    read_core_990_modern(combined_local, full_local)
  }
}
