# Build inst/lookups/cbsa_crosswalk.parquet from the OMB delineation file.
#
# Source: Census Bureau, "List 1: Core Based Statistical Areas (CBSAs),
# Metropolitan Divisions, and Combined Statistical Areas (CSAs)",
# 2023 vintage (OMB Bulletin No. 23-01, last updated July 2023).
#
# Run: Rscript data-raw/build_cbsa_crosswalk.R
#
# Update cadence: re-run when OMB issues a new bulletin (every few years).
# Stamp the new vintage in the call below and bump it in the manifest entry.

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(arrow); library(tibble)
})

SRC_URL <- "https://www2.census.gov/programs-surveys/metro-micro/geographies/reference-files/2023/delineation-files/list1_2023.xlsx"
VINTAGE <- "2023-07"
OUT     <- "inst/lookups/cbsa_crosswalk.parquet"

tmp <- tempfile(fileext = ".xlsx")
download.file(SRC_URL, tmp, mode = "wb", quiet = TRUE)
raw <- read_excel(tmp, sheet = 1, skip = 2)

# Full-name -> 2-letter postal. base R's state.* covers the 50 states; add
# DC + territories that appear in the Census file.
state_lookup <- tibble(
  state_name = c(state.name, "District of Columbia", "Puerto Rico"),
  state_abbr = c(state.abb,  "DC",                   "PR")
)

unmatched <- setdiff(stats::na.omit(unique(raw$`State Name`)),
                    state_lookup$state_name)
if (length(unmatched) > 0) {
  stop("Unmapped state names in delineation file: ",
       paste(unmatched, collapse = ", "))
}

crosswalk <- raw |>
  transmute(
    state_name = `State Name`,
    county     = `County/County Equivalent`,
    cbsa_title = `CBSA Title`,
    cbsa_code  = `CBSA Code`,
    metro_micro = `Metropolitan/Micropolitan Statistical Area`
  ) |>
  inner_join(state_lookup, by = "state_name") |>
  transmute(
    state_abbr,
    county,
    `Metro/Micro Area` = cbsa_title,
    cbsa_code,
    metro_micro
  ) |>
  distinct()

stopifnot(nrow(crosswalk) > 1500)            # sanity floor
stopifnot(n_distinct(crosswalk$state_abbr) >= 51)

write_parquet(crosswalk, OUT, compression = "snappy")

cat(sprintf("Wrote %s (%s rows, %s CBSAs, vintage %s)\n",
            OUT, nrow(crosswalk),
            n_distinct(crosswalk$`Metro/Micro Area`),
            VINTAGE))
