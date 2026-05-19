#' Compute SHA-256 of a file
#' @keywords internal
sha256_file <- function(path) {
  unname(digest::digest(file = path, algo = "sha256"))
}

#' S3 ETag for an input — used to track input vintage in the manifest
#' @keywords internal
s3_etag <- function(uri, profile = NULL) {
  if (!startsWith(uri, "s3://")) return(NA_character_)
  args <- c("s3api", "head-object",
            "--bucket", sub("^s3://([^/]+)/.*$", "\\1", uri),
            "--key",    sub("^s3://[^/]+/(.+)$",  "\\1", uri),
            "--query",  "ETag", "--output", "text")
  if (!is.null(profile)) args <- c(args, "--profile", profile)
  out <- tryCatch(
    system2("aws", args, stdout = TRUE, stderr = TRUE),
    error = function(e) NA_character_
  )
  gsub('"', "", out[1])
}

#' Resolve current git SHA (short)
#' @keywords internal
git_sha <- function() {
  out <- tryCatch(
    system2("git", c("rev-parse", "--short", "HEAD"), stdout = TRUE, stderr = TRUE),
    error = function(e) NA_character_
  )
  out[1]
}

#' Per-year completeness summary for a panel
#'
#' Returns a named list keyed by year with the row count for that year.
#' Lets the dashboard apply its own incompleteness policy without this
#' repo having to commit to one.
#' @keywords internal
year_row_counts <- function(df, year_col = "Year") {
  if (!year_col %in% names(df)) return(NULL)
  tab <- table(df[[year_col]])
  as.list(stats::setNames(as.integer(tab), names(tab)))
}

#' Build the vintage manifest
#'
#' One JSON blob per published vintage. Captures everything needed to
#' reproduce the build and inspect quality without re-reading inputs.
#'
#' @param vintage character `YYYY.MM`.
#' @param outputs named list: file basename → list(path=local_path, df=tibble).
#' @param inputs named list of S3 URIs (e.g. config$inputs flattened).
#' @param aws_profile profile name for `aws s3api head-object` calls.
#' @return list (the manifest), and as a side effect writes
#'   `_manifest.json` next to the outputs.
#' @export
build_manifest <- function(vintage, outputs, inputs, aws_profile = NULL) {
  files <- lapply(names(outputs), function(name) {
    o <- outputs[[name]]
    list(
      file        = name,
      sha256      = sha256_file(o$path),
      bytes       = file.info(o$path)$size,
      row_count   = nrow(o$df),
      year_counts = year_row_counts(o$df)
    )
  })
  names(files) <- names(outputs)

  input_records <- lapply(inputs, function(uri) {
    list(uri = uri, etag = s3_etag(uri, profile = aws_profile))
  })

  list(
    vintage     = vintage,
    built_at    = format(Sys.time(), "%Y-%m-%dT%H:%M:%S%z"),
    git_sha     = git_sha(),
    files       = files,
    inputs      = input_records
  )
}

#' Write a manifest to JSON alongside the outputs
#' @param manifest list from [build_manifest].
#' @param dir local directory to write `_manifest.json` to.
#' @return invisible path to the written file.
#' @export
write_manifest <- function(manifest, dir) {
  out <- file.path(dir, "_manifest.json")
  jsonlite::write_json(manifest, out, auto_unbox = TRUE, pretty = TRUE,
                       null = "null", na = "null")
  invisible(out)
}
