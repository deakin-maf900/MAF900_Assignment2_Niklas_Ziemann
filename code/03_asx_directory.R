# 03. Download the ASX directory of listed companies
#
# Source: ASX "Listed companies directory", the CSV download behind
#         https://www.asx.com.au/markets/trade-our-cash-market/directory
# Columns: ASX code, Company name, GICs industry group, Listing date, Market Cap
# This is a snapshot of who is listed TODAY (no history), so we keep the download date.

library(tidyverse)
library(here)

# 1. Download, unless the snapshot the report used (3 September 2026, committed with the project) is
#    on disk: then that file is read, so a re-run reproduces the same match. Delete it to download a
#    fresh directory, which is saved with its date in the file name.
#    The access token in the URL is the public one on the ASX website's directory page, not a credential.
asx_url <- "https://asx.api.markitdigital.com/asx-research/1.0/companies/directory/file?access_token=83ff96335c2d45a094df02a206a39ff4"
snapshot <- here("data", "raw", "asx", "asx_directory_2026-09-03.csv")

if (file.exists(snapshot)) {
  message("Reading the committed snapshot: ", basename(snapshot))
  asx_directory <- read_csv(snapshot)
} else {
  message("No committed snapshot found: downloading today's directory from asx.api.markitdigital.com")
  asx_directory <- read_csv(asx_url)
  write_csv(asx_directory, here("data", "raw", "asx", paste0("asx_directory_", today(), ".csv")))
}

# 2. Inspect
glimpse(asx_directory)
nrow(asx_directory)

# 3. Save under a fixed name for the next script
write_csv(asx_directory, here("data", "raw", "asx", "asx_directory.csv"))
