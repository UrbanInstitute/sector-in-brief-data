# Files that the data dictionary covers. Includes the dictionary itself for
# completeness (self-documenting).
.DD_FILES_WITH_SHARED_DIMS <- c("number_nonprofits.parquet",
                                "finances.parquet",
                                "pf_grants.parquet",
                                "daf.parquet")

.DD_COLUMNS <- c("file", "column", "datatype",
                 "description", "form_source",
                 "coverage", "coverage_notes")

.arrow_type_to_r <- function(x) {
  if (inherits(x, "Field"))   x <- x$type
  s <- tryCatch(x$ToString(), error = function(e) class(x)[1])
  switch(s,
    "int32"   = "integer",
    "int64"   = "integer",
    "double"  = "double",
    "string"  = "character",
    "utf8"    = "character",
    s
  )
}

.schema_for <- function(df) {
  tibble::tibble(
    column = names(df),
    datatype = vapply(df, function(x) {
      if (inherits(x, "integer")) "integer"
      else if (inherits(x, "numeric")) "double"
      else if (inherits(x, "character")) "character"
      else if (inherits(x, "logical")) "logical"
      else class(x)[1]
    }, character(1))
  )
}

#' Build the data_dictionary.parquet table
#'
#' Joins curated descriptions (`.DD_SHARED_DIMS`, `.DD_PANEL_COLS`) against
#' the actual schemas of `panels`. Fails loudly if a panel column is missing
#' a description or if a curated entry references a column that no longer
#' exists — the dictionary cannot drift from the code.
#'
#' @param panels named list of (file_basename → tibble). File basenames must
#'   include the extension (e.g. `finances.parquet`, `nested_geographies.csv`).
#' @return tibble with `.DD_COLUMNS`.
#' @export
build_data_dictionary <- function(panels) {
  stopifnot(is.list(panels), length(panels) > 0)

  # Expand shared dims for every panel that has them.
  dims_rows <- do.call(dplyr::bind_rows,
    lapply(.DD_FILES_WITH_SHARED_DIMS, function(f) {
      out <- .DD_SHARED_DIMS
      out$file <- f
      out
    }))

  curated <- dplyr::bind_rows(
    dims_rows[, c("file", "column", "description",
                  "form_source", "coverage_notes")],
    .DD_PANEL_COLS[, c("file", "column", "description",
                       "form_source", "coverage_notes")]
  )
  # Only consider curated entries for files that are actually being published
  # this run — a vintage may skip a panel without failing the drift check.
  curated <- curated[curated$file %in% names(panels), , drop = FALSE]

  # Pull actual schemas from the panels — source of truth for which columns
  # actually exist and what type they have.
  actual <- do.call(dplyr::bind_rows,
    lapply(names(panels), function(f) {
      sch <- .schema_for(panels[[f]])
      sch$file <- f
      sch
    }))

  # Drift checks.
  missing_desc <- dplyr::anti_join(actual, curated, by = c("file","column"))
  if (nrow(missing_desc) > 0) {
    stop("Output columns missing from data_dictionary_curation.R:\n  ",
         paste0(missing_desc$file, "$", missing_desc$column, collapse = "\n  "),
         call. = FALSE)
  }
  stale_curated <- dplyr::anti_join(curated, actual, by = c("file","column"))
  if (nrow(stale_curated) > 0) {
    stop("data_dictionary_curation.R has entries for columns that no longer ",
         "exist in any panel:\n  ",
         paste0(stale_curated$file, "$", stale_curated$column, collapse = "\n  "),
         call. = FALSE)
  }

  # Per-file year coverage string for the Year column / temporal panels.
  coverage <- vapply(names(panels), function(f) {
    df <- panels[[f]]
    if ("Year" %in% names(df) && nrow(df) > 0) {
      yr <- as.integer(df$Year)
      yr <- yr[!is.na(yr)]
      if (length(yr)) sprintf("%d–%d", min(yr), max(yr)) else "static"
    } else "static"
  }, character(1))
  coverage_lookup <- tibble::tibble(file = names(panels), coverage = coverage)

  out <- dplyr::inner_join(actual, curated, by = c("file", "column")) |>
    dplyr::left_join(coverage_lookup, by = "file") |>
    dplyr::mutate(coverage_notes = dplyr::coalesce(.data$coverage_notes, "")) |>
    dplyr::select(dplyr::all_of(.DD_COLUMNS))

  out
}
