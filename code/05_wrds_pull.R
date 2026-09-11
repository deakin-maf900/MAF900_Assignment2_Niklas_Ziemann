# 05. Collect the WRDS data: Compustat Global (prices, fundamentals) and LSEG ESG (emissions, flag)
#
# WRDS data is licensed: it is downloaded with your own WRDS login and is never committed to the
# repository (data/raw/wrds is in .gitignore). The password is not in this file either. It sits in
# the Postgres password file, which R reads automatically:
#   C:\Users\<your user name>\AppData\Roaming\postgresql\pgpass.conf
# containing one line:
#   wrds-pgdata.wharton.upenn.edu:9737:wrds:<wrds_username>:<wrds_password>
# (see the unit page "R - WRDS Connection" under Topic 2)
#
# The register has no ticker or ISIN. The chain is: NGER name -> name key (script 04) -> a Compustat
# price line (this script), either through the ASX code that an old-format Australian ISIN embeds
# (AU000000BHP4 -> BHP) or through the same name key on Compustat's company name.

library(tidyverse)
library(DBI)
library(dbplyr)
library(RPostgres)
library(here)

# 1. Connect to the WRDS database. The user name is read from config.csv (git-ignored);
#    the password comes from pgpass.conf (see above), so neither is in the code.
config <- read_csv(here("config.csv"))
wrds_username <- config |> filter(setting == "wrds_username") |> pull(value)

wrds <- dbConnect(Postgres(),
                  host = "wrds-pgdata.wharton.upenn.edu",
                  port = 9737,
                  dbname = "wrds",
                  sslmode = "require",
                  user = wrds_username)

# 2. Explore before coding: the libraries (schemas) and tables we use
#    Compustat Global daily prices:        comp_global_daily.g_secd
#    Compustat Global fundamentals annual: comp_global_daily.g_funda
#    LSEG ESG (V2 LSEG ESG Scores):        tr_esg.wrds_ref_esg  (one row per company, year and field)
#    LSEG ESG field list:                  tr_esg.wrds_ref_esg_item
dbListFields(wrds, Id(schema = "comp_global_daily", table = "g_secd"))
dbListFields(wrds, Id(schema = "tr_esg", table = "wrds_ref_esg"))
tbl(wrds, in_schema("tr_esg", "wrds_ref_esg_item")) |>
  filter(item %in% c(64, 89, 95, 96, 97, 98)) |>
  select(item, feedfieldname, title) |>
  collect()

# 3. Security master: every security on the ASX (exchange 106) with an AUD price line, with the
#    first and last day it traded. Prices start on 1 July 2008, the first day of the first NGER
#    reporting year, so that every register release (February 2010 onwards) has returns before and
#    after it. The exchange and the currency define an ASX line; the country code (fic) is not used:
#    Rio Tinto Limited, an Australian company on the ASX, was missing from a master that also
#    required fic == "AUS".
secd_remote <- tbl(wrds, in_schema("comp_global_daily", "g_secd"))

security_master <- secd_remote |>
  filter(curcdd == "AUD", exchg == 106, datadate >= "2008-07-01") |>
  group_by(gvkey, iid, isin, sedol, conm) |>
  summarise(trading_days = n(), first_day = min(datadate, na.rm = TRUE), last_day = max(datadate, na.rm = TRUE), .groups = "drop") |>
  collect() |>
  mutate(asx_code = str_remove(str_sub(isin, 3, 11), "^0+"))     # AU000000BHP4 -> BHP
nrow(security_master)
write_csv(security_master, here("data", "processed", "asx_security_master.csv"))

# 4. Which register corporations can we find in Compustat? One row per corporation (script 04's
#    name key), with the years it appears in the register.
corporations <- read_csv(here("data", "processed", "nger_asx_matched.csv")) |>
  group_by(name_key) |>
  summarise(asx_code = first(asx_code),
            corporation = last(corporation),
            span_start = ymd(paste0(min(str_sub(fy, 1, 4)), "-07-01")),
            span_end = ymd(paste0(as.numeric(max(str_sub(fy, 1, 4))) + 1, "-06-30")),
            .groups = "drop")

#    (a) Corporations in today's directory have an ASX code, and an old-format Australian ISIN
#        embeds it. Codes get reused after a delisting (SGH was Slater & Gordon until 2020 and is
#        Seven Group since 2024; WDS was WDS Limited until 2016 and is Woodside since 2022), so only
#        lines that traded in the last year of the extract are linked this way.
current_lines <- security_master |>
  filter(last_day >= max(last_day) - 365)

by_isin <- corporations |>
  filter(!is.na(asx_code)) |>
  inner_join(current_lines, by = "asx_code") |>
  group_by(name_key) |>
  slice_max(trading_days, n = 1, with_ties = FALSE) |>       # one price line per company
  ungroup() |>
  mutate(link = "isin")
nrow(by_isin)

#    (b) Every corporation left over is matched by name to any line that traded while it was in the
#        register: companies that have delisted since (Boral, Newcrest, CSR), companies with a numeric
#        ISIN (Coles, Ampol), and every name a corporation has filed under (a company acquired after it
#        delisted can carry its buyer's name in the latest years, as Coca-Cola Amatil does). The key is
#        stricter than script 04's: Compustat's abbreviations are written out, legal suffixes and the
#        word AUSTRALIA are removed, but GROUP, HOLDINGS and CORPORATION stay, so that the private
#        HRL Limited does not land on the listed HRL Holdings. A company that relisted keeps both
#        lines; script 06 takes, for each year, the line that traded then. Compustat cuts names at
#        28 characters, so a few long names do not match.
abbreviations <- c("\\bCORP\\b" = "CORPORATION", "\\bHLDGS\\b" = "HOLDINGS", "\\bGRP\\b" = "GROUP",
                   "\\bINTL\\b" = "INTERNATIONAL", "\\bSVC\\b" = "SERVICES")
suffix_pattern <- "\\b(PTY|PROPRIETARY|LTD|LIMITED|LIMITEDS|INC|INCORPORATED|PLC|NL|LLC|LP|AUSTRALIA|AUSTRALIAN|AUST|THE)\\b"

corporation_names <- read_csv(here("data", "processed", "nger_asx_matched.csv")) |>
  distinct(name_key, name_filed = corporation) |>
  mutate(strict_key = name_filed |>
           iconv(to = "ASCII//TRANSLIT") |>
           str_remove("(?<=[A-Za-z])\\d{1,2}$") |>
           str_remove(regex("\\s*\\(?\\s*(T/A|TRADING AS|FORMERLY|PREVIOUSLY).*$", ignore_case = TRUE)) |>
           str_to_upper() |>
           str_replace_all("[^A-Z0-9 ]", " ") |>
           str_replace_all(abbreviations) |>
           str_remove_all(suffix_pattern) |>
           str_squish())

security_master <- security_master |>
  mutate(strict_key = conm |>
           iconv(to = "ASCII//TRANSLIT") |>
           str_to_upper() |>
           str_replace_all("[^A-Z0-9 ]", " ") |>
           str_replace_all(abbreviations) |>
           str_remove_all(suffix_pattern) |>
           str_squish())

by_name <- corporations |>
  anti_join(by_isin, by = "name_key") |>
  inner_join(corporation_names, by = "name_key") |>
  inner_join(security_master |> rename(asx_code_line = asx_code), by = "strict_key", relationship = "many-to-many") |>
  filter(first_day <= span_end, last_day >= span_start) |>
  distinct(name_key, gvkey, iid, .keep_all = TRUE) |>
  mutate(asx_code = coalesce(asx_code, asx_code_line), link = "name") |>
  select(-asx_code_line, -name_filed, -strict_key)
by_name |> summarise(corporations = n_distinct(name_key), lines = n())
by_name |> count(name_key) |> filter(n > 1)                          # more than one line: a relisting or a second class of shares
by_name |> filter(last_day < max(security_master$last_day) - 365) |> distinct(name_key, conm, first_day, last_day)   # the delisted ones

emitter_securities <- bind_rows(by_isin, by_name) |>
  select(name_key, corporation, asx_code, gvkey, iid, isin, sedol, conm, trading_days, first_day, last_day, link)
emitter_securities |> count(link)
corporations |> filter(!is.na(asx_code)) |> anti_join(emitter_securities, by = "name_key")   # in today's directory but no price line

write_csv(emitter_securities, here("data", "processed", "emitter_securities.csv"))

# 5. Daily prices for those lines only (a few hundred thousand rows, not millions)
secd_au <- secd_remote |>
  filter(gvkey %in% !!emitter_securities$gvkey, iid %in% !!emitter_securities$iid,
         curcdd == "AUD", exchg == 106, datadate >= "2008-07-01") |>
  select(gvkey, iid, datadate, conm, isin, sedol, prccd, ajexdi, trfd, cshoc, cshtrd) |>
  collect()
nrow(secd_au)

# 6. Fundamentals annual for the same companies: revenue, assets, equity
funda_au <- tbl(wrds, in_schema("comp_global_daily", "g_funda")) |>
  filter(gvkey %in% !!emitter_securities$gvkey,
         datafmt == "HIST_STD", consol == "C", indfmt == "INDL", datadate >= "2008-07-01") |>
  select(gvkey, datadate, fyear, conm, isin, sedol, curcd, revt, at, ceq, costat) |>
  collect()
nrow(funda_au)

# 7. LSEG ESG for Australian companies: the reported-versus-estimated flag and the emissions fields
#    64 ESGPeriodLastUpdateDate, 89 AnalyticCO2EstimationMethod, 95 Scope 1, 97 Scope 2,
#    96 Scope 3, 98 total
lseg_au <- tbl(wrds, in_schema("tr_esg", "wrds_ref_esg")) |>
  filter(substr(isin, 1, 2) == "AU", fieldid %in% c(64, 89, 95, 96, 97, 98)) |>
  select(orgpermid, year, isin, ticker, comname, fieldid, fieldname, valuedate, value) |>
  collect()
nrow(lseg_au)

# 8. Save the downloads as CSV (in data/raw/wrds, which git ignores) and note the download date
write_csv(secd_au,  here("data", "raw", "wrds", "g_secd_au.csv"))
write_csv(funda_au, here("data", "raw", "wrds", "g_funda_au.csv"))
write_csv(lseg_au,  here("data", "raw", "wrds", "lseg_esg_au.csv"))
today()

dbDisconnect(wrds)
