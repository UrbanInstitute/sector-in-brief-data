#' Publish a vintage to S3
#'
#' Writes every (file, df) in `outputs` as parquet to a local staging
#' directory, builds + writes `_manifest.json`, then uploads the whole
#' directory to `s3://{bucket}/{prefix}/v{vintage}/` via `aws s3 cp`.
#'
#' @param outputs named list: file basename (no extension) → tibble.
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

  # Write parquets to staging.
  outputs_meta <- list()
  for (name in names(outputs)) {
    df  <- outputs[[name]]
    pq  <- file.path(stage, paste0(name, ".parquet"))
    arrow::write_parquet(df, pq, compression = "snappy")
    outputs_meta[[paste0(name, ".parquet")]] <- list(path = pq, df = df)
  }

  # Manifest.
  inputs <- list(
    bmf             = config$inputs$bmf,
    core_harmonized = config$inputs$core_harmonized
  )
  manifest <- build_manifest(config$vintage, outputs_meta, inputs,
                             aws_profile = config$aws$profile)
  write_manifest(manifest, stage)

  # Upload (or dry-run).
  prefix <- vintage_prefix(config, sandbox = sandbox)
  if (dry_run) {
    message("DRY-RUN: would upload ", stage, " → ", prefix)
    return(invisible(list(stage_dir = stage, s3_prefix = prefix,
                          manifest = manifest)))
  }
  args <- c("s3", "cp", stage, prefix, "--recursive",
            "--profile", config$aws$profile)
  message("Uploading ", stage, " → ", prefix)
  status <- system2("aws", args)
  if (status != 0) stop("aws s3 cp failed with exit code ", status,
                        call. = FALSE)

  invisible(list(stage_dir = stage, s3_prefix = prefix, manifest = manifest))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
