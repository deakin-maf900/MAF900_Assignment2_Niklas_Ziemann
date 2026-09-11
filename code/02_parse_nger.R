# 02. Parse the 17 NGER files into one tidy panel (one row = one corporation in one reporting year)
#
# The CER changed its column names over the years, for example:
#   2008-09  "Registered Corporations", "Total scope 1 greenhouse gas emissions (t CO2-e)", ...
#   2013-14  "Controlling Corporation ", "ABN", "Total Scope 1 Emissions (t CO2-e)", ...
#   2019-20  "Organisation name", "Identifying details", "Total scope 1 emissions (t CO2-e)", ...
# so we select the columns by what their names contain, not by their exact names.
# Numbers are stored as text with thousands separators ("122,169"), so we use parse_number().
# The files are not all in the same text encoding either (three are Windows-1252, the rest UTF-8),
# so docs/nger_urls.csv records the encoding of each file and read_csv() is told which one to use.

library(tidyverse)
library(here)

nger_urls <- read_csv(here("docs", "nger_urls.csv"))

# 1. Read every file, keep the five columns we need, add the reporting year
nger_panel <- tibble()
for (i in 1:nrow(nger_urls)) {
  one_year <- read_csv(here("data", "raw", "nger", nger_urls$file[i]),
                       col_types = cols(.default = "c"),
                       locale = locale(encoding = nger_urls$encoding[i])) |>
    select(corporation = 1,
           abn = matches("ABN|Identifying"),
           scope1 = matches("cope 1 |cope 1$"),
           scope2 = matches("cope 2 |cope 2$"),
           energy = matches("nergy")) |>
    mutate(fy = nger_urls$fy[i])
  nger_panel <- bind_rows(nger_panel, one_year)
}

# 2. Clean the values: numbers, ABN without spaces, no empty rows
nger_panel <- nger_panel |>
  filter(!is.na(corporation)) |>
  filter(!(is.na(scope1) & is.na(scope2))) |>            # a few rows carry a name and no numbers
  mutate(corporation = str_squish(corporation),          # stray spaces in some names
         across(c(scope1, scope2, energy), parse_number),
         abn = str_remove_all(abn, " "),
         scope12 = scope1 + scope2) |>
  select(fy, corporation, abn, scope1, scope2, scope12, energy)

# 3. Inspect: reporters per year, and the biggest emitters in the latest year
nger_panel |> count(fy)
nger_panel |> filter(fy == "2024-25") |> arrange(desc(scope1)) |> head(10)
glimpse(nger_panel)

# 4. Save the panel
write_csv(nger_panel, here("data", "processed", "nger_panel.csv"))
