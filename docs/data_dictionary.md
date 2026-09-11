# Data dictionary

One entry per raw source (as downloaded) and per file the scripts write. Units and keys are the
ones the scripts rely on.

## Raw data (`data/raw/`)

### NGER register: `data/raw/nger/nger_<fy>.csv` (17 files, script 01; committed)
Source: Clean Energy Regulator, corporate emissions and energy data, one CSV per reporting year
1 July to 30 June, 2008-09 to 2024-25. Licence CC BY 4.0. URLs, file names and text encodings in
`docs/nger_urls.csv`. The column names changed over the years; script 02 selects them by content.

| Column (varies by year) | Used as | Notes |
|---|---|---|
| "Registered Corporations" / "Controlling Corporation" / "Organisation name" (always column 1) | `corporation` | legal name; footnote digits glued to some names in 2009-10 |
| "ABN" / "Identifying details" | `abn` | from 2013-14 in the files on disk (the 2018 re-publication); blank before |
| "Total scope 1 greenhouse gas emissions (t CO2-e)" and variants | `scope1` | tonnes CO2-e, operational control, Australian facilities; text with thousands separators |
| "Total scope 2 ..." | `scope2` | tonnes CO2-e |
| "Net energy consumed (GJ)" and variants | `energy` | gigajoules |

### ASX listed companies directory: `data/raw/asx/asx_directory_2026-09-03.csv` (script 03; committed)
Source: ASX, listed companies directory CSV, one row per listed company on the download day, 1,834 rows
on 3 September 2026. Script 03 reads this snapshot when it is present and writes it to
`asx_directory.csv`, which scripts 04 onward read; it downloads a fresh directory only if the snapshot
is missing. The snapshot is committed so that scripts 03 and 04 reproduce exactly.

| Column | Used as | Notes |
|---|---|---|
| ASX code | `asx_code` | ticker |
| Company name | `company_name` | |
| GICs industry group | `gics_industry_group` | 24 groups |
| Listing date | `listing_date` | dd/mm/yyyy |
| Market Cap | `market_cap_today` | A$, arrives as text, "--" for 72 companies |

### RBA exchange rates: `data/raw/rba/f11hist-1969-2009.xls`, `f11hist.xls` (script 03b; committed)
Source: Reserve Bank of Australia, statistical table F11, end-of-month rates, quoted as foreign
currency per A$1. Series used: `FXRUSD` (US dollars), `FXRUKPS` (pounds sterling), `FXRNZD` (New
Zealand dollars), `FXRSARD` (South African rand). Rows 1 to 10 describe the series; row 11 holds the
series identifiers. The rand series is populated for 59 months only, January 2010 to November 2014;
the other three cover every month from July 1969.

### Compustat Global via WRDS (script 05; licensed, not committed)
`data/raw/wrds/g_secd_au.csv`, from `comp_global_daily.g_secd`: lines quoted in AUD on the ASX
(exchg 106) from 2008-07-01, restricted to the sample corporations. No country-of-incorporation filter
is applied (see DECISIONS, "things that were tried and dropped"). The pull selects on the list of
gvkeys and the list of issue ids separately rather than on the pairs, so the extract holds 218 lines of
186 companies while the 192 lines linked in `emitter_securities.csv` are the ones the analysis uses;
script 06 joins on the pair, so the 26 extra lines are never used.

| Column | Meaning |
|---|---|
| gvkey, iid | company and issue identifiers |
| datadate | trading day |
| conm, isin, sedol | name and security identifiers; the ASX code is characters 3 to 11 of an old-format ISIN with leading zeros removed |
| prccd | closing price, A$ |
| ajexdi | adjustment factor for splits and bonus issues |
| trfd | total return factor (dividends reinvested) |
| cshoc | shares outstanding |
| cshtrd | shares traded |

`data/raw/wrds/g_funda_au.csv`, from `comp_global_daily.g_funda`, annual fundamentals of the same
companies (datafmt HIST_STD, consol C, indfmt INDL), from 2008-07-01.

| Column | Meaning |
|---|---|
| gvkey, datadate, fyear | company, financial year end, fiscal year |
| curcd | reporting currency in the extract: AUD 2,234 rows, USD 166, NZD 18, GBP 16, ZAR 4 |
| revt | total revenue, millions of `curcd` |
| at | total assets, millions |
| ceq | common equity, millions |
| costat | active or inactive |

### LSEG ESG via WRDS: `data/raw/wrds/lseg_esg_au.csv` (script 05; licensed, not committed)
From `tr_esg.wrds_ref_esg`, one row per company, data year and field, Australian ISINs only.

| Column | Meaning |
|---|---|
| orgpermid, isin, ticker, comname | company identifiers |
| year | the vendor's data year; a June year end is labelled by its calendar year |
| fieldid, fieldname | 64 ESGPeriodLastUpdateDate; 89 AnalyticCO2EstimationMethod (Reported, Median, CO2, Energy); 95 Scope 1; 97 Scope 2; 96 Scope 3; 98 total, all tonnes CO2-e |
| valuedate | the date the value now in the database was set; a snapshot date, overwritten when the vendor revises |
| value | text; converted to numbers in script 06 |

### Hand-collected reports: `data/hand_collected/firm_reports_fy2024.csv` (committed; no script recreates it)
One row per firm, transcribed from the firm's own FY2024 report. Columns: `asx_code`,
`company_name`, `nger_corporation`, `nger_scope1_t` (the register value, for reference),
`report_title`, `period_covered`, `document_url` (or "not recorded"), `retrieval_date`,
`publication_date` (ISO; where the document prints no date, `notes` says where the date came from), `page`,
`scope1_as_printed` (the exact string in the document), `scope1_unit`, `scope1_t` (converted to
tonnes), `boundary` (operational control, equity share, group global, Australia only, unclear),
`australia_only_scope1_t` (where the firm reports it), `scope2_as_printed`, `notes`, `confidence`
(high, medium, low).

## Processed data (`data/processed/`, rebuilt by the scripts, not committed)

| File | Script | One row per | Columns |
|---|---|---|---|
| `nger_panel.csv` | 02 | corporation and reporting year (6,664) | fy, corporation, abn, scope1, scope2, scope12, energy |
| `nger_asx_matched.csv` | 04 | corporation and reporting year (6,664) | the above plus name_key (after the rename bridge), abn_key (last nine digits of the register identifier), asx_code, company_name, gics_industry_group, listing_date, market_cap_today, in_directory. `in_directory` says only that a company of that name is on the ASX today; whether a firm-year is **listed** is decided in script 06 |
| `aud_usd_month_end.csv` | 03b | month, 1969-07 to today (686) | date (end of month), aud_usd, aud_gbp, aud_nzd, aud_zar, month (the first of that month, which is the join key) |
| `asx_security_master.csv` | 05 | ASX line quoted in AUD in Compustat since July 2008 (4,092) | gvkey, iid, isin, sedol, conm, trading_days, first_day, last_day, asx_code (from the ISIN). This is the historical ASX universe, which is what lets the sample include companies that have since delisted |
| `emitter_securities.csv` | 05 | price line of a register corporation (192 lines, 183 corporations) | name_key, corporation, asx_code, gvkey, iid, isin, sedol, conm, trading_days, first_day, last_day, link (isin or name). Nine corporations have two lines: a relisting (Virgin, Healthscope, Spotless, Toll, Gunns, Gloucester Coal, Newcrest, OZ Minerals) or a second class of shares (SGH) |
| `firm_year_variables.csv` | 06 | listed emitter and reporting year (1,615) | fy, end_year, name_key, corporation, asx_code, company_name, gics_industry_group, gvkey, iid, isin, link, scope1, scope2, scope12, market_cap (A$, last trading day of June), revt, ceq, at (A$ million), curcd, to_aud (the factor the reported values were multiplied by: Australian dollars per unit of curcd, so 1 for AUD rows), intensity (t CO2-e per A$ million revenue), method, flag, lseg_scope1, lseg_scope2 |
| `lseg_flag_firm_year.csv` | 06 | Australian ISIN and vendor year (6,508) | isin, end_year, method, lseg_scope1, lseg_scope2, flag. Keyed by ISIN, not by ASX code (DECISIONS D26) |
| `monthly_returns.csv` | 07 | price line and month (31,127) | gvkey, iid, month, ret |
| `tercile_panel.csv` | 07 | listed emitter and release year with an intensity (1,414) | fy, end_year, asx_code, corporation, gvkey, iid, intensity, tercile (1 low, 3 high). `corporation` is carried because a company that has delisted has no current ASX code |
| `table2_firm_years.csv` | 08 | listed emitter and release year (1,414) | fy, end_year, asx_code, corporation, gvkey, iid, tercile, intensity, ret_post6, ret_post12, vol_pre12, market_cap, log_market_cap, book_to_market, turnover_pre12 |

## Output (`output/`, regenerated; not committed): the exhibit map

| Exhibit in the report | File in `output/` | Script | Note |
|---|---|---|---|
| Table 1 (sample by reporting year) | `tables/table_1_sample_by_year.csv` | 07 (joins `table_a_sample_by_year.csv` and `table_c_reported_share_by_year.csv` of script 06 to the tercile counts) | seven columns: fy, reporters, listed_reporters, listed_share_of_scope1, with_vendor_value, reported_share, sorted_into_terciles. There is no separate "found in Compustat" column: being listed in a year means having a price line that year, so the two counts would be the same number. The percentages in the report are the shares in the file times 100, rounded |
| Table 2, Panels A, B, C | `tables/table_2_terciles.csv` (rows by `sample`) | 08 | the report shows mean (median) per tercile, the mean of the yearly differences, `t_stat`, `wilcoxon_p`, `n_low` / `n_high`, `release_years`; `t_stat_firm_level` and `p_t` stay in the file |
| Figure 1 | `figures/fig_1_february_publication.png`; data in `tables/figure1_average.csv`, `figure1_by_release_year.csv`, `figure1_tercile_counts.csv` | 07 | |
| Figure 2 | `figures/fig_2_register_vs_vendor.png` | 06 | two firm-years with a vendor value of zero are not drawn (log scale); the labels are the 2023-24 firm-years whose gap exceeds 100 per cent, thinned where two labels would overlap |
| Figure 3 | `figures/fig_3_report_dates.png`; data in `tables/table_e_hand_check.csv` | 09 | |
| Appendix Table A1 | `tables/table_b_register_vs_vendor.csv` | 06 | |
| Appendix Table A2 | `tables/table_d_flag_split.csv` | 08 | |
| Appendix Table A3 | `tables/table_e_hand_check.csv` | 09 | the vendor value, its flag and its value date are joined to the price line by ISIN (DECISIONS D26) |
| Appendix Figure A1 | `figures/fig_3b_returns_around_report.png`; data in `tables/figure3b_by_firm.csv` | 09 | |
| Cited in the text only | `tables/table_2_top_returns.csv`, `table_2_pooled_gap.csv` (the largest high-tercile returns and the pooled gap with and without the five largest) | 08 | |
| Not in the report | `tables/table_f_terciles_2023-24.csv`, `figures/fig_a_reporters_by_year.png`, `fig_c_emissions_vs_size_2024.png` | 06 | the 2023-24 cross-section and two exploratory figures |
| Console output of each run | `log_<script>.txt` | all | kept locally, not committed |
