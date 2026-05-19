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

core_paths_990 <- core_paths(cfg, "990combined", years_990)
core_paths_pf  <- core_paths(cfg, "990pf",       years_990)

materialize <- function(uri) {
  local <- file.path(core_dir, basename(uri))
  if (file.exists(local)) return(local)
  status <- system2("aws", c("s3", "cp", uri, local,
                             "--profile", cfg$aws$profile),
                    stdout = FALSE, stderr = FALSE)
  if (status != 0) return(NA_character_)
  local
}

message("Downloading CORE 990combined (", length(years_990), " years) ...")
local_990 <- vapply(core_paths_990, materialize, character(1))
message("Downloading CORE 990pf ...")
local_pf  <- vapply(core_paths_pf,  materialize, character(1))

missing_990 <- names(local_990)[is.na(local_990)]
missing_pf  <- names(local_pf)[is.na(local_pf)]
if (length(missing_990) > 0)
  message("  CORE 990combined missing for: ", paste(missing_990, collapse = ", "))
if (length(missing_pf) > 0)
  message("  CORE 990pf missing for: ",       paste(missing_pf, collapse = ", "))

local_990 <- local_990[!is.na(local_990)]
local_pf  <- local_pf[!is.na(local_pf)]

core_990 <- dplyr::bind_rows(lapply(local_990, read_core_990combined))
core_pf  <- dplyr::bind_rows(lapply(local_pf,  read_core_990pf))
message("CORE 990 rows: ", format(nrow(core_990), big.mark = ","),
        "  |  CORE PF rows: ", format(nrow(core_pf), big.mark = ","))

# ---- 3. Org metadata --------------------------------------------------------
org_metadata <- build_org_metadata(bmf, core_990 = core_990, core_990pf = core_pf)

# ---- 4. Panels --------------------------------------------------------------
panels <- list()
panels$number_nonprofits <- build_number_nonprofits(org_metadata, years_990)
message("number_nonprofits rows: ", format(nrow(panels$number_nonprofits), big.mark = ","))

# ---- 5. Publish -------------------------------------------------------------
publish_vintage(panels, cfg, sandbox = !to_prod, dry_run = dry_run)
