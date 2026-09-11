# Run the whole pipeline in order: raw data -> processed data -> analysis -> tables and figures
# Open MAF900_Assignment2_Niklas_Ziemann.Rproj in RStudio first, so that here() points at the project folder.
# echo = TRUE makes each script print its code and its results in the console
# (a plain source() runs silently; so does RStudio's "Source" button. Use "Source with Echo",
#  Ctrl+Shift+Enter, when running a single script by hand.)

library(here)

source(here("code", "01_download_nger.R"), echo = TRUE)          # public data: Clean Energy Regulator (17 files, 20 s apart)
source(here("code", "02_parse_nger.R"), echo = TRUE)             # tidy panel, one row per corporation and reporting year
source(here("code", "03_asx_directory.R"), echo = TRUE)          # public data: ASX listed companies (today's snapshot)
source(here("code", "03b_rba_exchange_rates.R"), echo = TRUE)    # public data: RBA end-of-month AUD/USD
source(here("code", "04_match_nger_asx.R"), echo = TRUE)         # name match register -> ASX code

source(here("code", "05_wrds_pull.R"), echo = TRUE)              # WRDS (licensed): live from the database with your login

source(here("code", "06_first_analysis.R"), echo = TRUE)         # firm-year variables; sample table; register versus vendor; Table 1
source(here("code", "07_figure1.R"), echo = TRUE)                # monthly returns, terciles, Figure 1
source(here("code", "08_table2_terciles.R"), echo = TRUE)        # Table 2: terciles compared, with tests
source(here("code", "09_hand_check_figure3.R"), echo = TRUE)     # hand-collected reports; Figure 3

# Record the session for the reproducibility note in the README. This OVERWRITES the committed
# docs/session_info.txt with your own R and package versions, which is the point: it says what
# actually ran on your machine. Restore it from git if you would rather keep the run of record.
writeLines(capture.output(sessionInfo()), here("docs", "session_info.txt"))

# Look at a result outside R: opens the CSV in Excel
# shell.exec(here("data", "processed", "nger_asx_matched.csv"))
