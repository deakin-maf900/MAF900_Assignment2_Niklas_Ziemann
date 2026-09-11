# 04. Match NGER corporations to ASX-listed companies by name
#
# The register has no ticker or ISIN, only the legal name (and an ABN from 2013-14). Two lists of
# listed companies are matched by the same "name key": today's ASX directory here (script 03), and
# Compustat's security file in script 05, which also knows the companies that have delisted since.
# The key removes legal suffixes (PTY, LTD, LIMITED, ...) and filler words (GROUP, HOLDINGS,
# AUSTRALIA, CORPORATION, THE) so that "Stockland Corporation Ltd" and "STOCKLAND" become the same key.

library(tidyverse)
library(here)

nger_panel    <- read_csv(here("data", "processed", "nger_panel.csv"))
asx_directory <- read_csv(here("data", "raw", "asx", "asx_directory.csv")) |>
  mutate(`Market Cap` = parse_number(`Market Cap`),          # comes in as text
         `Listing date` = dmy(`Listing date`))

# 1. The words we remove from a company name before matching (CORP, HLDGS and GRP are Compustat's abbreviations)
strip_words <- c("PTY", "PROPRIETARY", "LTD", "LIMITED", "LIMITEDS", "INC", "INCORPORATED",
                 "PLC", "NL", "LLC", "LP", "CORP", "HLDGS", "GRP",
                 "GROUP", "HOLDINGS", "AUSTRALIA", "AUSTRALIAN", "AUST", "CORPORATION", "THE")
strip_pattern <- paste0("\\b(", paste(strip_words, collapse = "|"), ")\\b")

# 2. The name key, step by step
#    a) drop footnote digits the CER glued onto some names in 2009-10 ("Boral Limited2")
#    b) drop "trading as" / "formerly" clauses
#    c) upper case, letters and digits only
#    d) remove the strip words, fix one known CER spelling drift, squeeze spaces
nger_panel <- nger_panel |>
  mutate(name_key = corporation |>
           iconv(from = "UTF-8", to = "ASCII//TRANSLIT") |>
           str_remove("(?<=[A-Za-z])\\d{1,2}$") |>
           str_remove(regex("\\s*\\(?\\s*(T/A|TRADING AS|FORMERLY|PREVIOUSLY).*$", ignore_case = TRUE)) |>
           str_to_upper() |>
           str_replace_all("[^A-Z0-9 ]", " ") |>
           str_remove_all(strip_pattern) |>
           str_replace_all("MILLENIUM", "MILLENNIUM") |>
           str_squish())

asx_directory <- asx_directory |>
  mutate(name_key = `Company name` |>
           iconv(from = "UTF-8", to = "ASCII//TRANSLIT") |>
           str_to_upper() |>
           str_replace_all("[^A-Z0-9 ]", " ") |>
           str_remove_all(strip_pattern) |>
           str_replace_all("MILLENIUM", "MILLENNIUM") |>
           str_squish()) |>
  filter(name_key != "")

# 3. A company that changes its name keeps its ABN: BHP Billiton became BHP Group in 2018, Woodside
#    Petroleum became Woodside Energy in 2022, Caltex became Ampol in 2020. Today's lists know only
#    the new name, so every row of an ABN takes the key of its latest name, and the rows before
#    2013-14 (the files carry no ABN) take the latest key of the same old name.
#    The last nine digits of the ABN are the ACN, which is what a few files give instead.
nger_panel <- nger_panel |>
  mutate(abn_key = str_sub(str_remove_all(abn, "[^0-9]"), -9),
         abn_key = if_else(str_length(abn_key) == 9, abn_key, NA))

latest_key <- nger_panel |>
  filter(!is.na(abn_key)) |>
  group_by(abn_key) |>
  slice_max(fy, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(abn_key, latest_key = name_key)

renamed <- nger_panel |>
  filter(!is.na(abn_key)) |>
  left_join(latest_key, by = "abn_key") |>
  filter(name_key != latest_key) |>
  distinct(name_key, latest_key)
renamed |> print(n = Inf)                                   # old name key -> current name key
message("Old name keys that point at two current names (this table should be empty):")
renamed |> count(name_key) |> filter(n > 1)
renamed <- renamed |> distinct(name_key, .keep_all = TRUE)

nger_panel <- nger_panel |>
  left_join(renamed, by = "name_key") |>
  mutate(name_key = coalesce(latest_key, name_key)) |>
  select(-latest_key)

# 4. Two ASX lines can share a key (for example NWS and NWSLV). Keep the larger company.
asx_directory |> group_by(name_key) |> filter(n() > 1) |> arrange(name_key)
asx_directory |> summarise(lines = n(), no_market_cap = sum(is.na(`Market Cap`)))   # a line with no market cap sorts last, so it never wins a collision
asx_directory <- asx_directory |>
  arrange(desc(`Market Cap`)) |>
  distinct(name_key, .keep_all = TRUE)
nrow(asx_directory)                                          # lines left after one per name key

# 5. Join: every NGER row keeps its data, rows whose company is in today's directory get the ASX code.
#    Whether a company was listed in a given year is decided in script 06 from its price line, so a
#    company that has delisted since, or listed later, is handled there.
nger_asx <- nger_panel |>
  left_join(asx_directory |>
              select(name_key, asx_code = `ASX code`, company_name = `Company name`,
                     gics_industry_group = `GICs industry group`,
                     listing_date = `Listing date`, market_cap_today = `Market Cap`),
            by = "name_key") |>
  mutate(in_directory = !is.na(asx_code))

# 6. How many are in today's directory?
nger_asx |> count(fy, in_directory) |> pivot_wider(names_from = in_directory, values_from = n)
nger_asx |> filter(in_directory) |> summarise(firm_years = n(), firms = n_distinct(asx_code))

# 7. The largest emitters of the latest year that are in the directory
nger_asx |>
  filter(in_directory, fy == "2024-25") |>
  arrange(desc(scope1)) |>
  select(asx_code, company_name, gics_industry_group, scope1, scope2) |>
  head(15)

# 8. Save
write_csv(nger_asx, here("data", "processed", "nger_asx_matched.csv"))
