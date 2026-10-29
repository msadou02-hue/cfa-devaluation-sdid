# Replication of the California Proposition 99 example from
# Arkhangelsky et al. (2021), using the data shipped with synthdid.
#
# Run from the repository root:  Rscript R/02_prop99_replication.R
# Expected point estimates (paper, Table 1): DiD -27.3, SC -19.6, SDID -15.6

suppressPackageStartupMessages({
  library(ggplot2)
  library(synthdid)
})

set.seed(12345)
dir.create("figures", showWarnings = FALSE)
dir.create("results", showWarnings = FALSE)

data("california_prop99")
setup <- panel.matrices(california_prop99)

estimates <- list(
  DiD  = did_estimate(setup$Y, setup$N0, setup$T0),
  SC   = sc_estimate(setup$Y, setup$N0, setup$T0),
  SDID = synthdid_estimate(setup$Y, setup$N0, setup$T0)
)

# One treated unit: placebo standard errors, as in the paper.
summary_tbl <- do.call(rbind, lapply(names(estimates), function(nm) {
  est <- estimates[[nm]]
  se  <- sqrt(vcov(est, method = "placebo"))
  data.frame(estimator = nm, estimate = as.numeric(est), std_error = as.numeric(se))
}))
print(summary_tbl, digits = 3)
write.csv(summary_tbl, "results/prop99_estimates.csv", row.names = FALSE)

p <- synthdid_plot(estimates, se.method = "placebo", facet.vertical = FALSE) +
  labs(y = "Cigarette packs per capita")
ggsave("figures/prop99_estimators.png", p, width = 11, height = 4.5, dpi = 150)
