#' Read pipeline config
#'
#' Loads `config.yml` from the package root (or an explicit path) and returns
#' a named list. All pipeline I/O paths flow through here — no R file in this
#' package should hardcode an S3 key, HTTP URL, or local directory.
#'
#' @param path Path to a YAML config file. Defaults to `config.yml` in the
#'   current working directory.
#' @return A list with the parsed config.
#' @export
read_config <- function(path = "config.yml") {
  if (!file.exists(path)) {
    stop("Config file not found at: ", path, call. = FALSE)
  }
  yaml::read_yaml(path)
}

#' Resolve a path relative to the repo root
#'
#' Used so panel builders can reference fixtures and lookups without
#' hardcoding absolute paths.
#'
#' @param ... Path components joined with `file.path`.
#' @param root Repo root. Defaults to the current working directory.
#' @return Absolute path.
#' @export
resolve_path <- function(..., root = getwd()) {
  normalizePath(file.path(root, ...), mustWork = FALSE)
}

#' Build the publish prefix for a vintage
#'
#' @param config A config list (from `read_config`).
#' @param sandbox If TRUE, use the sandbox prefix.
#' @return S3 URI of the vintage prefix (no trailing slash).
#' @export
vintage_prefix <- function(config, sandbox = FALSE) {
  prefix <- if (sandbox) config$output$sandbox_prefix else config$output$prefix
  sprintf("s3://%s/%s/v%s", config$output$bucket, prefix, config$vintage)
}
