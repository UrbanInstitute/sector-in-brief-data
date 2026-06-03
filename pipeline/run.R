# Top-level pipeline entrypoint.
# Usage:
#   Rscript pipeline/run.R                  # full run, publish to sandbox
#   Rscript pipeline/run.R --dry-run        # stage locally, no S3 upload
#   Rscript pipeline/run.R --prod           # publish to prod prefix (gated)
#
# Reads config.yml from the cwd, materializes inputs from S3 into a local
# cache, runs the panels, and publishes the vintage.

suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tibble); library(nccsdata)
})

# Source package functions (no devtools dependency at runtime).
for (f in list.files("R", "\\.R$", full.names = TRUE)) source(f)

args     <- commandArgs(trailingOnly = TRUE)
dry_run  <- "--dry-run" %in% args
to_prod  <- "--prod"    %in% args

cfg <- read_config()
message("Vintage: ", cfg$vintage,
        if (to_prod) "  (PROD)" else "  (SANDBOX)")

cache <- cfg$local$cache_dir
dir.create(cache, recursive = TRUE, showWarnings = FALSE)

# ---- 1. BMF -----------------------------------------------------------------
bmf_local <- file.path(cache, basename(cfg$inputs$bmf))
if (!file.exists(bmf_local)) {
  message("Downloading BMF ...")
  system2("aws", c("s3", "cp", cfg$inputs$bmf, bmf_local,
                   "--profile", cfg$aws$profile), stdout = FALSE)
}
bmf <- read_bmf(bmf_local)
message("BMF rows: ", format(nrow(bmf), big.mark = ","))

# ---- 2. CORE (for static Size) ---------------------------------------------
nn_range <- cfg$year_ranges$number_nonprofits
years_990 <- seq.int(nn_range[1], nn_range[2])
core_dir  <- file.path(cache, "core")
dir.create(core_dir, recursive = TRUE, showWarnings = FALSE)

core_990_uri_tbl <- core_990_paths(cfg, years_990)
core_pf_uris     <- core_pf_paths(cfg, years_990)

materialize <- function(uri, dest_dir = core_dir) {
  if (is.na(uri)) return(NA_character_)
  local <- file.path(dest_dir, basename(uri))
  if (file.exists(local)) return(local)
  status <- system2("aws", c("s3", "cp", uri, local,
                             "--profile", cfg$aws$profile),
                    stdout = FALSE, stderr = FALSE)
  if (status != 0) return(NA_character_)
  local
}

message("Downloading CORE 990combined (", nrow(core_990_uri_tbl), " years) ...")
core_990_uri_tbl$combined_local <- vapply(core_990_uri_tbl$combined_uri,
                                          materialize, character(1))
message("Downloading CORE 990 (modern, for Pt IX) ...")
core_990_uri_tbl$full_local     <- vapply(core_990_uri_tbl$full_uri,
                                          materialize, character(1))
message("Downloading CORE 990pf ...")
local_pf <- vapply(core_pf_uris, materialize, character(1))

missing_990 <- core_990_uri_tbl$year[is.na(core_990_uri_tbl$combined_local)]
missing_pf  <- names(local_pf)[is.na(local_pf)]
if (length(missing_990) > 0)
  message("  CORE 990combined missing for: ", paste(missing_990, collapse = ", "))
if (length(missing_pf) > 0)
  message("  CORE 990pf missing for: ",       paste(missing_pf, collapse = ", "))

core_990_uri_tbl <- core_990_uri_tbl[!is.na(core_990_uri_tbl$combined_local), , drop = FALSE]
local_pf <- local_pf[!is.na(local_pf)]

core_990 <- dplyr::bind_rows(lapply(seq_len(nrow(core_990_uri_tbl)), function(i) {
  row <- core_990_uri_tbl[i, ]
  full_local <- if (!is.na(row$full_local)) row$full_local else NULL
  read_core_990_year(row$year, row$combined_local, full_local)
}))
core_pf_raw <- dplyr::bind_rows(lapply(local_pf, read_core_990pf_raw))
core_pf     <- core_pf_raw[, intersect(names(core_pf_raw),
                                       c("ein","tax_year","source_form",
                                         "total_revenue","total_expenses",
                                         "total_assets","total_contributions",
                                         "total_benefits"))]
message("CORE 990 rows: ", format(nrow(core_990), big.mark = ","),
        "  |  CORE PF rows: ", format(nrow(core_pf), big.mark = ","))

# ---- 3. Org metadata --------------------------------------------------------
org_metadata <- build_org_metadata(bmf, core_990 = core_990, core_990pf = core_pf)

# ---- 4. Panels --------------------------------------------------------------
panels <- list()
panels$number_nonprofits <- build_number_nonprofits(org_metadata, years_990)
message("number_nonprofits rows: ", format(nrow(panels$number_nonprofits), big.mark = ","))

fin_range  <- cfg$year_ranges$finances
years_fin  <- seq.int(fin_range[1], fin_range[2])
panels$finances <- build_finances(core_990, core_pf, org_metadata, years_fin)
message("finances rows: ", format(nrow(panels$finances), big.mark = ","))

pfg_range  <- cfg$year_ranges$pf_grants
years_pfg  <- seq.int(pfg_range[1], pfg_range[2])
panels$pf_grants <- build_pf_grants(core_pf_raw, org_metadata, years_pfg)
message("pf_grants rows: ", format(nrow(panels$pf_grants), big.mark = ","))

# ---- 4b. efile panels (gov_grants, pf_pri) ---------------------------------
# Two filing-grain metric tables from the efile Phase 0 slice (phase0/latest).
efile_dir <- file.path(cache, "efile")
dir.create(efile_dir, recursive = TRUE, showWarnings = FALSE)

gg_local  <- materialize(cfg$inputs$efile$gov_grants, efile_dir)
pri_local <- materialize(cfg$inputs$efile$pf_pri,     efile_dir)

gg_range  <- cfg$year_ranges$gov_grants
years_gg  <- seq.int(gg_range[1], gg_range[2])
if (!is.na(gg_local)) {
  gov_grants_raw <- read_gov_grants_raw(gg_local)
  panels$government_grants <- build_gov_grants(gov_grants_raw, org_metadata, years_gg)
  message("government_grants rows: ",
          format(nrow(panels$government_grants), big.mark = ","))
} else {
  message("  efile government_grants missing — skipping gov_grants panel")
}

pri_range <- cfg$year_ranges$pf_pri
years_pri <- seq.int(pri_range[1], pri_range[2])
if (!is.na(pri_local)) {
  pf_pri_raw <- read_pf_pri_raw(pri_local)
  panels$program_related_investments <-
    build_pf_pri(pf_pri_raw, org_metadata, years_pri)
  message("program_related_investments rows: ",
          format(nrow(panels$program_related_investments), big.mark = ","))
} else {
  message("  efile program_related_investments missing — skipping pf_pri panel")
}

# ---- 4c. DAF ----------------------------------------------------------------
daf_dir <- file.path(cache, "daf")
dir.create(daf_dir, recursive = TRUE, showWarnings = FALSE)
daf_url_tbl <- daf_paths(cfg)

materialize_url <- function(url) {
  local <- file.path(daf_dir, basename(url))
  if (file.exists(local)) return(local)
  status <- utils::download.file(url, local, mode = "wb", quiet = TRUE)
  if (status != 0) return(NA_character_)
  local
}

message("Downloading DAF orgs (", nrow(daf_url_tbl), " years) ...")
daf_url_tbl$orgs_local <- vapply(daf_url_tbl$orgs_url, materialize_url, character(1))
daf_url_tbl <- daf_url_tbl[!is.na(daf_url_tbl$orgs_local), , drop = FALSE]
daf <- read_daf(tibble::tibble(tax_year = daf_url_tbl$tax_year,
                               orgs_url = daf_url_tbl$orgs_local))
message("DAF rows: ", format(nrow(daf), big.mark = ","))

daf_range <- cfg$year_ranges$daf
years_daf <- seq.int(daf_range[1], daf_range[2])
panels$daf <- build_daf(daf, org_metadata, years_daf)
message("daf rows: ", format(nrow(panels$daf), big.mark = ","))

# ---- 4d. Static dimension files --------------------------------------------
panels$nested_geographies <- list(df = build_nested_geographies(bmf),
                                  format = "csv")
message("nested_geographies rows: ",
        format(nrow(panels$nested_geographies$df), big.mark = ","))

# ---- 4e. Data dictionary ----------------------------------------------------
# Build from the actual schemas + curated descriptions. Lives in the same
# vintage prefix so it's pinned to the data it documents.
dd_panels <- list()
for (nm in names(panels)) {
  entry <- panels[[nm]]
  fname <- if (inherits(entry, "data.frame"))
    paste0(nm, ".parquet")
  else
    paste0(nm, ".", entry$format %||% "parquet")
  dd_panels[[fname]] <- if (inherits(entry, "data.frame")) entry else entry$df
}
panels$data_dictionary <- build_data_dictionary(dd_panels)
message("data_dictionary rows: ",
        format(nrow(panels$data_dictionary), big.mark = ","))

# ---- 5. Publish -------------------------------------------------------------
publish_vintage(panels, cfg, sandbox = !to_prod, dry_run = dry_run)
