#' Publish a vintage to S3
#'
#' Writes every (file, df) in `outputs` as parquet to a local staging
#' directory, builds + writes `_manifest.json`, then uploads the whole
#' directory to `s3://{bucket}/{prefix}/v{vintage}/` via `aws s3 cp`.
#'
#' @param outputs named list: file basename (no extension) → tibble (written
#'   as parquet) OR `list(df = <tibble>, format = "csv"|"parquet")` for
#'   explicit format control. CSVs are written with `arrow::write_csv_arrow`.
#' @param config a config list from [read_config].
#' @param sandbox if TRUE, publish to `output$sandbox_prefix` instead of
#'   the production prefix.
#' @param dry_run if TRUE, stages locally and prints what would be uploaded
#'   but does not call `aws s3 cp`.
#' @return invisible list with `stage_dir`, `s3_prefix`, and `manifest`.
#' @export
publish_vintage <- function(outputs, config, sandbox = TRUE, dry_run = FALSE) {
  stopifnot(is.list(outputs), length(outputs) > 0)

  stage <- file.path(config$local$cache_dir %||% ".cache",
                     paste0("v", config$vintage, if (sandbox) "-sandbox" else ""))
  dir.create(stage, recursive = TRUE, showWarnings = FALSE)

  # Write outputs to staging. Each entry is either a tibble (→ parquet) or
  # list(df, format).
  outputs_meta <- list()
  for (name in names(outputs)) {
    entry <- outputs[[name]]
    if (inherits(entry, "data.frame")) {
      df <- entry; fmt <- "parquet"
    } else {
      df  <- entry$df
      fmt <- entry$format %||% "parquet"
    }
    out_path <- file.path(stage, paste0(name, ".", fmt))
    switch(fmt,
      parquet = arrow::write_parquet(df, out_path, compression = "snappy"),
      csv     = arrow::write_csv_arrow(df, out_path),
      stop("Unknown output format: ", fmt, call. = FALSE)
    )
    outputs_meta[[paste0(name, ".", fmt)]] <- list(path = out_path, df = df)
  }

  # Manifest.
  inputs <- list(
    bmf         = config$inputs$bmf,
    core_legacy = config$inputs$core_legacy,
    core_modern = config$inputs$core_modern,
    core_pf     = config$inputs$core_pf
  )
  manifest <- build_manifest(config$vintage, outputs_meta, inputs,
                             aws_profile = config$aws$profile)
  write_manifest(manifest, stage)

  # Upload (or dry-run).
  prefix <- vintage_prefix(config, sandbox = sandbox)
  latest_prefix <- if (!sandbox && isTRUE(config$output$also_publish_latest))
    sprintf("s3://%s/%s/latest/", config$output$bucket, config$output$prefix)
  else NULL

  if (dry_run) {
    message("DRY-RUN: would upload ", stage, " -> ", prefix)
    if (!is.null(latest_prefix))
      message("DRY-RUN: would mirror ", prefix, " -> ", latest_prefix)
    return(invisible(list(stage_dir = stage, s3_prefix = prefix,
                          latest_prefix = latest_prefix,
                          manifest = manifest)))
  }
  args <- c("s3", "cp", stage, prefix, "--recursive",
            "--profile", config$aws$profile)
  message("Uploading ", stage, " -> ", prefix)
  status <- system2("aws", args)
  if (status != 0) stop("aws s3 cp failed with exit code ", status,
                        call. = FALSE)

  if (!is.null(latest_prefix)) {
    message("Mirroring ", prefix, " -> ", latest_prefix)
    mirror_args <- c("s3", "cp", prefix, latest_prefix, "--recursive",
                     "--profile", config$aws$profile)
    status <- system2("aws", mirror_args)
    if (status != 0) stop("aws s3 cp (latest mirror) failed with exit code ",
                          status, call. = FALSE)
  }

  invisible(list(stage_dir = stage, s3_prefix = prefix,
                 latest_prefix = latest_prefix, manifest = manifest))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
