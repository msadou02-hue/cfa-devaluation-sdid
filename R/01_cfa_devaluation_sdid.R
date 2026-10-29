# Effect of the January 1994 CFA franc devaluation on real GDP growth,
# estimated with DiD, Synthetic Control and Synthetic Difference-in-Differences
# (Arkhangelsky, Athey, Hirshberg, Imbens & Wager, 2021).
#
# Run from the repository root:  Rscript R/01_cfa_devaluation_sdid.R

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(pwt10)
  library(synthdid)
})

set.seed(1994)
dir.create("figures", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

# ---------------------------------------------------------------------------
# 1. Sample definition
# ---------------------------------------------------------------------------
# ISO-3 codes are used instead of country names: PWT spells several names
# differently (e.g. "Côte d'Ivoire", "Congo"), which silently drops countries
# when matching on names.
cfa_iso <- c(
  # WAEMU (West Africa)
  "BEN", "BFA", "CIV", "GNB", "MLI", "NER", "SEN", "TGO",
  # CEMAC (Central Africa)
  "CMR", "CAF", "TCD", "COG", "GNQ", "GAB"
)
# Neighbouring non-CFA economies in West and Central Africa
control_iso <- c("GHA", "NGA", "LBR", "SLE", "GIN", "COD", "AGO", "GMB", "MRT")

first_year <- 1985
last_year  <- 2000
treat_year <- 1994   # devaluation took effect on 12 January 1994

data("pwt10.0")

df <- pwt10.0 %>%
  filter(isocode %in% c(cfa_iso, control_iso),
         year >= first_year, year <= last_year) %>%
  transmute(iso = as.character(isocode), country = as.character(country),
            year, rgdpna) %>%
  arrange(iso, year) %>%
  group_by(iso) %>%
  mutate(gdp_growth = 100 * (log(rgdpna) - log(lag(rgdpna)))) %>%
  ungroup() %>%
  filter(!is.na(gdp_growth)) %>%
  mutate(cfa = iso %in% cfa_iso,
         treated = as.integer(cfa & year >= treat_year))

# synthdid needs a balanced panel: keep countries observed in every year.
n_years <- n_distinct(df$year)
balanced <- df %>% group_by(iso) %>% filter(n() == n_years, all(is.finite(gdp_growth))) %>% ungroup()
dropped <- setdiff(unique(df$iso), unique(balanced$iso))
if (length(dropped) > 0) message("Dropped (unbalanced or missing data): ", paste(dropped, collapse = ", "))

message(sprintf("Panel: %d CFA countries, %d controls, years %d-%d",
                n_distinct(balanced$iso[balanced$cfa]),
                n_distinct(balanced$iso[!balanced$cfa]),
                min(balanced$year), max(balanced$year)))

# ---------------------------------------------------------------------------
# 2. Panel matrices
# ---------------------------------------------------------------------------
# panel.matrices() orders the rows so that control units come first and treated
# units last, which is what the estimators assume. Building Y by hand with rows
# in alphabetical order (as in the first version of this analysis) mixes
# treated and control countries in the "control" block.
setup <- panel.matrices(as.data.frame(balanced %>% select(country, year, gdp_growth, treated)),
                        unit = "country", time = "year",
                        outcome = "gdp_growth", treatment = "treated")
stopifnot(setup$N0 == n_distinct(balanced$iso[!balanced$cfa]))

# ---------------------------------------------------------------------------
# 3. Estimates
# ---------------------------------------------------------------------------
estimates <- list(
  DiD  = did_estimate(setup$Y, setup$N0, setup$T0),
  SC   = sc_estimate(setup$Y, setup$N0, setup$T0),
  SDID = synthdid_estimate(setup$Y, setup$N0, setup$T0)
)

# Jackknife standard errors (leave one country out). Placebo SEs are not an
# option here: they require more control units than treated units, and the
# CFA zone has more members than the donor pool.
se_method <- "jackknife"
summary_tbl <- bind_rows(lapply(names(estimates), function(nm) {
  est <- estimates[[nm]]
  se  <- sqrt(vcov(est, method = se_method))
  tibble(estimator = nm,
         estimate  = as.numeric(est),
         std_error = as.numeric(se),
         ci_low    = estimate - 1.96 * std_error,
         ci_high   = estimate + 1.96 * std_error)
}))
print(summary_tbl, n = Inf)
write.csv(summary_tbl, "results/cfa_estimates.csv", row.names = FALSE)

# Unit weights used by SDID: which control countries make up the counterfactual
sdid_w <- synthdid_controls(estimates$SDID, weight.type = "omega", mass = 1)
print(round(sdid_w, 3))
write.csv(data.frame(country = rownames(sdid_w), omega = sdid_w[, 1]),
          "results/sdid_unit_weights.csv", row.names = FALSE)

# ---------------------------------------------------------------------------
# 4. Figures
# ---------------------------------------------------------------------------
p_est <- synthdid_plot(estimates, se.method = se_method, facet.vertical = FALSE) +
  labs(title = "CFA devaluation: DiD vs SC vs SDID", y = "Real GDP growth (%)")
ggsave("figures/cfa_estimators.png", p_est, width = 11, height = 4.5, dpi = 150)

p_weights <- synthdid_units_plot(estimates, se.method = se_method) +
  labs(title = "Unit-level contributions to each estimate")
ggsave("figures/cfa_unit_contributions.png", p_weights, width = 11, height = 5, dpi = 150)

group_avg <- balanced %>%
  group_by(year, group = ifelse(cfa, "CFA zone", "Non-CFA")) %>%
  summarise(avg_growth = mean(gdp_growth), .groups = "drop")

p_trends <- ggplot() +
  geom_line(data = balanced, aes(year, gdp_growth, group = country),
            colour = "grey75", linewidth = 0.4) +
  geom_line(data = group_avg, aes(year, avg_growth, colour = group), linewidth = 1.2) +
  geom_vline(xintercept = treat_year - 0.5, linetype = "dashed") +
  scale_colour_manual(values = c("CFA zone" = "#1f5aa6", "Non-CFA" = "#c0392b")) +
  coord_cartesian(ylim = c(-20, 25)) +
  labs(title = "Real GDP growth, 1986-2000",
       subtitle = "Grey: individual countries. Dashed line: January 1994 devaluation.",
       x = NULL, y = "Real GDP growth (%)", colour = NULL) +
  theme_minimal(base_size = 12) +
  theme(legend.position = "bottom")
ggsave("figures/cfa_gdp_trends.png", p_trends, width = 9, height = 5, dpi = 150)

period_avg <- balanced %>%
  mutate(period = factor(ifelse(year < treat_year, "1986-1993", "1994-2000"),
                         levels = c("1986-1993", "1994-2000")),
         group = ifelse(cfa, "CFA zone", "Non-CFA")) %>%
  group_by(group, period) %>%
  summarise(mean_growth = mean(gdp_growth), .groups = "drop")
print(period_avg)

p_bars <- ggplot(period_avg, aes(period, mean_growth, fill = group)) +
  geom_col(position = "dodge") +
  scale_fill_manual(values = c("CFA zone" = "#1f5aa6", "Non-CFA" = "#c0392b")) +
  labs(title = "Average real GDP growth before and after the devaluation",
       x = NULL, y = "Average growth (%)", fill = NULL) +
  theme_minimal(base_size = 12)
ggsave("figures/cfa_period_means.png", p_bars, width = 7, height = 4.5, dpi = 150)

message("Done. Results in results/, figures in figures/.")
