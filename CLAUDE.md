# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

This repo is a **green-field bootstrap**. Only `NEW_REPO_BOOTSTRAP.md`, `README.md`, and `LICENSE` exist. The R package scaffold (DESCRIPTION, NAMESPACE, `R/`, `tests/`, `pipeline/run.R`, `config.yml`, `inst/`, GitHub workflows) has **not been created yet**. Read `NEW_REPO_BOOTSTRAP.md` end-to-end before any non-trivial work — it is the spec, not background reading.

## What this repo does

Producer of the parquet artifact consumed by the `UrbanInstitute/sector-in-brief` Shiny dashboard. Reads canonical NCCS BMF + core + IRS SOI 990-PF + DAF e-file inputs from S3, applies per-panel aggregations, and publishes vintage-tagged parquet to `s3://nccsdata/sector-in-brief/vYYYY.MM/`. Replaces (and will archive) `UrbanInstitute/nccs-dataexplorer-data`.

**Aggregate-grain only.** No `EIN2` columns in output. Org-grain / API-side outputs are out of scope (see ADR 0008).

## Required external reading (in `../nccs-contracts/` and sibling repos)

Authoritative sources that constrain this repo's behavior — consult before designing anything:

1. `../nccs-contracts/decisions/0010-sector-in-brief-data-replaces-dataexplorer-data.md` — mandate.
2. `../nccs-contracts/contracts/sector-in-brief.yml` — output contract (stub; this repo fills it).
3. `../nccs-contracts/contracts/bmf-master-geocoded.yml` — BMF input contract.
4. `../nccs-contracts/decisions/0011-decouple-dashboard-from-committed-data.md` — what the dashboard does once we publish.
5. `../sector-in-brief/R/options_nogeo.R` and `../sector-in-brief/R/data_server_args.R` — **truth** for output column names, panel names, value sets. Output schema must match these strings verbatim.
6. `../nccs-dataexplorer-data/` (archived after parity) — prior implementation; lift business logic, leave the structure.

## Architecture (target — not yet implemented)

Single-direction data flow:

```
S3 inputs ──► read_bmf() / read_core() ──► derive_*() ──► build_<panel>() ──► publish_vintage() ──► S3
                  (canonical names)         (pure fns)     (one per panel)      (+ manifest.json)
```

Key invariants:

- **`R/read_bmf.R` is the only place that knows new-BMF source column names.** It returns canonical names (`EIN2`, `NTEEV2`, `BMF_SUBSECTION_CODE`, `F990_TOTAL_ASSETS_RECENT`, `CENSUS_*`, `NCCS_LEVEL_1`, `ORG_YEAR_FIRST/LAST`). See translation table in `NEW_REPO_BOOTSTRAP.md` §"BMF input translation". Panel builders consume canonical names.
- **Derivation functions are pure and consolidated** into `R/derive_dimensions.R` + `R/derive_ein.R`. The old repo duplicated these as inline `case_when` chains across `01_bmf_data.R` and `10_api_data.R` (Title Case vs SCREAMING_SNAKE). One definition each, tested against fixtures.
- **Every panel parquet uses the same dimension column names and types** — exact strings: `Organization Type`, `Subsector`, `Size` (int32, 0–6), `Census Region`, `Census State`, `Census County`, `Metro/Micro Area`, and `Year` (int32) where temporal. No `Tax Year` / `TAX_YEAR` drift. See the per-panel metric-column table in `NEW_REPO_BOOTSTRAP.md` §"Output contract".
- **All paths come from `config.yml` via `read_config()`.** No hardcoded relative paths, no `setwd()`, runnable from repo root.
- **Every published vintage drops `_manifest.json`** alongside the parquets with sha256, row counts, input ETags, git SHA. No silent overwrites of `latest/`.

## Non-negotiables (lessons from the old repo)

1. No hardcoded relative paths in R; all I/O through `read_config()`.
2. `.gitattributes` must contain `* text=auto eol=lf` from commit one. On first clone also run `git config core.autocrlf input`. This avoids the CRLF re-stain that masqueraded as a 16-file modification pile.
3. No vendored C++ (no `rapidxml-1.13/`). Fast XML paths need an ADR first.
4. No scratch/spike scripts in `R/` — branches or gists only.
5. Schema discipline: one canonical name and type per concept across all files; data dictionary derived from actual schemas, not hand-maintained.
6. `gov_grants` and `pf_pri` must ship at **aggregate grain** (old pipeline left them org-grain or unwired).
7. **Size derivation** has a known inconsistency: old code keyed off `F990_TOTAL_ASSETS_RECENT`, dashboard's `options_nogeo.R` documents expense-based bands. Confirm with the contract before locking it in.

## Working with S3

- AWS profile: `thiya`. Use `--profile thiya` for all `aws` CLI calls.
- Output bucket/prefix: `s3://nccsdata/sector-in-brief/v{vintage}/` (+ optional server-side copy to `latest/`).
- Before the first vintage publish, do the prefix migration in `NEW_REPO_BOOTSTRAP.md` §"S3 prefix migration" — **confirm with the user before any S3 delete**.

## Clone hygiene

On first clone and any future clone, run:

```bash
git fetch --all
git config core.autocrlf input
git status -sb
git rev-list --left-right --count origin/main...HEAD
```

The old repo was 51 commits behind with a CRLF stain that looked like real changes. Catch both before doing any work.

## Commands

The R package toolchain is not yet scaffolded. Once it exists, expected commands (from `NEW_REPO_BOOTSTRAP.md` §"First-session task list"):

- Scaffold: `Rscript -e 'usethis::create_package(".")'`, then `usethis::use_testthat()`, `usethis::use_github_actions("check-standard")`.
- Tests: `Rscript -e 'devtools::test()'` (all) or `Rscript -e 'testthat::test_file("tests/testthat/test-derive_dimensions.R")'` (single file).
- Check: `Rscript -e 'devtools::check()'` (also runs in CI via `.github/workflows/R-CMD-check.yml`).
- Run the full pipeline: `Rscript pipeline/run.R` from the repo root.
- Publish a vintage: manual-trigger `publish.yml` workflow (after bumping `vintage:` in `config.yml`).

Verify these exactly once the scaffold lands; update this section if they differ.
