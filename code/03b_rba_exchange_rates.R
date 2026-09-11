# 03b. Download the exchange rate history from the Reserve Bank of Australia (statistical table F11)
#
# Some listed emitters report their accounts in US dollars (BHP, Woodside, South32, Santos, Fortescue
# and others), in pounds (Greatland), in New Zealand dollars (Fletcher Building) or in rand (AngloGold
# Ashanti until 2011). Their revenue and book equity are converted to Australian dollars at the
# end-of-month rate of their financial year end (script 06).
# The RBA publishes the series as two Excel files: 1969 to 2009, and 2010 to today.

library(tidyverse)
library(readxl)
library(here)

# 1. Download both files into data/raw/rba (kept, like the other raw downloads)
urls <- c("https://www.rba.gov.au/statistics/tables/xls-hist/f11hist-1969-2009.xls",
          "https://www.rba.gov.au/statistics/tables/xls-hist/f11hist.xls")

for (url in urls) {
  file <- here("data", "raw", "rba", basename(url))
  if (!file.exists(file)) download.file(url, file, mode = "wb")
}

# 2. Read them: the first ten rows describe the series, row 11 holds the series identifiers
#    (FXRUSD is A$1 in USD, FXRUKPS in GBP, FXRNZD in NZD, FXRSARD in rand), the data start in row 12
exchange_rates <- tibble()
for (url in urls) {
  one_file <- read_excel(here("data", "raw", "rba", basename(url)), skip = 10) |>
    select(date = `Series ID`, any_of(c(aud_usd = "FXRUSD", aud_gbp = "FXRUKPS",
                                        aud_nzd = "FXRNZD", aud_zar = "FXRSARD")))
  exchange_rates <- bind_rows(exchange_rates, one_file)
}

exchange_rates <- exchange_rates |>
  mutate(date = as.Date(date), across(c(aud_usd, aud_gbp, aud_nzd, aud_zar), as.numeric)) |>
  filter(!is.na(date), !is.na(aud_usd)) |>
  mutate(month = floor_date(date, "month")) |>
  arrange(date)

exchange_rates |> summarise(first = min(date), last = max(date), months = n())
exchange_rates |> filter(month(date) == 6, year(date) %in% c(2009, 2015, 2024))    # a few known year-end rates

# 3. Save
write_csv(exchange_rates, here("data", "processed", "aud_usd_month_end.csv"))
