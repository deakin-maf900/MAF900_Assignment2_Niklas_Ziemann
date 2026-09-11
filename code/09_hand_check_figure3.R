# 09. The hand-collected subsample: the ten largest listed emitters' own FY2024 reports against the
#     register and the vendor, and Figure 3 (when each firm's Scope 1 figure became public, by channel,
#     and the firm's return around its own report)
#
# Inputs:
#   data/hand_collected/firm_reports_fy2024.csv   transcribed by hand from the firms' own reports: value,
#                                                 page, publication date, URL (see docs/data_dictionary.md)
#   data/processed/nger_asx_matched.csv           the register values and today's ASX codes (script 04)
#   data/processed/lseg_flag_firm_year.csv        the vendor values and flag (script 06)
#   data/raw/wrds/lseg_esg_au.csv                 the vendor's value dates (script 05)
#   data/processed/firm_year_variables.csv        gvkey and iid of each emitter (script 06)
#   data/processed/monthly_returns.csv            monthly total returns (script 07)
# Outputs: output/tables/table_e_hand_check.csv, figure3b_by_firm.csv;
#          output/figures/fig_3_report_dates.png, fig_3b_returns_around_report.png

library(tidyverse)
library(here)

hand_check <- read_csv(here("data", "hand_collected", "firm_reports_fy2024.csv"))
nger_asx   <- read_csv(here("data", "processed", "nger_asx_matched.csv"))
lseg_flag  <- read_csv(here("data", "processed", "lseg_flag_firm_year.csv"))
lseg_au    <- read_csv(here("data", "raw", "wrds", "lseg_esg_au.csv"))
firm_years <- read_csv(here("data", "processed", "firm_year_variables.csv"))
monthly    <- read_csv(here("data", "processed", "monthly_returns.csv"))

hand_check |> select(asx_code, report_title, period_covered, publication_date, page, scope1_as_printed, boundary, confidence)

# ---------------------------------------------------------------------------------------------
# 1. The three values side by side: the firm's own report, the register, the vendor.
#    Reporting year 2023-24 is vendor year 2024; the register was due on 28 February 2025.
# ---------------------------------------------------------------------------------------------
register <- nger_asx |>
  filter(fy == "2023-24", !is.na(asx_code)) |>
  select(asx_code, register_scope1 = scope1, register_scope2 = scope2) |>
  left_join(firm_years |> filter(fy == "2023-24") |> select(asx_code, isin), by = "asx_code")   # the ISIN of the price line, for the vendor join

vendor <- lseg_flag |>
  filter(end_year == 2024) |>
  select(isin, vendor_scope1 = lseg_scope1, vendor_flag = flag)

# A firm can carry more than one Scope 1 row for 2024; the first is kept and both counts are
# printed so the drop is visible.
lseg_au |> filter(fieldid == 95, year == 2024) |> summarise(rows = n())

vendor_dates <- lseg_au |>
  filter(fieldid == 95, year == 2024) |>                       # 95 = Scope 1
  distinct(isin, .keep_all = TRUE) |>
  select(isin, vendor_value_date = valuedate)
nrow(vendor_dates)                                             # rows left after one per firm

comparison <- hand_check |>
  left_join(register, by = "asx_code") |>
  left_join(vendor, by = "isin") |>
  left_join(vendor_dates, by = "isin") |>
  mutate(register_date = ymd("2025-02-28"),
         report_vs_register_pct = 100 * (scope1_t - register_scope1) / register_scope1,
         vendor_vs_register_pct = 100 * (vendor_scope1 - register_scope1) / register_scope1,
         days_report_before_register = as.numeric(register_date - publication_date),
         days_vendor_after_report = as.numeric(vendor_value_date - publication_date))

comparison |>
  select(asx_code, publication_date, boundary, scope1_t, register_scope1, vendor_scope1,
         report_vs_register_pct, vendor_vs_register_pct, vendor_value_date, days_report_before_register) |>
  print(width = Inf)
write_csv(comparison, here("output", "tables", "table_e_hand_check.csv"))

# ---------------------------------------------------------------------------------------------
# 2. Figure 3: the day the FY2023-24 Scope 1 figure became public in each channel, firm by firm
# ---------------------------------------------------------------------------------------------
timeline <- comparison |>
  select(asx_code,
         `Firm's own report` = publication_date,
         `NGER register` = register_date,
         `Vendor (LSEG)` = vendor_value_date) |>
  pivot_longer(-asx_code, names_to = "channel", values_to = "date") |>
  filter(!is.na(date))

ggplot(timeline, aes(x = date, y = fct_rev(asx_code), colour = channel, shape = channel)) +
  geom_point(size = 3) +
  scale_x_date(date_breaks = "6 months", date_labels = "%b %Y") +
  ggtitle("Figure 3: when ten large emitters' FY2023-24 Scope 1 became public") +
  labs(x = "Date", y = "ASX code", colour = "Channel", shape = "Channel",
       caption = "Own report: hand-collected date. Register: statutory deadline. Vendor: LSEG value date.") +
  theme(legend.position = "bottom")
# Saved at the width it is printed in the report (16 cm), so the axis text stays readable on paper
ggsave(here("output", "figures", "fig_3_report_dates.png"), width = 6.5, height = 3.6)

# ---------------------------------------------------------------------------------------------
# 3. Returns around each firm's own report: the firm's monthly return minus the equal-weighted
#    average of all listed emitters, cumulated from three months before to six months after the
#    month of publication. Ten firms in one year: descriptive only.
# ---------------------------------------------------------------------------------------------
all_emitters <- monthly |>
  group_by(month) |>
  summarise(ret_all = mean(ret), firms = n(), .groups = "drop")

around_report <- comparison |>
  filter(!is.na(publication_date)) |>
  inner_join(firm_years |> filter(fy == "2023-24") |> select(asx_code, gvkey, iid), by = "asx_code") |>
  mutate(report_month = floor_date(publication_date, "month")) |>
  inner_join(monthly, by = c("gvkey", "iid"), relationship = "many-to-many") |>
  inner_join(all_emitters, by = "month") |>
  mutate(event_time = (year(month) - year(report_month)) * 12 + month(month) - month(report_month),
         excess = ret - ret_all) |>
  filter(event_time >= -3, event_time <= 6) |>
  arrange(asx_code, event_time) |>
  group_by(asx_code) |>
  mutate(cumulative = cumsum(excess)) |>
  ungroup() |>
  select(asx_code, publication_date, month, event_time, ret, ret_all, excess, cumulative)

figure3b <- around_report |>
  group_by(event_time) |>
  summarise(mean_cumulative = mean(cumulative), firms = n(), .groups = "drop")
figure3b
write_csv(around_report, here("output", "tables", "figure3b_by_firm.csv"))

ggplot() +
  geom_line(data = around_report, aes(x = event_time, y = cumulative, group = asx_code), colour = "grey70") +
  geom_line(data = figure3b, aes(x = event_time, y = mean_cumulative), linewidth = 1.2) +
  geom_hline(yintercept = 0) +
  geom_vline(xintercept = 0, linetype = "dotted") +
  scale_x_continuous(breaks = -3:6) +
  scale_y_continuous(labels = scales::percent, breaks = seq(-1, 1, 0.1)) +   # labels below zero as well: a third of the panel is negative
  ggtitle("Appendix Figure A1: excess return around the firm's own FY2024 report") +
  labs(x = "Months relative to the month the report was published (month 0)",
       y = "Cumulative excess return",
       caption = "Grey: one line per firm. Black: average. Firms in Compustat only. Descriptive, no test.")
# Saved at the width it is printed in the report (16 cm), so the axis text stays readable on paper
ggsave(here("output", "figures", "fig_3b_returns_around_report.png"), width = 6.5, height = 3.6)
