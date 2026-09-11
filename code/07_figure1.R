# 07. Figure 1 of the proposal: cumulative return of the high-minus-low emissions-intensity tercile
#     around the February publication of the NGER register
#
# The register for reporting year t (ended 30 June t) is published by 28 February of year t+1.
# Event month 0 is that February. For every reporting year the listed emitters are sorted into
# terciles of emissions intensity (Scope 1 + 2 per A$ million revenue); the equal-weighted monthly
# return of the top tercile minus the bottom tercile is cumulated from month -6 to month +12.
# Flat after month 0 supports H1 (availability); continued drift supports H2 (processing cost).
# This is descriptive: no test, no risk adjustment.

library(tidyverse)
library(here)

firm_year_variables <- read_csv(here("data", "processed", "firm_year_variables.csv"))   # script 06
secd_au             <- read_csv(here("data", "raw", "wrds", "g_secd_au.csv"))            # script 05

# 1. Monthly total returns from the daily prices
#    total return index = prccd / ajexdi * trfd (price, adjusted for splits, with dividends reinvested)
monthly <- secd_au |>
  filter(!is.na(prccd), !is.na(trfd)) |>
  mutate(tri = prccd / ajexdi * trfd,
         month = floor_date(datadate, "month")) |>
  group_by(gvkey, iid, month) |>
  slice_max(datadate, n = 1) |>            # last trading day of the month
  ungroup() |>
  arrange(gvkey, iid, month) |>
  group_by(gvkey, iid) |>
  mutate(ret = tri / lag(tri) - 1) |>
  ungroup() |>
  filter(!is.na(ret)) |>
  select(gvkey, iid, month, ret)

monthly |> summarise(firms = n_distinct(gvkey), months = n_distinct(month), first = min(month), last = max(month))
write_csv(monthly, here("data", "processed", "monthly_returns.csv"))

# 2. Emissions intensity for every listed emitter and reporting year (script 06), terciles within the year
terciles <- firm_year_variables |>
  filter(!is.na(intensity)) |>             # needs revenue for the year, and revenue above zero
  group_by(fy) |>
  filter(n() >= 12) |>                     # at least four firms per tercile
  mutate(tercile = ntile(intensity, 3)) |>
  ungroup() |>
  select(fy, end_year, asx_code, corporation, gvkey, iid, intensity, tercile)

tercile_counts <- terciles |> count(fy, tercile) |> pivot_wider(names_from = tercile, values_from = n, names_prefix = "tercile_")
tercile_counts
write_csv(tercile_counts, here("output", "tables", "figure1_tercile_counts.csv"))
write_csv(terciles, here("data", "processed", "tercile_panel.csv"))

# Table 1 of the report: the sample by reporting year, from the register to the terciles.
# A firm is listed in a reporting year when its Compustat price line traded during that year (script 06).
table_1 <- read_csv(here("output", "tables", "table_a_sample_by_year.csv")) |>
  left_join(read_csv(here("output", "tables", "table_c_reported_share_by_year.csv")), by = "fy") |>
  left_join(tercile_counts |> mutate(sorted_into_terciles = tercile_1 + tercile_2 + tercile_3) |>
              select(fy, sorted_into_terciles), by = "fy") |>
  select(fy, reporters, listed_reporters, listed_share_of_scope1,
         with_vendor_value = with_flag, reported_share, sorted_into_terciles)
table_1
write_csv(table_1, here("output", "tables", "table_1_sample_by_year.csv"))

# 3. Event time: months relative to the February after the reporting year
panel <- terciles |>
  mutate(event_month0 = ymd(paste0(end_year + 1, "-02-01"))) |>
  inner_join(monthly, by = c("gvkey", "iid"), relationship = "many-to-many") |>
  mutate(event_time = (year(month) - year(event_month0)) * 12 + month(month) - month(event_month0)) |>
  filter(event_time >= -6, event_time <= 12)

# 4. Equal-weighted tercile portfolios, high minus low, cumulated within each release year
portfolio <- panel |>
  group_by(fy, event_time, tercile) |>
  summarise(ret = mean(ret), firms = n(), .groups = "drop")

spread <- portfolio |>
  select(-firms) |>
  pivot_wider(names_from = tercile, values_from = ret, names_prefix = "tercile_") |>
  mutate(high_minus_low = tercile_3 - tercile_1) |>
  arrange(fy, event_time) |>
  group_by(fy) |>
  mutate(cumulative = cumsum(high_minus_low)) |>
  ungroup()

# 5. Average across release years: all years with prices, and the window named in the proposal (2016-17 onward)
figure1 <- bind_rows(
  spread |> mutate(sample = "All release years"),
  spread |> filter(fy >= "2016-17") |> mutate(sample = "Proposal window, 2016-17 onward")) |>
  group_by(sample, event_time) |>
  summarise(mean_cumulative = mean(cumulative), release_years = n(), .groups = "drop")
figure1 |> pivot_wider(names_from = sample, values_from = c(mean_cumulative, release_years))

write_csv(spread,  here("output", "tables", "figure1_by_release_year.csv"))
write_csv(figure1, here("output", "tables", "figure1_average.csv"))

# 6. The figure: one grey line per release year, the two averages in colour, publication month dashed
ggplot() +
  geom_line(data = spread, aes(x = event_time, y = cumulative, group = fy), colour = "grey75") +
  geom_line(data = figure1, aes(x = event_time, y = mean_cumulative, colour = sample, linetype = sample), linewidth = 1.2) +
  geom_hline(yintercept = 0) +
  geom_vline(xintercept = 0, linetype = "dotted") +
  scale_x_continuous(breaks = seq(-6, 12, 2)) +
  scale_y_continuous(labels = scales::percent) +
  ggtitle("Figure 1: cumulative return of the high-minus-low intensity tercile") +
  labs(x = "Months relative to the February publication of the register (month 0)",
       y = "Cumulative return, top minus bottom tercile",
       colour = "Average over", linetype = "Average over",
       caption = paste0("Grey: one line per release year (", min(spread$fy), " to ", max(spread$fy),
                        "). Equal-weighted terciles, no risk adjustment, no test.")) +
  theme(legend.position = "bottom")
# Saved at the width it is printed in the report (16 cm), so the axis text stays readable on paper
ggsave(here("output", "figures", "fig_1_february_publication.png"), width = 6.5, height = 3.9)
