# =========================================================
# HETEROGENEITY BETWEEN SUBJECTS / PATIENTS
# Input: results/derived/Prism_input.xlsx
# Sheet: compare_images
#
# Outputs:
#   01_subject_aggregate.xlsx
#   02_subject_rank_plot.png
#   03_image_level_by_subject.png
#   04_class_profile_heatmap_manual.png
#   05_class_profile_heatmap_automated.png
#   06_subject_tables.xlsx
#   07_readme_summary.txt
# =========================================================

# ANALYTICAL SCOPE
# ----------------
# This is a descriptive heterogeneity workflow. It does not fit an inferential
# statistical model. Its purpose is to show how subject-level values and
# within-subject image-level measurements vary across controls and HD subjects.
#
# Two measurement methods are processed in parallel:
#   - Manual
#   - Automated
#
# The central subject-level quantity is a pooled rate:
#
#   cristae_per_mito = sum(total cristae across images) /
#                      sum(mitochondria across images)
#
# This weighting gives each mitochondrion equal contribution. It is not the
# arithmetic mean of image-specific `total / n_mito` values.
#
# The control band is the observed minimum-to-maximum range across control
# subjects for each method. It is a descriptive reference range, not a
# confidence interval or formal statistical acceptance interval.
#
# SCRIPT STRUCTURE
# ----------------
# The script is intentionally written as a sequential workflow and contains no
# user-defined functions. Each numbered section documents one reproducible step.


# ---------- 0) install missing packages ----------

needed_pkgs <- c(
  "readxl",
  "dplyr",
  "tidyr",
  "stringr",
  "ggplot2",
  "forcats",
  "writexl",
  "scales"
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
library(forcats)
library(writexl)
library(scales)


# ---------- 2) define input and output paths ----------

infile <- file.path(
  "results",
  "derived",
  "Prism_input.xlsx"
)

out_dir <- file.path(
  dirname(infile),
  "heterogeneity_subjects"
)

if (!dir.exists(out_dir)) {
  dir.create(out_dir)
}


# ---------- 3) read the paired image-level input table ----------

raw <- read_excel(
  infile,
  sheet = "compare_images"
)


# ---------- 4) validate required input columns ----------

required_cols <- c(
  "group",
  "image_id",
  "manual_n_mito",
  "manual_total",
  "auto_n_mito",
  "auto_total"
)

missing_cols <- setdiff(
  required_cols,
  names(raw)
)

if (length(missing_cols) > 0) {
  stop(
    "Missing required columns: ",
    paste(missing_cols, collapse = ", ")
  )
}


# ---------- 5) derive disease status and subject identifiers ----------

# Public control identifiers:
#   image_id beginning with C1_ -> C1
#   image_id beginning with C2_ -> C2
#
# HD subjects:
#   P1 ... P10 in group

# Control subjects are encoded in image IDs (`C1_` and `C2_`), whereas HD
# subjects are encoded by the worksheet/group name (`P1` through `P10`).
# Factor levels place Ctrl before HD for consistent plotting and summaries.
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


# ---------- 6) reshape paired manual/automated columns to long format ----------

# `pivot_longer()` converts columns such as `manual_total` and `auto_total`
# into a shared `total` column plus a method indicator. Rows without a valid
# total or a positive mitochondrion count are excluded before rate calculation.
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

    cristae_per_mito = total / n_mito
  ) %>%
  filter(
    !is.na(total),
    !is.na(n_mito),
    n_mito > 0
  )


# ---------- 7) aggregate image-level measurements to subject level ----------

label_cols <- grep(
  "^label_",
  names(long),
  value = TRUE
)

# Counts are summed before division so that `cristae_per_mito` is a pooled
# subject-level rate. Class proportions are also calculated from summed class
# counts, preserving the contribution of all observed cristae.
subject_agg <- long %>%
  group_by(
    disease_status,
    subject_id,
    method
  ) %>%
  summarise(
    n_images = n(),

    total_sum = sum(
      total,
      na.rm = TRUE
    ),

    n_mito_sum = sum(
      n_mito,
      na.rm = TRUE
    ),

    cristae_per_mito = total_sum / n_mito_sum,

    across(
      all_of(label_cols),
      ~ sum(.x, na.rm = TRUE)
    ),

    .groups = "drop"
  ) %>%
  mutate(
    label_total = rowSums(
      across(
        all_of(label_cols)
      )
    ),

    across(
      all_of(label_cols),
      ~ .x / ifelse(
        label_total == 0,
        NA,
        label_total
      ),
      .names = "prop_{.col}"
    )
  )


# ---------- 8) calculate the descriptive control range for each method ----------

# The observed control minimum, maximum, and mean are calculated separately
# for Manual and Automated measurements. These values are descriptive only.
control_band <- subject_agg %>%
  filter(
    disease_status == "Ctrl"
  ) %>%
  group_by(method) %>%
  summarise(
    ctrl_min = min(
      cristae_per_mito,
      na.rm = TRUE
    ),

    ctrl_max = max(
      cristae_per_mito,
      na.rm = TRUE
    ),

    ctrl_mean = mean(
      cristae_per_mito,
      na.rm = TRUE
    ),

    .groups = "drop"
  )


# ---------- 9) define a common subject order using the Manual pooled rate ----------

# A single ordering derived from Manual values is reused in both facets and
# heatmaps, allowing direct visual comparison between measurement methods.
manual_order <- subject_agg %>%
  filter(
    method == "Manual"
  ) %>%
  arrange(cristae_per_mito) %>%
  pull(subject_id) %>%
  as.character()

subject_agg <- subject_agg %>%
  mutate(
    subject_plot = factor(
      as.character(subject_id),
      levels = manual_order
    )
  )

long <- long %>%
  mutate(
    subject_plot = factor(
      as.character(subject_id),
      levels = manual_order
    )
  )


# ---------- 10) classify each subject relative to the observed control range ----------

subject_agg <- subject_agg %>%
  left_join(
    control_band,
    by = "method"
  ) %>%
  mutate(
    position_vs_ctrl = case_when(
      disease_status == "Ctrl" ~ "Control",

      cristae_per_mito < ctrl_min ~
        "Below control range",

      cristae_per_mito > ctrl_max ~
        "Above control range",

      TRUE ~ "Within control range"
    )
  )


# ---------- 11) export the primary subject-level table ----------

write_xlsx(
  list(
    subject_aggregate = subject_agg
  ),

  path = file.path(
    out_dir,
    "01_subject_aggregate.xlsx"
  )
)


# ---------- 12) PLOT 1: subject-level rank plot with control reference band ----------

p_rank <- ggplot(
  subject_agg,
  aes(
    x = subject_plot,
    y = cristae_per_mito,
    color = disease_status
  )
) +
  geom_rect(
    data = control_band,

    aes(
      xmin = -Inf,
      xmax = Inf,
      ymin = ctrl_min,
      ymax = ctrl_max
    ),

    inherit.aes = FALSE,
    fill = "grey85",
    alpha = 0.5
  ) +
  geom_hline(
    data = control_band,

    aes(
      yintercept = ctrl_mean
    ),

    inherit.aes = FALSE,
    linetype = "dashed",
    linewidth = 0.5
  ) +
  geom_point(
    size = 3
  ) +
  facet_wrap(
    ~ method,
    scales = "free_y"
  ) +
  labs(
    title = "Subject-level cristae abundance with control reference range",

    subtitle = paste(
      "Grey band = control min-max range;",
      "dashed line = control mean"
    ),

    x = NULL,

    y = paste(
      "Cristae per mitochondrion",
      "(sum(total) / sum(n_mito))"
    )
  ) +
  theme_bw() +
  theme(
    legend.position = "top",

    axis.text.x = element_text(
      angle = 45,
      hjust = 1
    )
  )

ggsave(
  filename = file.path(
    out_dir,
    "02_subject_rank_plot.png"
  ),

  plot = p_rank,
  width = 10,
  height = 5.5,
  dpi = 300
)


# ---------- 13) PLOT 2: within-subject image-level distributions ----------

# Shows within-subject variability and overlap across subjects

p_image <- ggplot(
  long,
  aes(
    x = subject_plot,
    y = cristae_per_mito,
    color = disease_status
  )
) +
  geom_jitter(
    width = 0.15,
    alpha = 0.7,
    size = 1.8
  ) +
  stat_summary(
    fun = median,
    geom = "crossbar",
    width = 0.55,
    fatten = 0,
    linewidth = 0.4,
    color = "black"
  ) +
  facet_wrap(
    ~ method,
    scales = "free_y"
  ) +
  labs(
    title = "Image-level cristae abundance within each subject",

    subtitle = paste(
      "Dots = individual images;",
      "black crossbar = within-subject median"
    ),

    x = NULL,

    y = paste(
      "Cristae per mitochondrion",
      "(total / n_mito)"
    )
  ) +
  theme_bw() +
  theme(
    legend.position = "top",

    axis.text.x = element_text(
      angle = 45,
      hjust = 1
    )
  )

ggsave(
  filename = file.path(
    out_dir,
    "03_image_level_by_subject.png"
  ),

  plot = p_image,
  width = 12,
  height = 5.5,
  dpi = 300
)


# ---------- 14) reshape subject-level class proportions for heatmaps ----------

# Wide class-proportion columns are converted to one row per subject, method,
# and cristae class. The explicit class order prevents lexical sorting (e.g.,
# class 10 appearing before class 2).
heat_long <- subject_agg %>%
  select(
    disease_status,
    subject_id,
    subject_plot,
    method,
    starts_with("prop_label_")
  ) %>%
  pivot_longer(
    cols = starts_with("prop_label_"),
    names_to = "class",
    values_to = "proportion"
  ) %>%
  mutate(
    class = str_remove(
      class,
      "^prop_label_"
    ),

    class = factor(
      class,
      levels = as.character(2:12)
    )
  )


# ---------- 15) PLOT 3A: Manual class-profile heatmap ----------

p_heat_manual <- heat_long %>%
  filter(
    method == "Manual"
  ) %>%
  ggplot(
    aes(
      x = class,
      y = subject_plot,
      fill = proportion
    )
  ) +
  geom_tile(
    color = "white"
  ) +
  scale_fill_gradient(
    low = "white",
    high = "black",

    labels = percent_format(
      accuracy = 1
    ),

    na.value = "grey95"
  ) +
  labs(
    title = "Cristae class profile by subject - Manual",
    x = "Cristae class",
    y = NULL,
    fill = "Proportion"
  ) +
  theme_bw() +
  theme(
    panel.grid = element_blank()
  )

ggsave(
  filename = file.path(
    out_dir,
    "04_class_profile_heatmap_manual.png"
  ),

  plot = p_heat_manual,
  width = 8.5,
  height = 5.5,
  dpi = 300
)


# ---------- 16) PLOT 3B: Automated class-profile heatmap ----------

p_heat_auto <- heat_long %>%
  filter(
    method == "Automated"
  ) %>%
  ggplot(
    aes(
      x = class,
      y = subject_plot,
      fill = proportion
    )
  ) +
  geom_tile(
    color = "white"
  ) +
  scale_fill_gradient(
    low = "white",
    high = "black",

    labels = percent_format(
      accuracy = 1
    ),

    na.value = "grey95"
  ) +
  labs(
    title = "Cristae class profile by subject - Automated",
    x = "Cristae class",
    y = NULL,
    fill = "Proportion"
  ) +
  theme_bw() +
  theme(
    panel.grid = element_blank()
  )

ggsave(
  filename = file.path(
    out_dir,
    "05_class_profile_heatmap_automated.png"
  ),

  plot = p_heat_auto,
  width = 8.5,
  height = 5.5,
  dpi = 300
)


# ---------- 17) export detailed subject and image summaries ----------

# This table summarizes the distribution of image-specific rates within each
# subject. Unlike `subject_agg`, these statistics give every image equal weight.
image_summary <- long %>%
  group_by(
    disease_status,
    subject_id,
    method
  ) %>%
  summarise(
    n_images = n(),

    mean_image_rate = mean(
      cristae_per_mito,
      na.rm = TRUE
    ),

    median_image_rate = median(
      cristae_per_mito,
      na.rm = TRUE
    ),

    sd_image_rate = sd(
      cristae_per_mito,
      na.rm = TRUE
    ),

    min_image_rate = min(
      cristae_per_mito,
      na.rm = TRUE
    ),

    max_image_rate = max(
      cristae_per_mito,
      na.rm = TRUE
    ),

    .groups = "drop"
  )

write_xlsx(
  list(
    subject_aggregate = subject_agg,
    image_summary_by_subject = image_summary,
    heatmap_input = heat_long
  ),

  path = file.path(
    out_dir,
    "06_subject_tables.xlsx"
  )
)


# ---------- 18) write a concise human-readable summary ----------

sink(
  file.path(
    out_dir,
    "07_readme_summary.txt"
  )
)

cat("HETEROGENEITY SUMMARY\n")
cat("=====================\n\n")

cat("1) Subject-level aggregate values:\n")

print(
  subject_agg %>%
    select(
      disease_status,
      subject_id,
      method,
      n_images,
      total_sum,
      n_mito_sum,
      cristae_per_mito,
      position_vs_ctrl
    ) %>%
    arrange(
      method,
      disease_status,
      cristae_per_mito
    )
)

cat("\n\n2) Control reference ranges:\n")
print(control_band)

cat("\n\n3) Interpretation guide:\n")

cat(
  paste0(
    "- 02_subject_rank_plot.png: each point represents one subject; ",
    "the grey band is the observed control range\n"
  )
)

cat(
  paste0(
    "- 03_image_level_by_subject.png: each point represents one image; ",
    "the plot shows within-subject variability\n"
  )
)

cat(
  "- 04/05 heatmaps: cristae-class proportions for each subject\n"
)

cat(
  paste0(
    "- position_vs_ctrl indicates whether an HD subject is below, ",
    "within, or above the observed control range\n"
  )
)

sink()

cat("\nCOMPLETED.\n")

cat(
  "Outputs were saved to:\n",
  out_dir,
  "\n"
)
