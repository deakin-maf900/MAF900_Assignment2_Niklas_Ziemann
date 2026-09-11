# 06. First analysis: the sample, the register versus the vendor, and a first look at the emitters
#
# Inputs (all produced by the earlier scripts):
#   data/processed/nger_asx_matched.csv     register panel with the name key and today's ASX codes (script 04)
#   data/processed/aud_usd_month_end.csv    RBA end-of-month AUD/USD and AUD/GBP rates (script 03b)
#   data/processed/emitter_securities.csv   the Compustat price lines of the register corporations (script 05)
#   data/raw/wrds/g_secd_au.csv             Compustat Global daily prices, AUD lines on the ASX (script 05)
#   data/raw/wrds/g_funda_au.csv            Compustat Global fundamentals (script 05)
#   data/raw/wrds/lseg_esg_au.csv           LSEG ESG emissions fields and the reported/estimated flag (script 05)
# Outputs: data/processed/firm_year_variables.csv and lseg_flag_firm_year.csv (used by scripts 07 to 09);
#          tables in output/tables, figures in output/figures

library(tidyverse)
library(here)
library(modelsummary)

nger_asx           <- read_csv(here("data", "processed", "nger_asx_matched.csv"))
aud_usd            <- read_csv(here("data", "processed", "aud_usd_month_end.csv"))
emitter_securities <- read_csv(here("data", "processed", "emitter_securities.csv"))
secd_au            <- read_csv(here("data", "raw", "wrds", "g_secd_au.csv"))
funda_au           <- read_csv(here("data", "raw", "wrds", "g_funda_au.csv"))
lseg_au            <- read_csv(here("data", "raw", "wrds", "lseg_esg_au.csv"))

# ---------------------------------------------------------------------------------------------
# 1. The listed emitters: a register row is "listed" in a reporting year (1 July to 30 June) when one
#    of the corporation's Compustat price lines traded during that year. A company that has delisted
#    since keeps its earlier years, one that listed later enters when it lists, and one that changed
#    its name is one company (script 04). Where two lines overlap a year, the busier one is used.
# ---------------------------------------------------------------------------------------------
listed_rows <- nger_asx |>
  mutate(fy_start = ymd(paste0(str_sub(fy, 1, 4), "-07-01")),
         fy_end   = ymd(paste0(as.numeric(str_sub(fy, 1, 4)) + 1, "-06-30"))) |>
  inner_join(emitter_securities |>
               select(name_key, asx_code_line = asx_code, gvkey, iid, isin, trading_days, first_day, last_day, link),
             by = "name_key", relationship = "many-to-many") |>
  filter(first_day <= fy_end, last_day >= fy_start) |>
  group_by(fy, name_key) |>
  slice_max(trading_days, n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(fy, name_key, asx_code_line, gvkey, iid, isin, link)

nger_asx <- nger_asx |>
  left_join(listed_rows, by = c("fy", "name_key")) |>
  mutate(listed = !is.na(gvkey),
         asx_code = coalesce(asx_code, asx_code_line)) |>       # delisted companies: the code their ISIN embeds
  select(-asx_code_line)

nger_asx |> count(fy, listed) |> pivot_wider(names_from = listed, values_from = n)
nger_asx |> filter(listed) |> summarise(firm_years = n(), firms = n_distinct(name_key))
nger_asx |> filter(listed) |> count(link)
nger_asx |> filter(in_directory, !listed) |> count(fy)               # in today's directory but not yet listed that year

# The sample by reporting year: NGER reporters and listed reporters
sample_by_year <- nger_asx |>
  group_by(fy) |>
  summarise(reporters = n(),
            listed_reporters = sum(listed),
            scope1_Mt = sum(scope1, na.rm = TRUE) / 1e6,
            listed_scope1_Mt = sum(scope1 * listed, na.rm = TRUE) / 1e6) |>
  mutate(listed_share_of_scope1 = listed_scope1_Mt / scope1_Mt)
sample_by_year
write_csv(sample_by_year, here("output", "tables", "table_a_sample_by_year.csv"))

sample_by_year |>
  pivot_longer(c(reporters, listed_reporters), names_to = "group", values_to = "n") |>
  mutate(group = if_else(group == "reporters", "All register reporters", "ASX-listed reporters")) |>
  ggplot(aes(x = fy, y = n, fill = group)) +
  geom_col(position = "dodge") +
  ggtitle("NGER reporting corporations and ASX-listed reporters, by reporting year") +
  labs(x = "Reporting year", y = "Number of corporations", fill = "Corporations") +
  theme(axis.text.x = element_text(angle = 90))
ggsave(here("output", "figures", "fig_a_reporters_by_year.png"), width = 9, height = 4.5)

# ---------------------------------------------------------------------------------------------
# 2. Firm-year variables: market cap at 30 June, revenue and book equity in A$, emissions intensity
#    NGER reporting year 2023-24 ends on 30 June 2024, so its "end year" is 2024.
#    Some emitters report in US dollars (BHP, Woodside, South32, Santos, Fortescue, ...), pounds
#    (Greatland), New Zealand dollars (Fletcher Building) or rand (AngloGold Ashanti until 2011):
#    converted at the RBA end-of-month rate of their year end (script 03b).
#    A firm that changed its year end has two fundamentals rows in one calendar year: the one
#    closest to 30 June is kept.
# ---------------------------------------------------------------------------------------------
market_cap_june <- secd_au |>
  filter(month(datadate) == 6, !is.na(prccd), !is.na(cshoc)) |>
  mutate(end_year = year(datadate), market_cap = prccd * cshoc) |>
  group_by(gvkey, iid, end_year) |>
  slice_max(datadate, n = 1) |>
  ungroup() |>
  select(gvkey, iid, end_year, market_cap)

funda_au |> count(curcd)                                                   # the reporting currencies in the extract
fundamentals <- funda_au |>
  filter(curcd %in% c("AUD", "USD", "GBP", "NZD", "ZAR")) |>
  mutate(end_year = year(datadate), month = floor_date(datadate, "month")) |>
  left_join(aud_usd |> select(month, aud_usd, aud_gbp, aud_nzd, aud_zar), by = "month") |>
  mutate(to_aud = case_when(curcd == "USD" ~ 1 / aud_usd,            # A$1 = 0.65 USD means USD 1 = A$ 1 / 0.65
                            curcd == "GBP" ~ 1 / aud_gbp,            # Greatland Resources reports in pounds
                            curcd == "NZD" ~ 1 / aud_nzd,            # Fletcher Building reports in New Zealand dollars
                            curcd == "ZAR" ~ 1 / aud_zar,            # AngloGold Ashanti reported in rand until 2011
                            .default = 1),
         revt = revt * to_aud, ceq = ceq * to_aud, at = at * to_aud) |>
  group_by(gvkey, end_year) |>
  slice_min(abs(month(datadate) - 6), n = 1, with_ties = FALSE) |>
  ungroup() |>
  select(gvkey, end_year, datadate, curcd, to_aud, revt, ceq, at)
fundamentals |> count(curcd)
fundamentals |> filter(is.na(to_aud))                                      # the RBA files carry no rand rate before 2010: AngloGold's 2008 and 2009 rows stay without one

emitters <- nger_asx |>
  filter(listed) |>
  mutate(end_year = as.numeric(str_sub(fy, 1, 4)) + 1) |>
  left_join(market_cap_june, by = c("gvkey", "iid", "end_year")) |>
  left_join(fundamentals, by = c("gvkey", "end_year")) |>
  mutate(intensity = scope12 / revt,                       # t CO2-e per A$ million of revenue
         intensity = replace(intensity, revt == 0, NA))    # revenue can be zero: no ratio then

emitters |> count(fy, has_price = !is.na(market_cap), has_revenue = !is.na(revt))

# ---------------------------------------------------------------------------------------------
# 3. Register versus vendor: does LSEG carry the same Scope 1 number as the regulator?
#    LSEG labels a June year-end 2024 as year 2024, the same "end year" as above. The vendor's rows
#    are joined to the price line by ISIN.
# ---------------------------------------------------------------------------------------------
# The vendor files one row per field, firm and year, but a few (firm, year, field) triples appear
# twice. The first row is kept; both counts are printed so the drop is visible.
lseg_au |> filter(fieldid %in% c(89, 95, 97)) |> summarise(rows = n())
lseg_au |> filter(fieldid %in% c(89, 95, 97)) |> distinct(isin, year, fieldname) |> summarise(rows_after_distinct = n())

lseg_wide <- lseg_au |>
  filter(fieldid %in% c(89, 95, 97)) |>          # 89 flag, 95 Scope 1, 97 Scope 2
  distinct(isin, year, fieldname, .keep_all = TRUE) |>
  select(isin, end_year = year, fieldname, value) |>
  pivot_wider(names_from = fieldname, values_from = value) |>
  rename(method = AnalyticCO2EstimationMethod,
         lseg_scope1 = CO2EquivalentsEmissionDirectScope1,
         lseg_scope2 = CO2EquivalentsEmissionIndirectScope2) |>
  mutate(across(c(lseg_scope1, lseg_scope2), as.numeric),
         flag = if_else(method == "Reported", "Reported", "Estimated"))
lseg_wide |> count(method, flag)                      # the raw labels behind the two-way flag
write_csv(lseg_wide, here("data", "processed", "lseg_flag_firm_year.csv"))

# One row per listed emitter and reporting year with everything scripts 07 to 09 need
firm_year_variables <- emitters |>
  left_join(lseg_wide, by = c("isin", "end_year")) |>
  select(fy, end_year, name_key, corporation, asx_code, company_name, gics_industry_group, gvkey, iid, isin, link,
         scope1, scope2, scope12, market_cap, revt, ceq, at, curcd, to_aud, intensity, method, flag, lseg_scope1, lseg_scope2)
write_csv(firm_year_variables, here("data", "processed", "firm_year_variables.csv"))

wedge <- firm_year_variables |>
  filter(!is.na(lseg_scope1), scope1 > 0) |>
  mutate(gap_pct = 100 * (lseg_scope1 - scope1) / scope1)

wedge_summary <- wedge |>
  group_by(flag) |>
  summarise(firm_years = n(),
            firms = n_distinct(name_key),
            median_gap_pct = median(gap_pct),
            within_5pct = mean(abs(gap_pct) <= 5),
            within_25pct = mean(abs(gap_pct) <= 25))
wedge_summary
write_csv(wedge_summary, here("output", "tables", "table_b_register_vs_vendor.csv"))

wedge |>
  mutate(flag = replace_na(flag, "No flag")) |>
  ggplot(aes(x = scope1, y = lseg_scope1, colour = flag)) +
  geom_point(alpha = 0.7) +
  geom_abline(slope = 1, intercept = 0, linetype = "dashed") +
  geom_text(data = wedge |> filter(fy == "2023-24", abs(gap_pct) > 100),      # name the largest gaps of the latest year
            aes(label = asx_code), colour = "black", size = 3, vjust = -0.8, check_overlap = TRUE) +
  scale_x_log10(labels = scales::label_comma()) + scale_y_log10(labels = scales::label_comma()) +
  ggtitle("Figure 2: Scope 1 emissions, NGER register versus LSEG ESG, same firm and year") +
  labs(x = "NGER register, t CO2-e (log scale)", y = "LSEG ESG, t CO2-e (log scale)",
       colour = "LSEG value is",
       caption = "Every listed emitter and year with both values (2008-09 to 2024-25). Dashed line: equal values. Labels: 2023-24 gaps above 100 per cent.") +
  theme(legend.position = "bottom")
ggsave(here("output", "figures", "fig_2_register_vs_vendor.png"), width = 8, height = 6)

# Share of listed emitters whose vendor value is flagged "Reported", by reporting year
reported_by_year <- firm_year_variables |>
  group_by(fy) |>
  summarise(emitters = n(),
            with_flag = sum(!is.na(flag)),
            reported = sum(flag == "Reported", na.rm = TRUE),
            reported_share = reported / with_flag)
reported_by_year
write_csv(reported_by_year, here("output", "tables", "table_c_reported_share_by_year.csv"))

# ---------------------------------------------------------------------------------------------
# 4. A first cross-section: listed emitters of 2023-24 sorted into emissions-intensity terciles
# ---------------------------------------------------------------------------------------------
emitters_2024 <- emitters |>
  filter(fy == "2023-24", !is.na(intensity), !is.na(market_cap)) |>
  mutate(tercile = ntile(intensity, 3),
         tercile = factor(tercile, labels = c("Low", "Mid", "High")))

datasummary_skim(emitters_2024 |> select(scope12, intensity, market_cap, revt))

table1 <- emitters_2024 |>
  group_by(tercile) |>
  summarise(n = n(),
            across(c(intensity, scope12, market_cap, revt),
                   list(Mean = ~ mean(.x, na.rm = TRUE), Median = ~ median(.x, na.rm = TRUE)),
                   .names = "{col}_{fn}"))
table1
write_csv(table1, here("output", "tables", "table_f_terciles_2023-24.csv"))

# ---------------------------------------------------------------------------------------------
# 5. Cross-section: emissions against size, by sector (the industry group comes from today's
#    directory, so a company that has delisted since carries none and is drawn as NA). Twenty-four
#    GICS industry groups are too many to read off a legend, so the seven most common are kept and
#    the rest are collected into one class (Lecture 4: coarser sector groupings).
# ---------------------------------------------------------------------------------------------
emitters_2024 |>
  mutate(industry = fct_lump_n(gics_industry_group, n = 7, other_level = "Other industry groups")) |>
  ggplot(aes(x = market_cap / 1e6, y = scope12, colour = industry)) +
  geom_point(size = 2) +
  scale_x_log10(labels = scales::comma) + scale_y_log10(labels = scales::comma) +
  ggtitle("ASX-listed NGER reporters, 2023-24: emissions against market capitalisation") +
  labs(x = "Market capitalisation at 30 June 2024, A$ million (log scale)",
       y = "Scope 1 + 2 emissions, t CO2-e (log scale)",
       colour = "Industry group")
ggsave(here("output", "figures", "fig_c_emissions_vs_size_2024.png"), width = 10, height = 6)
