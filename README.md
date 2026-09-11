# Priced when public, or priced when processed? Emissions disclosure channels and Australian stock prices

MAF900 Advanced Data Methods, Assessment 2. Niklas Ziemann, Deakin University.
Report: submitted separately on CloudDeakin. This repository holds the code and documentation that
produce every table and figure in it.

Research question (Assessment 1): do disclosure processing costs delay the incorporation of
publicly available emissions information into Australian stock prices?

The public NGER register publishes large emitters' Scope 1 and 2 emissions every February. The
pipeline below links those register values to ASX-listed firms, to their share prices and
fundamentals in Compustat Global, and to a commercial vendor's emissions values (LSEG ESG), then
compares high- and low-intensity firms around the February publication.

If you only want to run the pipeline, the section on [how to reproduce](#how-to-reproduce) it has all
of the steps, including how to create the WRDS password file.

## Data sources and access

|Source|What it gives us|Access|Script|
|-|-|-|-|
|NGER register, Clean Energy Regulator|Scope 1 and 2 emissions of every corporation above the reporting threshold, one file per reporting year 2008-09 to 2024-25, published by 28 February|Public, CC BY 4.0. The 17 files are in `data/raw/nger/` (about 400 KB); script 01 re-downloads any that are missing, 20 s apart (the site rate-limits)|01, 02|
|ASX listed companies directory|ASX code, name, GICS industry group, market cap of every company listed today|Public. The 3 September 2026 snapshot the report used is committed (`data/raw/asx/asx\\\_directory\\\_2026-09-03.csv`, 120 KB); script 03 reads it when it is there and downloads a fresh one otherwise|03|
|RBA statistical table F11|End-of-month exchange rates since 1969: AUD/USD, AUD/GBP, AUD/NZD and AUD/ZAR|Public. Two Excel files in `data/raw/rba/`. The rand series is populated only from January 2010 to November 2014|03b|
|Compustat Global (WRDS)|Daily prices, adjustment and total return factors, shares outstanding and traded; annual revenue, assets, book equity. Also the security file, which is what makes the historical ASX universe available: every line carries its first and last trading day|Licensed: a WRDS login with Compustat Global. Pulled from the database with your own login; never committed|05|
|LSEG ESG Scores V2 (WRDS)|The vendor's Scope 1 and 2 values and the flag saying whether a value was reported by the firm or estimated by the vendor|Licensed: a WRDS login with LSEG ESG. Never committed|05|
|Firms' own FY2024 reports|Scope 1 as the firm printed it, its boundary, and the report's publication date, for ten of the largest listed emitters|Public documents; transcribed by hand into `data/hand\\\_collected/firm\\\_reports\\\_fy2024.csv` with document, page, URL and the printed string. No script recreates this file|09|

`docs/data\\\_dictionary.md` lists every column and maps each exhibit of the report to the file and
script behind it. `docs/wrds\\\_query\\\_specs.md` describes the WRDS tables and fields, and documents the
web-form route to the same extracts for anyone without database access.

## Which companies are in the sample

A register corporation is **listed in a reporting year** when one of its Compustat ASX price lines
traded during that year (1 July to 30 June). Nothing else goes into that decision. The same rule also handles the cases that a list of the
companies listed today cannot handle:

* a company that has **delisted** since keeps the years in which it traded (Boral, Newcrest, CSR);
* a company that **listed later** enters only when it lists (Viva Energy has been in the register
since 2013-14 and enters the sample in 2018-19, when it listed);
* a company that **changed its name** is one company across the panel, because the register's own
identifier bridges the names (BHP Billiton to BHP Group, Woodside Petroleum to Woodside Energy,
Caltex to Ampol; script 04 prints all 97 renames it finds).

Three companies in today's directory have no ASX line in Compustat at all, because their ASX
securities are CDIs of a US parent: Alcoa, Newmont and News Corp. So, they do not appear in any sample year.

The ASX directory is still used, for the ASX code, the GICS industry group and the listing date of
the companies that are on it. It no longer decides membership. `docs/DECISIONS.md` D22, D23, D24 and
D25 record the design and what it changed.

## Project structure

```
MAF900\\\_Assignment2\\\_Niklas\\\_Ziemann.Rproj   open this in RStudio; here() then finds every path
renv.lock, .Rprofile, renv/      package versions (renv); renv::restore() installs them
README.md                        this file
config\\\_example.csv               template for config.csv (WRDS user name; config.csv itself is git-ignored)
code/                            ten numbered scripts plus run\\\_all.R, run in this order
  01\\\_download\\\_nger.R             download the 17 register files (skips files already on disk)
  02\\\_parse\\\_nger.R                one tidy panel: corporation x reporting year, columns selected by content across vintages
  03\\\_asx\\\_directory.R             the ASX directory: read the committed snapshot, or download today's
  03b\\\_rba\\\_exchange\\\_rates.R       download the RBA exchange rate history (USD, GBP, NZD, ZAR)
  04\\\_match\\\_nger\\\_asx.R            name key, the identifier bridge across renames, join to the ASX directory
  05\\\_wrds\\\_pull.R                 Compustat Global and LSEG ESG from the WRDS database (RPostgres); the historical ASX security master; the link from each corporation to its price lines
  06\\\_first\\\_analysis.R            listed-in-year from the trading window; firm-year variables; sample by year; register versus vendor (Figure 2)
  07\\\_figure1.R                   monthly returns, intensity terciles, Table 1, Figure 1
  08\\\_table2\\\_terciles.R           Table 2: terciles compared, with the tests
  09\\\_hand\\\_check\\\_figure3.R        the hand-collected reports; Figure 3 and Appendix Figure A1
  run\\\_all.R                      runs all ten in order and writes docs/session\\\_info.txt
data/
  raw/nger, raw/rba              committed (public)
  raw/asx                        the 3 September 2026 snapshot is committed; later downloads are not
  raw/wrds                       licensed extracts, git-ignored (a .gitkeep marker keeps the folder in the clone)
  processed/                     rebuilt by the scripts, git-ignored (same marker)
  hand\\\_collected/                committed
docs/
  nger\\\_urls.csv                  the 17 download links and each file's text encoding
  data\\\_dictionary.md             every raw and processed column, and the exhibit map
  DECISIONS.md                   the judgement calls, with the alternative and its measured effect
  wrds\\\_query\\\_specs.md            WRDS tables, fields and filters, and the web-form route
  session\\\_info.txt               R and package versions of the run of 10 September 2026
output/
  tables/, figures/              regenerated by the scripts, git-ignored
  \\\_old/                          superseded console logs, kept rather than deleted; git-ignored
```

## What renv, renv.lock and .Rprofile are for

R packages change, and a script that ran last year can give different numbers, or refuse to run, on
this year's versions. renv pins them.

* **`renv.lock`** is the manifest. It records R 4.6.0 and the exact version of all 113 packages this
project loaded, with a checksum for each. It is a text file and it is committed.
* **`renv::restore()`** reads that manifest and installs those exact versions into a library that
belongs to this project alone, not to your machine. Nothing you already have is touched or changed.
* **`.Rprofile`** is one line. R runs it automatically when the project opens, and it switches renv on
for the session, so nothing has to be switched on by hand.
* **`renv/activate.R`** is the bootstrap that `.Rprofile` calls; **`renv/settings.json`** holds the
project's renv options. Both are committed and both are small.
* **`renv/library/`** is the installed packages themselves. It is NOT committed, because it is large,
machine-specific and fully rebuilt from `renv.lock`. That is deliberate: the lockfile is the thing
that needs to travel with the project, and the installed library can just be rebuilt at the other end.

So, anyone who clones the repository, opens the project and runs `renv::restore()` ends up on the same
package versions this analysis ran on.

## How to reproduce

In order to reproduce this analysis, work through the seven steps below. Steps 1 to 3 and 6 need no
WRDS account; steps 4 and 5 do, and without them scripts 05 to 09 cannot run.

**1. R and RStudio.** R 4.6.0 on Windows is what the run of record used (`docs/session\\\_info.txt`).
Any recent R will do, but renv restores the exact package versions only if the R version matches.

**2. Restore the packages first, from a terminal, before opening the project in RStudio.** Copy the
folder to a path without special characters, open a terminal in it (in Windows Explorer: type `cmd` in
the address bar and press Enter), and run:

```
Rscript -e "renv::restore(prompt = FALSE)"
```

About 11 seconds from a warm renv cache, some minutes if the packages have to come from CRAN.

**Do this before opening the .Rproj, not after.** On a fresh clone the project library is empty, so
`.Rprofile` makes renv bootstrap and restore itself while the R session is starting. From a terminal
that is fine. Inside RStudio it happens during the session-startup window, and RStudio can give up
first and report "The R session failed to start" or "Cannot connect to R". Restoring first means
`.Rprofile` finds a library that is already there and returns straight away.

**3. Open the project.** File > Open Project > `MAF900\\\_Assignment2\\\_Niklas\\\_Ziemann.Rproj` in RStudio.
The Console should report the project folder as the working directory. Opening the `.Rproj` is what
makes `here()` resolve every path, so please do not `setwd()` anywhere.

**If `renv::restore()` fails, stalls, or starts compiling things, you can skip it entirely.** Run the
following in the same terminal, or in the RStudio Console once the project is open. The
lockfile pins R 4.6.0, so on an older R some of the pinned versions have to be built from source,
and on Windows that needs Rtools. None of that is necessary to run the project. Turn renv off and
install the packages the ordinary way:

```
renv::deactivate()
install.packages(c("tidyverse", "here", "readxl", "DBI", "dbplyr", "RPostgres", "modelsummary"))
```

Those seven are every package the scripts load, so this gets you to the same place.

**4. The WRDS password file** (the unit's Topic 2 supporting page, "R - WRDS Connection"). You need a
WRDS account whose subscription includes Compustat Global and LSEG ESG Scores V2, **with database
access**, not web-query access alone. Create the folder

```
C:\\\\Users\\\\<you>\\\\AppData\\\\Roaming\\\\postgresql
```

if it does not exist, and inside it a plain-text file named exactly `pgpass.conf` holding **one
line, with no spaces and no quotation marks**:

```
wrds-pgdata.wharton.upenn.edu:9737:wrds:<your\\\_wrds\\\_username>:<your\\\_wrds\\\_password>
```

The five fields are host, port, database, user name, password, separated by colons. Save it with
Notepad, not Word, and make sure Windows has not appended `.txt` to the name. On macOS or Linux the
file is `\\\~/.pgpass` with the same single line, and it must be `chmod 600`. Nothing else in the
project needs the password, and no script contains one.

**5. `config.csv`.** Copy `config\\\_example.csv` to `config.csv` and put your WRDS user name in the
`wrds\\\_username` row. `config.csv` is git-ignored, which is where the user name and any local path
belong (Lecture 2, slide 13).

**6. Run the pipeline.** Open `code/run\\\_all.R` and click Source, or run the ten scripts one at a
time in numerical order with **Source with Echo** (`Ctrl+Shift+Enter`). About 15 minutes with the
WRDS pull, of which 05 is three to five minutes and the throttled register download in 01 is the
rest when the files are not already on disk; about 80 seconds for 01 to 09 with 05 skipped and the
raw files in place. The plain "Source" button runs a script silently, so nothing appears in the
Console even though the files are written; that is why `run\\\_all.R` uses `echo = TRUE`.

What each script writes:

|Script|Writes|
|-|-|
|01|`data/raw/nger/` (17 register files)|
|02|`data/processed/nger\\\_panel.csv`|
|03|`data/raw/asx/asx\\\_directory.csv` (a copy of the snapshot, or of today's download)|
|03b|`data/raw/rba/` (two Excel files), `data/processed/aud\\\_usd\\\_month\\\_end.csv`|
|04|`data/processed/nger\\\_asx\\\_matched.csv`|
|05|`data/raw/wrds/` (three licensed extracts), `data/processed/emitter\\\_securities.csv`, `asx\\\_security\\\_master.csv`|
|06|`data/processed/firm\\\_year\\\_variables.csv`, `lseg\\\_flag\\\_firm\\\_year.csv`; tables a, b, c, f; `fig\\\_a`, `fig\\\_2`, `fig\\\_c`|
|07|`data/processed/monthly\\\_returns.csv`, `tercile\\\_panel.csv`; Table 1; `figure1\\\_average.csv`, `figure1\\\_by\\\_release\\\_year.csv`; `fig\\\_1`|
|08|`output/tables/table\\\_2\\\_terciles.csv` and its companions|
|09|`output/tables/table\\\_e\\\_hand\\\_check.csv`, `figure3b\\\_by\\\_firm.csv`; `fig\\\_3`, `fig\\\_3b`|
|run\_all.R|`docs/session\\\_info.txt` (it overwrites the committed copy with your own session)|

**7. Check the counts** against "What to expect" below. Every script prints the counts it produces
as it goes, so a mismatch shows up at the script that caused it rather than at the end.

### If something does not work

* **Nothing appears in the Console.** The scripts print by naming the object on its own line, which
only shows when you run lines one at a time (`Ctrl+Enter`) or use **Source with Echo**
(`Ctrl+Shift+Enter`). The plain Source button runs silently and the files are still written.
`run\\\_all.R` uses `echo = TRUE` for this reason.
* **`could not connect` in script 05.** The password file is missing, misnamed, or Windows has added
`.txt` to it. Check the path and that it is called exactly `pgpass.conf`. Check the internet too.
* **`there is no package called ...`.** `renv::restore()` was skipped. If renv itself gives trouble,
`renv::deactivate()` then install the packages normally.
* **`cannot open file 'data/raw/nger/...'` in 02.** Run 01 first.
* **429 errors in 01.** The regulator's site is rate-limiting. Wait a minute and run 01 again; it
continues where it stopped.
* **Script 03 fails.** Only possible if the committed snapshot is missing and the ASX blocked the
download. Put `asx\\\_directory\\\_2026-09-03.csv` back in `data/raw/asx/` and run 03 again.
* **Script 05 writes its files only at the very end**, and the Environment pane keeps showing the
`wrds` connection object after `dbDisconnect()`. Both are normal.

## What to expect (run of 10 September 2026)

|Script|Output|Count|
|-|-|-|
|02|`nger\\\_panel.csv`|6,664 corporation-years (233 in 2008-09 to 398 in 2024-25)|
|03|reads `asx\\\_directory\\\_2026-09-03.csv`|1,834 listed companies on 3 September 2026|
|03b|`aud\\\_usd\\\_month\\\_end.csv`|686 months, July 1969 to August 2026; the rand series covers 59 of them|
|04|`nger\\\_asx\\\_matched.csv`|97 renames bridged through the register's own identifier; 1,268 firm-years of 117 companies are in today's ASX directory (this is not yet the sample: 06 decides)|
|05|`asx\\\_security\\\_master.csv`, `emitter\\\_securities.csv`, `g\\\_secd\\\_au.csv`, `g\\\_funda\\\_au.csv`, `lseg\\\_esg\\\_au.csv`|4,092 ASX lines in Australian dollars since July 2008; 192 price lines linked to 183 register corporations (94 through the ISIN, 98 by name); three companies in today's directory have no ASX line in Compustat at all (Alcoa, Newmont, News Corp, whose ASX securities are CDIs of US parents); 674,447 daily rows on 218 lines; 2,438 fundamentals rows (2,234 AUD, 166 USD, 18 NZD, 16 GBP, 4 ZAR); 21,933 LSEG rows|
|06|`firm\\\_year\\\_variables.csv`, `lseg\\\_flag\\\_firm\\\_year.csv`; tables a, b, c and f; figures a, 2, c|1,615 listed firm-years of 183 companies (1,031 linked by ISIN, 584 by name), 63 in 2008-09 rising to 108 in 2018-19 and 94 in 2024-25; 1,594 with a June market cap, 1,414 with an intensity; listed reporters hold 20 per cent of register Scope 1 in 2008-09 and 38 per cent in 2024-25; 859 Reported firm-years in the register-vendor comparison, median gap +2.6 per cent; 81 emitters in the 2023-24 cross-section|
|07|`monthly\\\_returns.csv`, `tercile\\\_panel.csv`, Table 1 (`table\\\_1\\\_sample\\\_by\\\_year.csv`), Figure 1|186 companies and 218 months of returns; 17 release years, 17 to 32 firms per tercile in every one of them; high minus low cumulative return +1.0 per cent at month 0 and +10.1 per cent at month +12 (all years), +3.8 and +11.8 per cent (2016-17 onward)|
|08|`table\\\_2\\\_terciles.csv` and companions|1,414 firm-years, 1,352 with a 6-month return and 1,251 with a 12-month return; no release year has fewer than 10 firms in a tercile, so Panel B is identical to Panel A|
|09|`table\\\_e\\\_hand\\\_check.csv`, `figure3b\\\_by\\\_firm.csv`, Figure 3 and Appendix Figure A1|ten firms, eight with a comparable Scope 1 figure, all ten with a publication date, nine with both a date and prices|

## What a re-run will and will not reproduce

The register files, the RBA files, the ASX snapshot and the hand-collected CSV are committed, so
scripts 01 to 04 reproduce the counts above exactly. Two things can still move between runs:

* **The LSEG snapshot.** The vendor overwrites a value when it revises it, and each value carries a
date, so a later pull can change the register-versus-vendor counts and the flag split. Two of the
ten hand-checked firms already carry value dates in 2026 for their FY2024 figure.
* **Compustat revisions.** Prices, shares outstanding and fundamentals are restated occasionally.

Script 03 says in its own output which of the two paths it took. If the committed snapshot is
missing it downloads today's directory instead, and then 03's row count moves (1,834 on 3 September
2026 against whatever is listed today) and the key-collision table changes. 04's headline counts are
robust to that: they were still 1,268 firm-years of 117 companies, and still 97 renames, a week
later, because only `market\\\_cap\\\_today` and the collision tie-break depend on the day. So, a matching
1,268 / 117 is not by itself evidence that the committed snapshot was used. The line script 03 prints
is what actually says which file it read.

## What cannot be reproduced from the code alone

* The WRDS pulls need a subscription to Compustat Global and LSEG ESG. The scripts and
`docs/wrds\\\_query\\\_specs.md` say exactly what to pull, and `wrds\\\_query\\\_specs.md` also gives the
web-form route for a login without database access.
* The hand-collected CSV is a transcription. Every row carries the document, its URL, the page and
the printed string, so every figure in it can be checked against the source.
* The exact packages are pinned in `renv.lock`; the run of 10 September used R 4.6.0 on Windows
(`docs/session\\\_info.txt`).

## How this repository follows the unit's conventions

Lecture 2, slides 12 and 13, in their order.

1. **Automation.** Nothing is done by hand except the ten-row transcription in
`data/hand\\\_collected/`, which no script can recreate and which records its source page by page.
Every download, clean, join, table and figure is in `code/`.
2. **Organisation.** One directory per stage: `data/raw`, `data/processed`, `code`, `docs`,
`output`. The structure block above is the map.
3. **Documentation: README.** This file: what the project is, where the data comes from, how to
reproduce every step, what to expect, and what a re-run will not reproduce.
4. **Documentation: comments.** Every script opens with what it reads and what it writes, and each
numbered step inside it carries a comment explaining why the step is there, rather than restating
what the code does.
5. **Documentation: data dictionary.** `docs/data\\\_dictionary.md`, every raw and processed column,
plus the exhibit map from each table and figure back to the file and script that made it.
6. **Do not commit the output.** `output/tables/` and `output/figures/` are git-ignored, and so is
`data/processed/`; only `.gitkeep` markers are tracked, so a clone has the folders and rebuilds
their contents. The data and the code that generate the output are what is committed.
7. **Commit in small chunks.** The repository is committed one stage of the pipeline at a
time, and no commit mixes code with data from a different stage.
8. **renv.** `renv.lock` pins R 4.6.0 and every package the scripts load; `.Rprofile` and
`renv/activate.R` make a clone restore them with one command.
9. **Sensitive data in a config file plus .gitignore.** The WRDS user name lives in `config.csv`,
which is git-ignored; `config\\\_example.csv` is the committed template. The password is never in
the project at all: it lives in the Postgres `pgpass.conf` described in step 4 above. The
licensed WRDS extracts are git-ignored for the same reason.
10. **The whole pipeline.** Raw data (`data/raw`, scripts 01 to 05) to processed data
(`data/processed`, scripts 02 to 06) to analysis (`output/tables`, `output/figures`, scripts 06
to 09) to report (the CloudDeakin submission, which cites the file behind every number).

## Judgement calls

`docs/DECISIONS.md` lists the decisions that change a number, each with the alternative and its
measured effect where one was measured. The largest: the name-key strip list (D1); the two-route link from a corporation to its price lines (D4); converting the foreign-currency reporters instead of dropping them (D7); and the t-test that treats each release year as one observation; (D15) the sample: definition, rebuilt on the day before submission when the register's own identifiers showed how much a directory-only match was losing (D22 to D25).

