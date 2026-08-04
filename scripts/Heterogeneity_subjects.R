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


# ---------- 2) input file ----------

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


# ---------- 3) read data ----------

raw <- read_excel(
  infile,
  sheet = "compare_images"
)


# ---------- 4) checks ----------

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
    "Chybi sloupce: ",
    paste(missing_cols, collapse = ", ")
  )
}


# ---------- 5) derive subject_id and disease_status ----------

# Public control identifiers:
#   image_id beginning with C1_ -> C1
#   image_id beginning with C2_ -> C2
#
# HD subjects:
#   P1 ... P10 in group

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


# ---------- 6) wide -> long ----------

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


# ---------- 7) aggregate to subject level ----------

label_cols <- grep(
  "^label_",
  names(long),
  value = TRUE
)

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


# ---------- 8) control range per method ----------

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


# ---------- 9) rank subjects by Manual cristae_per_mito ----------

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


# ---------- 10) classify HD subjects relative to control band ----------

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


# ---------- 11) save subject table ----------

write_xlsx(
  list(
    subject_aggregate = subject_agg
  ),

  path = file.path(
    out_dir,
    "01_subject_aggregate.xlsx"
  )
)


# ---------- 12) PLOT 1: subject rank plot with control band ----------

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


# ---------- 13) PLOT 2: image-level distribution within each subject ----------

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


# ---------- 14) prepare class-profile heatmap ----------

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


# ---------- 15) PLOT 3A: heatmap Manual ----------

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


# ---------- 16) PLOT 3B: heatmap Automated ----------

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


# ---------- 17) export tables ----------

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


# ---------- 18) concise text summary ----------

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
    "- 02_subject_rank_plot.png: kazdy bod = jeden subjekt; ",
    "sedy pas = kontrolni rozmezi\n"
  )
)

cat(
  paste0(
    "- 03_image_level_by_subject.png: kazdy bod = jeden obrazek; ",
    "ukazuje vnitrni variabilitu subjektu\n"
  )
)

cat(
  "- 04/05 heatmap: proporce trid crist u kazdeho subjektu\n"
)

cat(
  paste0(
    "- position_vs_ctrl urcuje, zda je HD subjekt pod, ",
    "v nebo nad kontrolnim rozmezi\n"
  )
)

sink()

cat("\nHOTOVO.\n")

cat(
  "Vystupy byly ulozeny do slozky:\n",
  out_dir,
  "\n"
)
