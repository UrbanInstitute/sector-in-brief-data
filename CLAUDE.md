# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Status

Scaffold + Phase 4 are landed. First production vintage `v2026.05` shipped 2026-05-21 to `s3://nccsdata/sector-in-brief/v2026.05/` with a `latest/` mirror, and the dashboard cut over. The predecessor repo `UrbanInstitute/nccs-dataexplorer-data` is archived.

Two more panels — `gov_grants` and `pf_pri` — are built and verified against live data (branch `feat/gov-grants-pf-pri-panels`, 2026-05-29) but **not yet published to a vintage**. They source the efile Phase 0 slice (`s3://nccsdata/processed/efile/phase0/latest/`), which went live 2026-05-29. Both cover **2021–2023 only** (e-file is complete from 2021; 2024 filings are still arriving). Publishing them needs a vintage bump past the frozen `v2026.05`.

For the canonical, post-cutover data model (inputs, outputs, scope), use the project-data-model memory record. BOOTSTRAP is historical.

## What this repo does

Producer of the parquet artifact consumed by the `UrbanInstitute/sector-in-brief` Shiny dashboard. Reads canonical NCCS BMF + CORE 990/990EZ + 990-PF + DAF e-file inputs from S3, applies per-panel aggregations, and publishes vintage-tagged parquet to `s3://nccsdata/sector-in-brief/vYYYY.MM/` (with a `latest/` server-side mirror).

**Aggregate-grain only.** No `EIN2` columns in output. Org-grain / API-side outputs are out of scope (see ADR 0008).

## Required external reading (in `../nccs-contracts/` and sibling repos)

Authoritative sources that constrain this repo's behavior — consult before designing anything:

1. `../nccs-contracts/decisions/0010-sector-in-brief-data-replaces-dataexplorer-data.md` — mandate.
2. `../nccs-contracts/contracts/sector-in-brief.yml` — output contract (stub; this repo fills it).
3. `../nccs-contracts/contracts/bmf-master-geocoded.yml` — BMF input contract.
4. `../nccs-contracts/decisions/0011-decouple-dashboard-from-committed-data.md` — what the dashboard does once we publish.
5. `../sector-in-brief/R/options_nogeo.R` and `../sector-in-brief/R/data_server_args.R` — prior dashboard string conventions (`Asset Size`, `Census CBSA`, `Tax Year`). **No longer authoritative** — see "Output naming" below. The dashboard updates to the cleaner names emitted by this repo, not the other way around.
6. `../nccs-dataexplorer-data/` (archived 2026-05-21) — prior implementation; historical reference only.

## Output naming (authoritative)

This repo's panel output column names are the contract. The dashboard conforms. Specifically:

- `Size` — static per-EIN size band by total **expenses** (NOT assets — the dashboard's prior `Asset Size` label is a misnomer; expenses is what `derive_size` consumes).
- `Metro/Micro Area` — OMB CBSA name. Replaces the dashboard's prior `Census CBSA` (which was an internal join-key name, not a user-facing concept).
- `Year` — tax year as reported on the filing. Replaces the dashboard's prior `Tax Year`.
- All other dimension columns retain the title-case names already in use (`Organization Type`, `Subsector`, `Census Region`, `Census State`, `Census County`).

`R/data_dictionary_curation.R` carries the per-(file, column) descriptions; `build_data_dictionary()` fails loudly if a panel column lacks a description or a curated entry has gone stale.

## Architecture

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
6. `gov_grants` and `pf_pri` are now **in scope** (user-approved 2026-05-29) and built off the efile Phase 0 slice — superseding the prior "out of scope / deferred" stance. `gov_grants` = Form 990 Pt VIII line 1e (grants **received**, NOT Schedule I grants paid to governments); `pf_pri` = Form 990-PF Pt IX-B aggregate. Both publish 2021–2023 only. Do not source either from the GivingTuesday Data Mart (the archived dataexplorer-data drafts did — efile is the canonical source now).
7. **Size derivation** is locked to total **expenses** (not assets, despite the old dashboard's `Asset Size` label). See "Output naming".

## Working with S3

- AWS profile: `thiya`. Use `--profile thiya` for all `aws` CLI calls.
- Output bucket/prefix: `s3://nccsdata/sector-in-brief/v{vintage}/` plus `s3://nccsdata/sector-in-brief/latest/` (auto server-side mirror when `output.also_publish_latest: true`, prod only).
- Sandbox prefix: `s3://nccsdata/sector-in-brief-sandbox/v{vintage}/` (used by `Rscript pipeline/run.R` without `--prod`).
- The 2026-05-21 prefix migration is done — pre-cutover contents live under `s3://nccs-data-archive/superseded/`. Any future destructive S3 operation still needs explicit user confirmation.

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

Run from the repo root.

- Tests: `Rscript -e 'devtools::test()'` (all) or `Rscript -e 'testthat::test_file("tests/testthat/test-<name>.R")'` (single file). CI runs the same via `.github/workflows/R-CMD-check.yml`.
- Check: `Rscript -e 'devtools::check()'`.
- Full pipeline → sandbox: `Rscript pipeline/run.R` → `s3://nccsdata/sector-in-brief-sandbox/v{vintage}/`.
- Full pipeline → prod: `Rscript pipeline/run.R --prod` → `s3://nccsdata/sector-in-brief/v{vintage}/` and (if config flag set) mirror to `latest/`. Bump `vintage:` in `config.yml` before publishing a new one.
- Stage locally without uploading: `Rscript pipeline/run.R --dry-run`.

**Environment quirk**: in WSL2 the system R doesn't include `/usr/local/lib/R/site-library` on its default path, so `library(arrow)` fails. Either `export R_LIBS_SITE=/usr/local/lib/R/site-library` or invoke with the prefix.
