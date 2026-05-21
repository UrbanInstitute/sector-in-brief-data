# sector-in-brief-data

Producer pipeline for the parquet artifact consumed by the
[Sector-in-Brief Shiny dashboard](https://github.com/UrbanInstitute/sector-in-brief).

Reads canonical NCCS BMF, CORE 990/990EZ, 990-PF, and DAF e-file inputs from
S3; applies per-panel aggregations; and publishes vintage-tagged parquet to
`s3://nccsdata/sector-in-brief/v{YYYY.MM}/`, with a `latest/` server-side
mirror that the dashboard reads from.

Supersedes the archived
[`UrbanInstitute/nccs-dataexplorer-data`](https://github.com/UrbanInstitute/nccs-dataexplorer-data)
per [ADR 0010](https://github.com/UrbanInstitute/nccs-contracts/blob/main/decisions/0010-sector-in-brief-data-replaces-dataexplorer-data.md).

## Outputs (per vintage)

| File | Year range | Metrics |
|---|---|---|
| `number_nonprofits.parquet` | 1989–present | `Number of Nonprofits` |
| `finances.parquet` | 1989–2024 | `Total Revenues`, `Total Expenses`, `Total Assets`, `Total Benefits` |
| `pf_grants.parquet` | 1989–2024 | `Total Contributions` |
| `daf.parquet` | 2020–2024 | `Number of Nonprofits`, `Number of DAFs`, `Total Contributions`, `Total Grants`, `Total Value`, `Has DAF` |
| `nested_geographies.csv` | static | `Census State`, `Census County`, `Metro/Micro Area`, `Census Region` |
| `data_dictionary.parquet` | static | per-(file, column) descriptions |
| `_manifest.json` | per-vintage | sha256, row counts, input ETags, git SHA |

All panels share the same dimension columns: `Organization Type`,
`Subsector`, `Size` (int32 0–6, static per EIN, derived from total
expenses), `Census Region`, `Census State`, `Census County`,
`Metro/Micro Area`, plus `Year` where temporal. Aggregate grain only — no
EIN-level rows in output.

## Running on a fresh machine (EC2, etc.)

The pipeline is self-contained — no manual data wrangling, no committed
inputs. A clean machine needs R 4.3+, the AWS CLI, a few OS-level dev
libraries (so `arrow` and the GitHub-installed `nccsdata` build cleanly),
and an AWS profile that can read the source buckets and write
`s3://nccsdata/sector-in-brief*`.

Tested on Ubuntu 24.04 (matches the GitHub Actions runner). For Amazon
Linux 2023 substitute `dnf` for `apt` and the equivalent `-devel` package
names.

```bash
# 1. System packages
sudo apt-get update
sudo apt-get install -y \
    r-base r-base-dev \
    libssl-dev libxml2-dev libcurl4-openssl-dev libgit2-dev \
    libfontconfig1-dev libharfbuzz-dev libfribidi-dev \
    libfreetype6-dev libpng-dev libtiff5-dev libjpeg-dev \
    awscli git

# 2. AWS credentials — the pipeline uses profile `thiya`.
#    Either drop credentials in ~/.aws/credentials:
#      [thiya]
#      aws_access_key_id     = ...
#      aws_secret_access_key = ...
#      region                = us-east-1
#    or attach an IAM role with equivalent S3 permissions and edit
#    config.yml's aws.profile to match (e.g. "default").

# 3. Clone the repo
git clone https://github.com/UrbanInstitute/sector-in-brief-data.git
cd sector-in-brief-data

# 4. Install R dependencies (resolves CRAN imports + the GitHub-hosted
#    `nccsdata` listed under Remotes). First run takes ~10-15 min on a
#    cold machine because arrow compiles from source.
Rscript -e 'install.packages("remotes", repos = "https://cloud.r-project.org"); remotes::install_deps(dependencies = TRUE, upgrade = "never")'

# 5. Smoke-test the package
Rscript -e 'devtools::test()'

# 6. Publish a vintage (bump config.yml's `vintage:` first if needed)
Rscript pipeline/run.R --prod
```

EC2 sizing: the pipeline is I/O- and memory-bound, not CPU-bound. An
`m6i.large` (2 vCPU, 8 GB) handles a full run; bump RAM if you see
allocation errors on the BMF + CORE joins. Running on EC2 also removes
the bandwidth bottleneck that makes a local laptop run take 30-60 min;
expect under 15 min in the same VPC region as the source S3 buckets.

## Running the pipeline

From the repo root:

```bash
# Sandbox publish
Rscript pipeline/run.R

# Production publish (also writes latest/ mirror when also_publish_latest is on)
Rscript pipeline/run.R --prod

# Stage locally without uploading
Rscript pipeline/run.R --dry-run
```

All I/O paths are sourced from `config.yml`. AWS profile `thiya` is used for
S3 access. Bump the `vintage:` field in `config.yml` before each new
production publish.

## Development

```bash
# Run the test suite
Rscript -e 'devtools::test()'

# Full R CMD check (also runs in CI)
Rscript -e 'devtools::check()'
```

CI: `.github/workflows/R-CMD-check.yml` runs on every push to `main`.

In WSL2, `library(arrow)` requires `R_LIBS_SITE=/usr/local/lib/R/site-library`
because the system Renviron doesn't include the site library by default.

## Layout

```
R/                        package functions (read_*, derive_*, build_<panel>, publish_vintage, …)
tests/testthat/           unit tests + small fixtures
pipeline/run.R            top-level pipeline entrypoint
config.yml                input paths, output prefixes, year ranges, vintage
inst/lookups/             cbsa_crosswalk.parquet (ships with the package)
inst/fixtures/            small sampled inputs for tests
.github/workflows/        R CMD check, publish workflow
```

See `CLAUDE.md` for contributor guidance and `NEW_REPO_BOOTSTRAP.md` for the
historical bootstrap spec.
