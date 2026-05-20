#' Build the nested_geographies dimension table
#'
#' One row per distinct (Census State, Census County, Metro/Micro Area,
#' Census Region) tuple observed in the BMF. The dashboard uses this to
#' drive cascading State → County → CBSA dropdowns.
#'
#' Rows where every geo column is NA are dropped (uninformative); rows where
#' some-but-not-all are NA are kept (e.g. rural counties with NA CBSA).
#'
#' @param bmf tibble from [read_bmf].
#' @return tibble with 4 columns, distinct.
#' @export
build_nested_geographies <- function(bmf) {
  cols <- c("Census State", "Census County", "Metro/Micro Area", "Census Region")
  stopifnot(all(cols %in% names(bmf)))

  geo <- bmf[, cols, drop = FALSE]
  geo <- dplyr::distinct(geo)
  all_na <- apply(geo, 1, function(r) all(is.na(r)))
  geo <- geo[!all_na, , drop = FALSE]
  geo <- dplyr::arrange(geo,
                        .data$`Census Region`,
                        .data$`Census State`,
                        .data$`Census County`,
                        .data$`Metro/Micro Area`)
  tibble::as_tibble(geo)
}
