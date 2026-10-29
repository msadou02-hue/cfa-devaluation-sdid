# Install the packages used by this project.
pkgs <- c("dplyr", "tidyr", "ggplot2", "pwt10", "remotes")
missing <- setdiff(pkgs, rownames(installed.packages()))
if (length(missing) > 0) install.packages(missing)

if (!requireNamespace("synthdid", quietly = TRUE)) {
  remotes::install_github("synth-inference/synthdid")
}
