# 01. Download the NGER corporate emissions and energy data
#
# Source: Clean Energy Regulator, "Corporate emissions and energy data" (one page per reporting year)
#         https://cer.gov.au/markets/reports-and-data/nger-reporting-data-and-registers
# Licence: Creative Commons Attribution 4.0 (CC BY 4.0)
# One CSV per reporting year, 2008-09 to 2024-25. The list of URLs is in docs/nger_urls.csv.

library(tidyverse)
library(here)

# 1. The list of files to download
nger_urls <- read_csv(here("docs", "nger_urls.csv"))
nger_urls

# 2. Download each file into data/raw/nger
#    The CER website answers HTTP 429 ("too many requests") if we download too fast,
#    so we wait 20 seconds between files. Files already on disk are not downloaded again.
for (i in 1:nrow(nger_urls)) {
  destfile <- here("data", "raw", "nger", nger_urls$file[i])
  if (!file.exists(destfile)) {
    download.file(url = nger_urls$url[i], destfile = destfile, mode = "wb")
    Sys.sleep(20)
  }
}

# 3. Check what we have: 17 files, one per reporting year
list.files(here("data", "raw", "nger"))

# 4. Look at the first rows of the latest file
read_csv(here("data", "raw", "nger", "nger_2024-25.csv"), n_max = 5)
