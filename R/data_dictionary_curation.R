# Hand-curated descriptions for every (file, column) pair this pipeline emits.
# Edit this file when you add/rename a panel column. `build_data_dictionary()`
# joins these against the actual output schemas and fails if anything drifts
# (missing description for a real column, or curated entry for a column that
# no longer exists).
#
# Schema fields:
#   description     — what the value means, plain English
#   form_source     — IRS Form 990 line(s) where applicable, or pipeline derivation
#   coverage        — year range as observed in the output
#   coverage_notes  — known limitations / gaps; surfaces in dashboard tooltips

# Shared dimension columns appear in every panel. Defined once, expanded per
# panel by build_data_dictionary().
.DD_SHARED_DIMS <- tibble::tribble(
  ~column,             ~description,                                              ~form_source,                                        ~coverage_notes,
  "Organization Type", "501(c) classification (e.g. '501(c)(3) Public Charities', '501(c)(4)'). Public charities and private foundations are split out within (c)(3).", "BMF subsection code mapped via derive_organization_type().",     "",
  "Subsector",         "NCCS major group (NTEE Level-1) \u2014 26 categories like 'ART', 'EDU', 'HEL'.", "BMF NTEE-V2 code mapped via derive_subsector().",  "",
  "Size",              "Static per-EIN size band 1-6 by total_expenses, or 0 if no CORE filing ever observed. Locked per EIN \u2014 does not float year-to-year.", "Derived from most-recent non-NA total_expenses across CORE 990 + 990-PF.", "Size=0 means the org has BMF metadata but no CORE filing on record.",
  "Census Region",     "US Census-defined region (Northeast / Midwest / South / West).",          "Derived from Census State via derive_census_region().",                "",
  "Census State",      "2-letter USPS state code from BMF geocode.",                              "BMF CENSUS_STATE_ABBR.",                                                "~8% of BMF rows have NA Census State \u2014 pass-through documented upstream gap.",
  "Census County",     "Census-defined county name from BMF geocode.",                            "BMF CENSUS_COUNTY_NAME.",                                                "",
  "Metro/Micro Area",  "OMB-defined CBSA name (Metropolitan or Micropolitan Statistical Area).",  "Joined from inst/lookups/cbsa_crosswalk.parquet (Census Jul 2023 OMB).", "NA for rural counties not in any CBSA \u2014 expected."
)

# Per-panel non-dimension columns.
.DD_PANEL_COLS <- tibble::tribble(
  ~file,                       ~column,               ~description,                                                                         ~form_source,                                                                                         ~coverage_notes,
  # number_nonprofits
  "number_nonprofits.parquet", "Year",                "Tax year of the count.",                                                              "BMF active-window: org counted in year Y if org_year_first \u2264 Y \u2264 org_year_last.",                  "",
  "number_nonprofits.parquet", "Number of Nonprofits","Count of distinct EINs active in this (Year, dim) cell per the BMF active-window rule.", "Aggregate of BMF rows.",                                                                            "Excludes orgs without a BMF window. 1989\u20132026 range.",
  # finances
  "finances.parquet",          "Year",                "Tax year as reported on the filing.",                                                 "CORE filing tax_year.",                                                                              "",
  "finances.parquet",          "Total Revenues",      "Sum of total revenue across orgs in the (Year, dim) cell.",                          "990: Form 990 Pt VIII Line 12 (total revenue). 990-PF: Pt I Line 12 Col (a). 990EZ: total_revenue.",  "",
  "finances.parquet",          "Total Expenses",      "Sum of total expenses across orgs in the (Year, dim) cell.",                         "990: Form 990 Pt IX Line 25 Col A (total functional expenses, harmonized to total_expenses). 990-PF: Pt I Line 26 Col (a). 990EZ: total_expenses.", "",
  "finances.parquet",          "Total Assets",        "Sum of end-of-year total assets across orgs.",                                       "990: Pt X Line 16 EOY (total_assets_eoy). 990-PF: Pt II Line 16 Col (b). 990EZ: total_assets_eoy.",   "",
  "finances.parquet",          "Total Benefits",      "Sum of total personnel costs (compensation + salaries/wages + pension + other employee benefits) across orgs. NOT including Pt IX-4 'Benefits paid to or for members' \u2014 that is a different concept (member payouts, not employee comp).", "Form 990 Pt IX Lines 5+6+7+8+9.  990-PF and 990EZ do not carry these lines \u2014 those filers contribute NA.", "1989\u20132011: partial 2-line proxy (lines 5+7 only); lines 6/8/9 not extracted in legacy data. Visible discontinuity at 2012 as full 5-line sum becomes available.",
  # pf_grants
  "pf_grants.parquet",         "Year",                "Tax year as reported on the 990-PF filing.",                                          "CORE 990-PF tax_year.",                                                                              "",
  "pf_grants.parquet",         "Total Contributions", "Sum of contributions paid OUT by private foundations (grants given to grantees) in the cell.", "Form 990-PF Pt I Line 25 Col (a): contributions_paid.",                                       "2011\u20132016: ~50% underreported vs prior dashboard. IRS never released the 2017\u20132019 backfill that populated PZ-HRMN for those years; processed_merged 990pf has the thinner coverage.",
  # daf
  "daf.parquet",               "Year",                "Tax year as reported on the Schedule D filing.",                                      "DAF e-file Schedule D, harmonized.",                                                                 "",
  "daf.parquet",               "Number of Nonprofits","BMF active-window count of orgs in the cell \u2014 denominator for the dashboard's 'Percentage of Nonprofits with DAFs' metric.", "Aggregate of BMF rows where org_year_first \u2264 Year \u2264 org_year_last.",                  "Matches the number_nonprofits panel for the same cells.",
  "daf.parquet",               "Number of DAFs",      "Sum of donor-advised funds (and 'other similar funds') reported end-of-year, across orgs in the cell.", "Form 990 Schedule D Part I Line 1: SD_01_TOT_NUM_EOY_DAF + SD_01_TOT_NUM_EOY_OTH.",        "DAF reporting began 2008; coverage in this dataset starts 2021 (earlier years not in e-file).",
  "daf.parquet",               "Total Contributions", "Sum of aggregate contributions to DAFs (and OSFs) for the cell.",                    "Schedule D Pt I Line 2: SD_01_AGGREGATE_CONTR_DAF + _OTH.",                                          "",
  "daf.parquet",               "Total Grants",        "Sum of aggregate grants made from DAFs (and OSFs).",                                 "Schedule D Pt I Line 3: SD_01_AGGREGATE_GRANT_DAF + _OTH.",                                          "",
  "daf.parquet",               "Total Value",         "Sum of aggregate end-of-year value of DAFs (and OSFs).",                             "Schedule D Pt I Line 4: SD_01_AGGREGATE_VALUE_EOY_DAF + _OTH.",                                      "",
  "daf.parquet",               "Has DAF",             "Count of orgs in the cell with at least one DAF (num_dafs > 0).",                    "Derived per-row from Number of DAFs > 0, summed.",                                                   "",
  # nested_geographies
  "nested_geographies.csv",    "Census State",        "2-letter USPS state code.",                                                          "BMF.",                                                                                               "",
  "nested_geographies.csv",    "Census County",       "County name.",                                                                        "BMF.",                                                                                               "",
  "nested_geographies.csv",    "Metro/Micro Area",    "OMB CBSA name.",                                                                      "CBSA crosswalk.",                                                                                    "NA for rural counties.",
  "nested_geographies.csv",    "Census Region",       "US Census region.",                                                                  "Derived from state.",                                                                                ""
)
