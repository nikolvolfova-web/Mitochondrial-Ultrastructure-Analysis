# =========================================================
# STATISTICAL ANALYSIS OF TOTAL CRISTAE COUNTS
# File expected: results/derived/Prism_input.xlsx
# Sheet used: compare_images
#
# Main analysis:
#   total ~ disease_status * method + offset(log(n_mito))
#   + random effects for subject and image
#
# Confirmatory analysis:
#   subject-level cristae_per_mito = sum(total) / sum(n_mito)
#
# Outputs:
#   - cleaned long-format table
#   - model summaries
#   - subject-level summaries
#   - diagnostic plots
#   - simple figures
# =========================================================

# STATISTICAL RATIONALE
# ---------------------
# The response variable `total` is a non-negative count of cristae observed in
# an image. Images contain different numbers of mitochondria, so the model uses
# `offset(log(n_mito))` to estimate cristae rates per mitochondrion rather than
# comparing unadjusted image totals.
#
# The primary model uses the NB2 negative-binomial parameterization:
#
#   Var(Y) = mu + mu^2 / theta
#
# which allows variance to exceed the mean. The fixed-effect interaction tests
# whether the Ctrl-versus-HD rate difference depends on whether measurements
# were obtained manually or automatically.
#
# Random intercepts account for the hierarchical and paired structure:
#   - subject_id: multiple images belong to the same biological subject;
#   - image_uid: Manual and Automated measurements refer to the same image.
#
# The zero-inflated model is fitted as a sensitivity model and is not selected
# automatically. Model choice should be based on AIC together with DHARMa
# diagnostics and biological plausibility.
#
# The confirmatory analysis first pools counts within each subject and method:
#
#   cristae_per_mito = sum(total) / sum(n_mito)
#
# and then compares Ctrl and HD using an exact Wilcoxon test. This analysis gives
# each subject one value and therefore emphasizes biological replication.
#
# SCRIPT STRUCTURE
# ----------------
# This script is a sequential analysis workflow and contains no user-defined
# functions. Numbered sections document data preparation, modelling,
# diagnostics, interpretation, visualization, and export.


# ---------- 0) install missing packages ----------

needed_pkgs <- c(
  "readxl",
  "dplyr",
  "tidyr",
  "stringr",
  "ggplot2",
  "glmmTMB",
  "DHARMa",
  "emmeans",
  "writexl",
  "coin"
)

to_install <- needed_pkgs[
  !needed_pkgs %in% installed.packages()[, "Package"]
]

if (length(to_install) > 0) {
  install.packages(to_install)
}


# ---------- 1) load packages ----------

library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(ggplot2)
library(glmmTMB)
library(DHARMa)
library(emmeans)
library(writexl)
library(coin)


# ---------- 2) define and validate input/output paths ----------

infile <- file.path(
  "results",
  "derived",
  "Prism_input.xlsx"
)

if (!file.exists(infile)) {
  stop(
    paste(
      "Input workbook was not found:",
      infile,
      "\nRun scripts/prepare_prism_input.R first."
    ),
    call. = FALSE
  )
}

out_dir <- file.path(
  dirname(infile),
  "stats_total_cristae"
)

if (!dir.exists(out_dir)) {
  dir.create(
    out_dir,
    recursive = TRUE
  )
}

cat("Input workbook:\n", infile, "\n")
cat("Output directory:\n", out_dir, "\n")


# ---------- 3) read paired image-level data ----------

raw <- read_excel(
  infile,
  sheet = "compare_images"
)


# ---------- 4) validate the required input schema ----------

required_cols <- c(
  "group",
  "image_id",
  "manual_n_mito",
  "manual_total",
  "manual_mean_per_mito",
  "auto_n_mito",
  "auto_total",
  "auto_mean_per_mito"
)

missing_cols <- setdiff(
  required_cols,
  names(raw)
)

if (length(missing_cols) > 0) {
  stop(
    "The input table is missing required columns: ",
    paste(missing_cols, collapse = ", ")
  )
}


# ---------- 5) derive disease status and biological subject identifiers ----------

# Control subjects are recognized from image IDs beginning with `C1_` or `C2_`.
# HD subject identity is taken from the experimental group name (`P1`-`P10`).
# This mapping must match the naming convention used during data curation.
dat <- raw %>%
  mutate(
    disease_status = case_when(
      str_detect(group, "^Ctrl") ~ "Ctrl",
      TRUE ~ "HD"
    ),

    subject_id = case_when(
      str_detect(image_id, "^C1_") ~ "C1",
      str_detect(image_id, "^C2_") ~ "C2",
      TRUE ~ as.character(group)
    ),

    disease_status = factor(
      disease_status,
      levels = c("Ctrl", "HD")
    ),

    subject_id = factor(subject_id)
  )


# ---------- 6) reshape paired Manual/Automated measurements to long format ----------

# The `.value` syntax creates shared variables such as `total`, `n_mito`, and
# `mean_per_mito`, while `method` records whether each row is Manual or
# Automated. Consequently, each paired image contributes up to two rows.
# `image_uid` uniquely identifies the paired image within its subject.
long <- dat %>%
  pivot_longer(
    cols = -c(
      group,
      image_id,
      disease_status,
      subject_id
    ),

    names_to = c(
      "method",
      ".value"
    ),

    names_pattern = "^(manual|auto)_(.*)$"
  ) %>%
  mutate(
    method = recode(
      method,
      manual = "Manual",
      auto = "Automated"
    ),

    method = factor(
      method,
      levels = c(
        "Manual",
        "Automated"
      )
    ),

    image_uid = paste(
      subject_id,
      image_id,
      sep = "__"
    )
  )


# ---------- 7) retain rows with valid counts and positive exposure ----------

long <- long %>%
  filter(
    !is.na(total),
    !is.na(n_mito),
    n_mito > 0
  )


# Print a concise quality-control overview of the modelling dataset.

cat("\n===== QC =====\n")
cat(
  "Rows in the long-format dataset:",
  nrow(long),
  "\n"
)

cat(
  "Unique subjects:",
  n_distinct(long$subject_id),
  "\n"
)

cat(
  "Unique images:",
  n_distinct(long$image_uid),
  "\n\n"
)

print(
  long %>%
    distinct(
      subject_id,
      disease_status,
      image_uid
    ) %>%
    count(
      disease_status,
      subject_id,
      name = "n_images"
    )
)


# ---------- 8) export the cleaned long-format modelling table ----------

write_xlsx(
  list(
    long_data = long
  ),
  path = file.path(
    out_dir,
    "01_long_data.xlsx"
  )
)


# ---------- 9) fit the primary negative-binomial generalized mixed model ----------

# Interpretation:
# - disease_status = biological effect Ctrl vs HD
# - method = systematic difference Manual vs Automated
# - interaction = whether group difference depends on method

# With a log link, the model can be written as:
#
#   log(E[total]) = fixed effects + log(n_mito) + random intercepts.
#
# Moving the offset to the left-hand side shows that fixed effects describe
# multiplicative changes in the expected cristae count per mitochondrion.
m_nb <- glmmTMB(
  total ~ disease_status * method +
    offset(log(n_mito)) +
    (1 | subject_id) +
    (1 | image_uid),

  family = nbinom2,
  data = long
)

cat("\n===== PRIMARY MODEL: NB GLMM =====\n")
print(summary(m_nb))


# ---------- 10) fit a zero-inflated negative-binomial sensitivity model ----------

# The sensitivity model adds one structural-zero probability shared across all
# observations (`ziformula = ~1`). It should be preferred only when the data and
# diagnostics support a separate excess-zero process.
m_zinb <- glmmTMB(
  total ~ disease_status * method +
    offset(log(n_mito)) +
    (1 | subject_id) +
    (1 | image_uid),

  ziformula = ~1,
  family = nbinom2,
  data = long
)

aic_tbl <- AIC(
  m_nb,
  m_zinb
) %>%
  as.data.frame() %>%
  tibble::rownames_to_column("model")

cat("\n===== MODEL COMPARISON =====\n")
print(aic_tbl)

# Primary model remains NB by default.
# If ZI model is clearly better and diagnostics support it,
# you may report ZI model as sensitivity analysis.


# ---------- 11) evaluate model fit using simulation-based DHARMa diagnostics ----------

# DHARMa creates standardized simulated residuals. The exported diagnostic plot
# and formal tests assess dispersion, excess zeros, and potential outliers.
sim_nb <- simulateResiduals(
  m_nb,
  n = 1000
)

pdf(
  file.path(
    out_dir,
    "02_DHARMa_diagnostics_NB.pdf"
  ),
  width = 8,
  height = 8
)

plot(sim_nb)

dev.off()

disp_test <- testDispersion(sim_nb)
zi_test <- testZeroInflation(sim_nb)
outl_test <- testOutliers(sim_nb)

cat("\n===== DHARMa DIAGNOSTICS =====\n")
print(disp_test)
print(zi_test)
print(outl_test)


# ---------- 12) extract fixed effects, incidence-rate ratios, and Wald intervals ----------

coef_mat <- summary(m_nb)$coefficients$cond

coef_df <- as.data.frame(coef_mat) %>%
  tibble::rownames_to_column("term") %>%
  rename(
    estimate = Estimate,
    std_error = `Std. Error`,
    z_value = `z value`,
    p_value = `Pr(>|z|)`
  ) %>%
  mutate(
    IRR = exp(estimate)
  )


# Fixed-effect estimates are on the log-rate scale. Exponentiation produces
# incidence-rate ratios (IRR), where IRR > 1 indicates a higher expected rate
# and IRR < 1 indicates a lower expected rate for the corresponding contrast.

# Wald confidence intervals for fixed effects

ci_df <- as.data.frame(
  confint(
    m_nb,
    parm = "beta_",
    method = "Wald"
  )
)

ci_df <- ci_df %>%
  tibble::rownames_to_column("term") %>%
  rename(
    conf_low = `2.5 %`,
    conf_high = `97.5 %`
  ) %>%
  mutate(
    IRR_low = exp(conf_low),
    IRR_high = exp(conf_high)
  )

fixed_effects <- coef_df %>%
  left_join(
    ci_df,
    by = "term"
  )


# ---------- 13) estimate marginal rates and biologically relevant contrasts ----------

# Setting `offset = 0` corresponds to log(n_mito) = 0 and therefore n_mito = 1.
# Response-scale estimated marginal means are consequently rates per
# mitochondrion. Pairwise contrasts on the response scale are rate ratios.

emm_group_by_method <- emmeans(
  m_nb,
  ~ disease_status | method,
  type = "response",
  offset = 0
)

emm_method_by_group <- emmeans(
  m_nb,
  ~ method | disease_status,
  type = "response",
  offset = 0
)

contrast_group_by_method <- as.data.frame(
  contrast(
    emm_group_by_method,
    method = "revpairwise"
  )
)

contrast_method_by_group <- as.data.frame(
  contrast(
    emm_method_by_group,
    method = "revpairwise"
  )
)

emm_group_by_method_df <- as.data.frame(
  emm_group_by_method
)

emm_method_by_group_df <- as.data.frame(
  emm_method_by_group
)


# ---------- 14) perform the confirmatory subject-level analysis ----------

# Counts and mitochondrion numbers are summed within each biological subject
# before division. This produces a pooled rate and avoids giving small images
# the same weight as images containing many mitochondria.
subject_summary <- long %>%
  group_by(
    disease_status,
    subject_id,
    method
  ) %>%
  summarise(
    total_sum = sum(
      total,
      na.rm = TRUE
    ),

    n_mito_sum = sum(
      n_mito,
      na.rm = TRUE
    ),

    cristae_per_mito = total_sum / n_mito_sum,

    n_images = n(),

    .groups = "drop"
  )

cat("\n===== SUBJECT-LEVEL SUMMARY =====\n")
print(subject_summary)


# Compare Ctrl and HD subjects separately for each measurement method.

subject_manual <- subject_summary %>%
  filter(method == "Manual")

subject_auto <- subject_summary %>%
  filter(method == "Automated")

wt_manual <- wilcox_test(
  cristae_per_mito ~ disease_status,
  data = subject_manual,
  distribution = "exact"
)

wt_auto <- wilcox_test(
  cristae_per_mito ~ disease_status,
  data = subject_auto,
  distribution = "exact"
)

manual_p <- pvalue(wt_manual)
auto_p <- pvalue(wt_auto)

confirmatory_tests <- tibble::tibble(
  method = c(
    "Manual",
    "Automated"
  ),

  test = c(
    "Exact Wilcoxon (coin)",
    "Exact Wilcoxon (coin)"
  ),

  p_value = c(
    manual_p,
    auto_p
  )
)

cat("\n===== CONFIRMATORY SUBJECT-LEVEL TESTS =====\n")
print(confirmatory_tests)


# ---------- 15) calculate image-level and subject-level descriptive summaries ----------

image_level_summary <- long %>%
  group_by(
    disease_status,
    method
  ) %>%
  summarise(
    n_images = n(),

    mean_total = mean(
      total,
      na.rm = TRUE
    ),

    sd_total = sd(
      total,
      na.rm = TRUE
    ),

    median_total = median(
      total,
      na.rm = TRUE
    ),

    mean_n_mito = mean(
      n_mito,
      na.rm = TRUE
    ),

    mean_rate = mean(
      total / n_mito,
      na.rm = TRUE
    ),

    median_rate = median(
      total / n_mito,
      na.rm = TRUE
    ),

    .groups = "drop"
  )

subject_level_summary <- subject_summary %>%
  group_by(
    disease_status,
    method
  ) %>%
  summarise(
    n_subjects = n(),

    mean_rate = mean(
      cristae_per_mito,
      na.rm = TRUE
    ),

    sd_rate = sd(
      cristae_per_mito,
      na.rm = TRUE
    ),

    median_rate = median(
      cristae_per_mito,
      na.rm = TRUE
    ),

    .groups = "drop"
  )


# ---------- 16) calculate secondary subject-level cristae-class profiles ----------

label_cols <- grep(
  "^label_",
  names(long),
  value = TRUE
)

# Class counts are pooled within each subject and method and then normalized by
# the total number of classified cristae. These profiles are descriptive and do
# not form part of the primary NB GLMM.
subject_class_profile <- long %>%
  group_by(
    disease_status,
    subject_id,
    method
  ) %>%
  summarise(
    across(
      all_of(label_cols),
      ~ sum(.x, na.rm = TRUE)
    ),
    .groups = "drop"
  ) %>%
  mutate(
    total_labels = rowSums(
      across(
        all_of(label_cols)
      )
    )
  ) %>%
  mutate(
    across(
      all_of(label_cols),
      ~ .x / ifelse(
        total_labels == 0,
        NA,
        total_labels
      ),
      .names = "prop_{.col}"
    )
  )


# ---------- 17) create subject-level and image-level descriptive figures ----------

# Subject-level plot: one pooled rate per biological subject and method.

p_subject <- ggplot(
  subject_summary,
  aes(
    x = disease_status,
    y = cristae_per_mito,
    color = disease_status
  )
) +
  geom_boxplot(
    outlier.shape = NA,
    width = 0.5
  ) +
  geom_jitter(
    width = 0.08,
    size = 2.5
  ) +
  facet_wrap(
    ~ method
  ) +
  labs(
    title = "Cristae per mitochondrion at subject level",
    x = NULL,
    y = "sum(total) / sum(n_mito)"
  ) +
  theme_bw() +
  theme(
    legend.position = "none"
  )

ggsave(
  filename = file.path(
    out_dir,
    "03_subject_level_cristae_per_mito.png"
  ),

  plot = p_subject,
  width = 8,
  height = 4.8,
  dpi = 300
)


# Image-level plot: one rate per image and method.

p_image <- ggplot(
  long,
  aes(
    x = disease_status,
    y = total / n_mito,
    color = disease_status
  )
) +
  geom_boxplot(
    outlier.shape = NA,
    width = 0.5
  ) +
  geom_jitter(
    width = 0.08,
    alpha = 0.7,
    size = 1.8
  ) +
  facet_wrap(
    ~ method
  ) +
  labs(
    title = "Cristae per mitochondrion at image level",
    x = NULL,
    y = "total / n_mito"
  ) +
  theme_bw() +
  theme(
    legend.position = "none"
  )

ggsave(
  filename = file.path(
    out_dir,
    "04_image_level_cristae_per_mito.png"
  ),

  plot = p_image,
  width = 8,
  height = 4.8,
  dpi = 300
)


# ---------- 18) export all primary tables to a structured Excel workbook ----------

write_xlsx(
  list(
    long_data = long,

    image_level_summary = image_level_summary,

    subject_summary = subject_summary,

    subject_level_summary = subject_level_summary,

    fixed_effects_NB = fixed_effects,

    AIC_models = aic_tbl,

    emmeans_group_by_method = emm_group_by_method_df,

    contrasts_group_by_method = contrast_group_by_method,

    emmeans_method_by_group = emm_method_by_group_df,

    contrasts_method_by_group = contrast_method_by_group,

    confirmatory_tests = confirmatory_tests,

    subject_class_profile = subject_class_profile
  ),

  path = file.path(
    out_dir,
    "05_statistical_results.xlsx"
  )
)


# ---------- 19) save complete model and diagnostic output as plain text ----------

sink(
  file.path(
    out_dir,
    "06_model_output.txt"
  )
)

cat("===== NEGATIVE BINOMIAL GLMM =====\n\n")
print(summary(m_nb))

cat("\n\n===== ZERO-INFLATED NB MODEL =====\n\n")
print(summary(m_zinb))

cat("\n\n===== AIC COMPARISON =====\n\n")
print(aic_tbl)

cat("\n\n===== DHARMa DIAGNOSTICS =====\n\n")
print(disp_test)
print(zi_test)
print(outl_test)

cat("\n\n===== FIXED EFFECTS WITH IRR =====\n\n")
print(fixed_effects)

cat("\n\n===== EMMEANS: GROUP WITHIN METHOD =====\n\n")
print(emm_group_by_method_df)

cat("\n\n===== CONTRASTS: GROUP WITHIN METHOD =====\n\n")
print(contrast_group_by_method)

cat("\n\n===== EMMEANS: METHOD WITHIN GROUP =====\n\n")
print(emm_method_by_group_df)

cat("\n\n===== CONTRASTS: METHOD WITHIN GROUP =====\n\n")
print(contrast_method_by_group)

cat("\n\n===== SUBJECT-LEVEL SUMMARY =====\n\n")
print(subject_summary)

cat("\n\n===== CONFIRMATORY SUBJECT-LEVEL TESTS =====\n\n")
print(confirmatory_tests)

sink()


cat("\nCOMPLETED.\n")
cat(
  "Outputs were saved to:\n",
  out_dir,
  "\n"
)
