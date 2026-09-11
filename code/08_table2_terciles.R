# 08. The tercile comparison the proposal called Table 1 (Table 2 of the report): the emissions-intensity
#     terciles compared on returns, volatility, size, book-to-market and turnover, with the mean of the
#     yearly high-minus-low differences, a t-test and a Wilcoxon test
#
# Inputs (all produced by the earlier scripts):
#   data/processed/tercile_panel.csv         one row per listed emitter and release year, with its tercile (script 07)
#   data/processed/monthly_returns.csv       monthly total returns (script 07)
#   data/processed/firm_year_variables.csv   market cap at 30 June, book equity in A$, the vendor flag (script 06)
#   data/raw/wrds/g_secd_au.csv              daily shares traded and shares outstanding, for turnover (script 05)
# Outputs: output/tables/table_2_terciles.csv, table_2_by_release_year.csv, table_2_firm_year_counts.csv,
#          table_d_flag_split.csv; data/processed/table2_firm_years.csv

library(tidyverse)
library(here)
library(modelsummary)

terciles            <- read_csv(here("data", "processed", "tercile_panel.csv"))
monthly             <- read_csv(here("data", "processed", "monthly_returns.csv"))
firm_year_variables <- read_csv(here("data", "processed", "firm_year_variables.csv"))
secd_au             <- read_csv(here("data", "raw", "wrds", "g_secd_au.csv"))

# ---------------------------------------------------------------------------------------------
# 1. Event time, as in script 07: months relative to the February after the reporting year
# ---------------------------------------------------------------------------------------------
panel <- terciles |>
  mutate(event_month0 = ymd(paste0(end_year + 1, "-02-01"))) |>
  inner_join(monthly, by = c("gvkey", "iid"), relationship = "many-to-many") |>
  mutate(event_time = (year(month) - year(event_month0)) * 12 + month(month) - month(event_month0))

# ---------------------------------------------------------------------------------------------
# 2. Returns after the release (months +1 to +6 and +1 to +12, compounded) and volatility before it
#    (months -12 to -1). A firm needs the full window: the last release (February 2026) has no
#    12-month window yet, so it appears in the 6-month column only.
# ---------------------------------------------------------------------------------------------
returns <- panel |>
  group_by(fy, end_year, asx_code, corporation, gvkey, iid, intensity, tercile) |>
  summarise(months_post6  = sum(event_time >= 1 & event_time <= 6),
            months_post12 = sum(event_time >= 1 & event_time <= 12),
            months_pre12  = sum(event_time >= -12 & event_time <= -1),
            ret_post6  = prod(1 + ret[event_time >= 1 & event_time <= 6]) - 1,
            ret_post12 = prod(1 + ret[event_time >= 1 & event_time <= 12]) - 1,
            vol_pre12  = sd(ret[event_time >= -12 & event_time <= -1]),
            .groups = "drop") |>
  mutate(ret_post6  = replace(ret_post6,  months_post6  < 6,  NA),
         ret_post12 = replace(ret_post12, months_post12 < 12, NA),
         vol_pre12  = replace(vol_pre12,  months_pre12  < 12, NA))

# ---------------------------------------------------------------------------------------------
# 3. Size at 30 June of the reporting year and book-to-market (script 06), and turnover in the
#    12 months before the release (shares traded over shares outstanding, daily, averaged)
# ---------------------------------------------------------------------------------------------
turnover_month <- secd_au |>
  filter(!is.na(cshtrd), !is.na(cshoc), cshoc > 0) |>
  mutate(month = floor_date(datadate, "month"), turnover = cshtrd / cshoc) |>
  group_by(gvkey, iid, month) |>
  summarise(turnover = mean(turnover), .groups = "drop")

turnover_pre12 <- terciles |>
  mutate(event_month0 = ymd(paste0(end_year + 1, "-02-01"))) |>
  inner_join(turnover_month, by = c("gvkey", "iid"), relationship = "many-to-many") |>
  mutate(event_time = (year(month) - year(event_month0)) * 12 + month(month) - month(event_month0)) |>
  filter(event_time >= -12, event_time <= -1) |>
  group_by(fy, gvkey, iid) |>
  summarise(turnover_pre12 = mean(turnover), .groups = "drop")

firm_years <- returns |>
  left_join(firm_year_variables |> select(fy, gvkey, iid, market_cap, ceq), by = c("fy", "gvkey", "iid")) |>
  left_join(turnover_pre12, by = c("fy", "gvkey", "iid")) |>
  mutate(log_market_cap = log(market_cap),
         book_to_market = ceq * 1e6 / market_cap,                    # ceq is in A$ million, market cap in A$
         book_to_market = replace(book_to_market, market_cap == 0, NA)) |>
  select(fy, end_year, asx_code, corporation, gvkey, iid, tercile, intensity, ret_post6, ret_post12, vol_pre12,
         market_cap, log_market_cap, book_to_market, turnover_pre12)

firm_years |> count(fy, tercile) |> pivot_wider(names_from = tercile, values_from = n, names_prefix = "tercile_")
firm_years |> summarise(across(c(ret_post6, ret_post12, vol_pre12, log_market_cap, book_to_market, turnover_pre12),
                               ~ sum(!is.na(.x))))
write_csv(firm_years, here("data", "processed", "table2_firm_years.csv"))

# Summary statistics of the firm-year variables (Topic 4: datasummary_skim)
datasummary_skim(firm_years |> select(intensity, ret_post6, ret_post12, vol_pre12, log_market_cap, book_to_market, turnover_pre12))

# ---------------------------------------------------------------------------------------------
# 4. Three samples: every release year with prices; the years with at least 10 firms per tercile;
#    and the window named in the proposal (2016-17 onward)
# ---------------------------------------------------------------------------------------------
thin_years <- firm_years |>
  count(fy, tercile) |>
  group_by(fy) |>
  summarise(smallest_tercile = min(n)) |>
  filter(smallest_tercile < 10) |>
  pull(fy)
thin_years

samples <- bind_rows(
  firm_years |> mutate(sample = "A. All release years"),
  firm_years |> filter(!fy %in% thin_years) |> mutate(sample = "B. Release years with 10 or more firms per tercile"),
  firm_years |> filter(fy >= "2016-17") |> mutate(sample = "C. Proposal window, 2016-17 onward"))

variables <- c("intensity", "ret_post6", "ret_post12", "vol_pre12", "log_market_cap", "book_to_market", "turnover_pre12")

long <- samples |>
  select(sample, fy, asx_code, tercile, all_of(variables)) |>
  pivot_longer(all_of(variables), names_to = "variable", values_to = "value") |>
  filter(!is.na(value)) |>
  mutate(variable = factor(variable, levels = variables))

# ---------------------------------------------------------------------------------------------
# 5. The comparison. Means by tercile; the high-minus-low difference; a t-test that treats each
#    release year as one observation (all firms in a release year share the same date and move
#    together, so the number of independent observations is the number of release dates, not the
#    number of firms); and a Wilcoxon rank-sum test on the firm-years, as in Table 2 of the proposal.
# ---------------------------------------------------------------------------------------------
by_tercile <- long |>
  group_by(sample, variable, tercile) |>
  summarise(n = n(), mean = mean(value), median = median(value), .groups = "drop")

by_year <- long |>
  filter(tercile %in% c(1, 3)) |>
  group_by(sample, variable, fy, tercile) |>
  summarise(mean = mean(value), .groups = "drop") |>
  pivot_wider(names_from = tercile, values_from = mean, names_prefix = "tercile_") |>
  mutate(high_minus_low = tercile_3 - tercile_1)

t_by_year <- by_year |>
  group_by(sample, variable) |>
  summarise(release_years = n(),
            difference = mean(high_minus_low),
            t_stat = t.test(high_minus_low)$statistic,
            p_t = t.test(high_minus_low)$p.value,
            .groups = "drop")

t_firm_level <- long |>
  filter(tercile %in% c(1, 3)) |>
  group_by(sample, variable) |>
  summarise(t_stat_firm_level = t.test(value ~ tercile)$statistic * -1,       # t.test orders 1 then 3: flip the sign to high minus low
            wilcoxon_p = wilcox.test(value ~ tercile)$p.value,
            .groups = "drop")

table2 <- by_tercile |>
  select(sample, variable, tercile, mean, median) |>
  pivot_wider(names_from = tercile, values_from = c(mean, median), names_glue = "{.value}_tercile_{tercile}") |>
  left_join(by_tercile |> filter(tercile == 1) |> select(sample, variable, n_low = n), by = c("sample", "variable")) |>
  left_join(by_tercile |> filter(tercile == 3) |> select(sample, variable, n_high = n), by = c("sample", "variable")) |>
  left_join(t_by_year, by = c("sample", "variable")) |>
  left_join(t_firm_level, by = c("sample", "variable")) |>
  arrange(sample, variable)
table2 |> print(n = Inf, width = Inf)

write_csv(table2,  here("output", "tables", "table_2_terciles.csv"))

# The largest 12-month returns in the high tercile, and the pooled high-minus-low gap with and
# without the five largest: how much of the mean gap is a handful of firm-years
top_returns <- firm_years |>
  filter(tercile == 3, !is.na(ret_post12)) |>
  arrange(desc(ret_post12)) |>
  select(fy, asx_code, corporation, ret_post12, market_cap) |>       # a delisted company can have no code: the name says who it is
  head(10)
top_returns
pooled_gap <- firm_years |>
  filter(!is.na(ret_post12), tercile %in% c(1, 3)) |>
  mutate(top_five = tercile == 3 & ret_post12 >= sort(ret_post12[tercile == 3], decreasing = TRUE)[5]) |>
  summarise(pooled_gap = mean(ret_post12[tercile == 3]) - mean(ret_post12[tercile == 1]),
            pooled_gap_without_top_five = mean(ret_post12[tercile == 3 & !top_five]) - mean(ret_post12[tercile == 1]))
pooled_gap
write_csv(top_returns, here("output", "tables", "table_2_top_returns.csv"))
write_csv(pooled_gap,  here("output", "tables", "table_2_pooled_gap.csv"))
write_csv(by_year, here("output", "tables", "table_2_by_release_year.csv"))
firm_years |> count(fy, tercile) |> write_csv(here("output", "tables", "table_2_firm_year_counts.csv"))

# ---------------------------------------------------------------------------------------------
# 6. The vendor flag (hypothesis 2): return after the release by tercile and by whether the vendor
#    carries the firm's own reported value. Counts and means only: the "Estimated" cells are too
#    small for a test, and the flag is a disclosure-quality sort as much as a measurement channel.
# ---------------------------------------------------------------------------------------------
flag_split <- firm_years |>
  left_join(firm_year_variables |> select(fy, gvkey, iid, flag), by = c("fy", "gvkey", "iid")) |>
  mutate(flag = replace_na(flag, "No vendor value")) |>
  group_by(flag, tercile) |>
  summarise(firm_years = n(),
            mean_ret_post12 = mean(ret_post12, na.rm = TRUE),
            median_ret_post12 = median(ret_post12, na.rm = TRUE),
            .groups = "drop")
flag_split
write_csv(flag_split, here("output", "tables", "table_d_flag_split.csv"))
