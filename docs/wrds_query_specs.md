# WRDS data: what is pulled, and how to pull it without this code

## The database route (script 05, the one the pipeline uses)

Connection: `RPostgres::dbConnect(Postgres(), host = "wrds-pgdata.wharton.upenn.edu", port = 9737,
dbname = "wrds", sslmode = "require", user = <your user name>)`, password in `pgpass.conf`.

| Step | Table | Filters | Fields |
|---|---|---|---|
| Security master | `comp_global_daily.g_secd` | `curcdd = 'AUD'`, `exchg = 106`, `datadate >= '2008-07-01'`; one row per gvkey, iid, isin, sedol, conm with the count of trading days and the first and last day. **No country filter**: see the note below | gvkey, iid, isin, sedol, conm, trading_days, first_day, last_day |
| Daily prices | `comp_global_daily.g_secd` | the gvkey and iid of the linked emitters (`emitter_securities.csv`), same currency, exchange and date filters | gvkey, iid, datadate, conm, isin, sedol, prccd, ajexdi, trfd, cshoc, cshtrd |
| Fundamentals | `comp_global_daily.g_funda` | the linked gvkeys; `datafmt = 'HIST_STD'`, `consol = 'C'`, `indfmt = 'INDL'`, `datadate >= '2008-07-01'` | gvkey, datadate, fyear, conm, isin, sedol, curcd, revt, at, ceq, costat |
| LSEG ESG | `tr_esg.wrds_ref_esg` | `substr(isin, 1, 2) = 'AU'`, `fieldid in (64, 89, 95, 96, 97, 98)` | orgpermid, year, isin, ticker, comname, fieldid, fieldname, valuedate, value |
| LSEG field list | `tr_esg.wrds_ref_esg_item` | the same six items | item, feedfieldname, title |

The link from a register corporation to its price lines is made in the script (D4 and D25 in
`DECISIONS.md`): route (a) is the ASX code embedded in an old-format Australian ISIN, on lines that
still trade, for companies in today's ASX directory; route (b) is a strict name key on `conm`,
against any line that traded while the corporation was in the register, keeping every such line.

**Why there is no `fic` filter.** The first two builds also required `fic = 'AUS'`. Compustat carries
Rio Tinto Limited, an Australian company whose ordinary shares trade on the ASX in Australian
dollars, under the dual-listed group's country code, so that filter removed the fourth-largest listed
emitter of 2023-24 from the sample; Amcor and Fletcher Building went the same way. The exchange and
the currency are what define an ASX line. Dropping the term takes the security master from 3,906
lines to 4,092.

## The web-form route (no database access needed)

The pipeline pulls from the WRDS Postgres database, which needs a login with database access. The
same data can be downloaded through the WRDS website's query forms instead. The three extracts below
were downloaded that way in August 2026, while the database connection was still being set up, and a
second script read them; that script was removed on 10 September, when the sample definition changed
and it would have needed the whole two-route link rebuilt inside it for no gain. The specifications
are kept here because they are the route for anyone whose WRDS subscription does not include
database access.

The files are licensed and are not in the repository. Anyone with a WRDS subscription to Compustat
Global and V2 LSEG ESG Scores can re-create them from the specifications below, or run
`05_wrds_pull.R` against the database directly. Note that the web forms return the whole country or
the whole database rather than the sample, so the files are large (8.3 million daily rows, 3.3
million LSEG rows) and have to be filtered locally; the database route pulls only the lines the
sample needs, which is why the pipeline uses it.

| File | WRDS product and query form | Filters and fields | Downloaded | Rows |
|---|---|---|---|---|
| `cg_secd_AU_2010_2026.csv` | Compustat Global, Security Daily (`comp_global_daily.g_secd`) | Country (fic) AUS, all gvkeys in a company list; 2010-01-01 to 2026-08-19; fields fic, gvkey, datadate, conm, isin, sedol, exchg, conml, ajexdi, cshoc, cshtrd, curcdd, prccd, prchd, prcld, iid, trfd | 2026-08-21 | 8,257,954 |
| `cg_funda_AUS.csv` | Compustat Global, Fundamentals Annual (`comp_global.g_funda`) | fic AUS; fields fic, costat, datafmt, indfmt, consol, gvkey, datadate, conm, isin, sedol, exchg, gsubind, loc, curcd, at, dvt, emp, revt, cshoi, nicon, ninc | 2026-08-12 | 5,821 |
| `lseg_esg_core_long_2008_2026.csv` | V2 LSEG ESG Scores (long format, one row per company, year and field) | entire database, data years 2008 to 2026, 72 field ids including 64 ESGPeriodLastUpdateDate, 89 AnalyticCO2EstimationMethod, 95 CO2 Scope 1, 97 Scope 2, 96 Scope 3, 98 total; latin-1 encoded | 2026-08-21 | 3,304,467 |

Notes that matter when re-creating them:

- Compustat Global returns several currency lines per company (Rio Tinto returns EUR, USD, GBP, CHF,
  MXN, AUD and BRL). The analysis keeps `curcdd == "AUD"` and `exchg == 106` (ASX) and one issue
  line per company.
- `cshoc` (shares outstanding) is blank on about 1 per cent of daily rows; market capitalisation
  needs both `prccd` and `cshoc`.
- LSEG ESG on WRDS is a current snapshot: one `valuedate` per field and firm-year, overwritten when
  the vendor revises a value. A later download can differ from this one. The download date is
  therefore part of the data description.
- Some Australian firms carry a blank ISIN in the LSEG extract (ANZ, Telstra), so an ISIN-based
  selection of Australian firms is a lower bound.
