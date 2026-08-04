# =========================================================
# PRISM INPUT EXPORT: manual vs automated cristae counts
#
# 1 row = 1 image
#
# Inputs:
#   data/curated/cristae_automated.xlsx
#   data/curated/cristae_manual.xlsx
#
# Output:
#   results/derived/Prism_input.xlsx
#
# Output worksheets:
#   - compare_images
#   - BA_total
#   - Scatter_total
#   - BA_mean_per_mito
#   - Scatter_mean_per_mito
#   - BA_label_totals
#   - QC_missing_in_auto
#   - QC_missing_in_manual
# =========================================================

# WORKFLOW OVERVIEW
# -----------------
# The source workbooks contain repeated image blocks. Within each block, the
# image identifier is written in column A and is followed by one or more
# mitochondrion-level rows. Column B identifies valid mitochondrion rows, while
# columns C:M contain counts for cristae classes 2-12.
#
# The script performs two aggregation levels:
#   1. mitochondrion level: one parsed row per valid mitochondrion;
#   2. image level: counts are summed across all mitochondria in an image.
#
# Manual and automated image-level tables are joined by both `group` and
# `image_id`. The complete joined table is retained for quality control, while
# Prism-specific worksheets contain only images present in both methods.
#
# IMPORTANT DATA ASSUMPTION
# -------------------------
# Non-numeric or empty class-count cells in columns C:M are interpreted as zero.
# This is appropriate only when an empty class cell means that no cristae of the
# corresponding class were observed. It should not be used for unknown or
# genuinely missing measurements.


# ---------- 0) install missing packages ----------

needed_pkgs <- c(
  "readxl",
  "dplyr",
  "stringr",
  "tidyr",
  "writexl",
  "tibble"
)

to_install <- needed_pkgs[
  !needed_pkgs %in% installed.packages()[, "Package"]
]

if (length(to_install) > 0) {
  install.packages(
    to_install,
    repos = "https://cloud.r-project.org"
  )
}


# ---------- 1) load required packages ----------

library(readxl)
library(dplyr)
library(stringr)
library(tidyr)
library(writexl)
library(tibble)


# ---------- 2) define repository input and output paths ----------

auto_path <- file.path(
  "data",
  "curated",
  "cristae_automated.xlsx"
)

man_path <- file.path(
  "data",
  "curated",
  "cristae_manual.xlsx"
)

if (!file.exists(auto_path)) {
  stop(
    paste(
      "Automated workbook was not found:",
      auto_path
    ),
    call. = FALSE
  )
}

if (!file.exists(man_path)) {
  stop(
    paste(
      "Manual workbook was not found:",
      man_path
    ),
    call. = FALSE
  )
}

cat("Automated workbook:\n", auto_path, "\n\n")
cat("Manual workbook:\n", man_path, "\n\n")

out_dir <- file.path(
  "results",
  "derived"
)

if (!dir.exists(out_dir)) {
  dir.create(
    out_dir,
    recursive = TRUE
  )
}

out_file <- file.path(
  out_dir,
  "Prism_input.xlsx"
)


# ---------- 3) parse one worksheet into mitochondrion-level rows ----------

#' Parse one worksheet into mitochondrion-level observations
#'
#' Reads a worksheet without assuming a conventional single-row header. The
#' function tracks the most recently encountered image identifier in column A
#' and assigns subsequent numeric mitochondrion rows to that image. A row is
#' accepted only when column B can be converted to a numeric mitochondrion ID.
#'
#' Cristae class counts are read from columns C:M and mapped to classes 2-12.
#' Empty or non-numeric class cells are converted to zero before row totals are
#' calculated.
#'
#' @param path Character scalar. Path to the source Excel workbook.
#' @param sheet_name Character scalar. Name of the worksheet to parse. The
#'   worksheet name is also retained as the experimental `group` identifier.
#'
#' @return A tibble with one row per valid mitochondrion and the columns
#'   `group`, `image_id`, `mito_row`, `mito_id`, `mito_total`, and
#'   `label_2` through `label_12`. An empty tibble is returned when the sheet
#'   contains no valid mitochondrion rows.
#'
#' @details Rows whose first cell is `Slice` are interpreted as block headers
#'   and reset the active image identifier. A numeric value in column B defines
#'   a mitochondrion row. If such a row appears before a valid image identifier
#'   has been found, the row is skipped to prevent assignment to the wrong image.
#'
#' @note Replacing non-numeric class cells with zero assumes that missing cells
#'   mean an observed count of zero rather than an unavailable measurement.
#'
parse_sheet <- function(path, sheet_name) {

  x <- read_excel(
    path,
    sheet = sheet_name,
    col_names = FALSE
  )

  n <- nrow(x)

  if (n == 0) {
    return(tibble())
  }

  current_image <- NA_character_
  out <- vector("list", length = 0)

  for (i in seq_len(n)) {

    # Column A contains either the block header (`Slice`) or an image ID.
    a <- x[[1]][i]

    # Column B contains the mitochondrion identifier for valid data rows.
    b <- x[[2]][i]

    a_str <- ifelse(
      is.na(a),
      "",
      as.character(a)
    )

    a_str_trim <- str_trim(a_str)

    # A `Slice` row starts a new block and resets the active image ID.
    if (tolower(a_str_trim) == "slice") {
      current_image <- NA_character_
      next
    }

    # A row is treated as a mitochondrion row only when column B is numeric.
    b_num <- suppressWarnings(
      as.numeric(b)
    )

    if (!is.na(b_num)) {

      # Update the active image ID when column A contains a non-empty value.
      if (a_str_trim != "") {
        current_image <- a_str_trim
      }

      # Discard rows that cannot be assigned to a known image.
      if (
        is.na(current_image) ||
        current_image == ""
      ) {
        next
      }

      # Columns C:M contain counts for cristae classes 2 through 12.
      lab <- x[i, 3:13] |>
        unlist(use.names = FALSE)

      lab_num <- suppressWarnings(
        as.numeric(lab)
      )

      lab_num[is.na(lab_num)] <- 0

      out[[length(out) + 1]] <- tibble(
        group = sheet_name,
        image_id = current_image,
        mito_row = i,
        mito_id = b_num,
        mito_total = sum(lab_num),
        label_2 = lab_num[1],
        label_3 = lab_num[2],
        label_4 = lab_num[3],
        label_5 = lab_num[4],
        label_6 = lab_num[5],
        label_7 = lab_num[6],
        label_8 = lab_num[7],
        label_9 = lab_num[8],
        label_10 = lab_num[9],
        label_11 = lab_num[10],
        label_12 = lab_num[11]
      )
    }
  }

  if (length(out) == 0) {
    return(tibble())
  }

  bind_rows(out)
}


# ---------- 4) aggregate all worksheets to one row per image ----------

#' Summarize an entire workbook at image level
#'
#' Applies [parse_sheet()] to every worksheet, combines all mitochondrion-level
#' observations, and aggregates them by worksheet-derived group and image ID.
#'
#' @param path Character scalar. Path to a manual or automated source workbook.
#'
#' @return A tibble with one row per unique `group` and `image_id`. The output
#'   contains the number of parsed mitochondria, the total cristae count, the
#'   pooled number of cristae per mitochondrion, and class-specific totals for
#'   classes 2-12. An empty tibble is returned when no valid rows are found.
#'
#' @details `mean_per_mito` is calculated as `sum(mito_total) / n_mito`. It is
#'   therefore the pooled cristae rate for the complete image, not an average of
#'   separately rounded values.
#'
summarize_workbook <- function(path) {

  sh <- excel_sheets(path)

  per_mito <- lapply(
    sh,
    function(s) parse_sheet(path, s)
  ) |>
    bind_rows()

  if (nrow(per_mito) == 0) {
    return(tibble())
  }

  per_image <- per_mito |>
    group_by(
      group,
      image_id
    ) |>
    summarise(
      # Number of mitochondria equals the number of valid parsed rows.
      n_mito = n(),

      # Total cristae count summed across all mitochondria in the image.
      total = sum(mito_total),

      # Image-level rate: total cristae divided by the number of mitochondria.
      mean_per_mito = total / n_mito,

      label_2 = sum(label_2),
      label_3 = sum(label_3),
      label_4 = sum(label_4),
      label_5 = sum(label_5),
      label_6 = sum(label_6),
      label_7 = sum(label_7),
      label_8 = sum(label_8),
      label_9 = sum(label_9),
      label_10 = sum(label_10),
      label_11 = sum(label_11),
      label_12 = sum(label_12),

      .groups = "drop"
    )

  per_image
}


# ---------- 5) parse and aggregate the automated and manual workbooks ----------

cat("Processing the automated workbook.\n")

auto_img <- summarize_workbook(auto_path) |>
  rename(
    auto_n_mito = n_mito,
    auto_total = total,
    auto_mean_per_mito = mean_per_mito,
    auto_label_2 = label_2,
    auto_label_3 = label_3,
    auto_label_4 = label_4,
    auto_label_5 = label_5,
    auto_label_6 = label_6,
    auto_label_7 = label_7,
    auto_label_8 = label_8,
    auto_label_9 = label_9,
    auto_label_10 = label_10,
    auto_label_11 = label_11,
    auto_label_12 = label_12
  )

cat("Processing the manual workbook.\n")

man_img <- summarize_workbook(man_path) |>
  rename(
    manual_n_mito = n_mito,
    manual_total = total,
    manual_mean_per_mito = mean_per_mito,
    manual_label_2 = label_2,
    manual_label_3 = label_3,
    manual_label_4 = label_4,
    manual_label_5 = label_5,
    manual_label_6 = label_6,
    manual_label_7 = label_7,
    manual_label_8 = label_8,
    manual_label_9 = label_9,
    manual_label_10 = label_10,
    manual_label_11 = label_11,
    manual_label_12 = label_12
  )


# ---------- 6) join manual and automated image-level results ----------

compare <- full_join(
  man_img,
  auto_img,
  by = c(
    "group",
    "image_id"
  )
) |>
  arrange(
    group,
    image_id
  )


# ---------- 6a) identify images missing from either method ----------

qc_missing_in_auto <- compare |>
  filter(is.na(auto_total)) |>
  select(
    group,
    image_id,
    manual_total
  )

qc_missing_in_manual <- compare |>
  filter(is.na(manual_total)) |>
  select(
    group,
    image_id,
    auto_total
  )


# Prism comparison tables require paired images measured by both methods.
compare_paired <- compare |>
  filter(
    !is.na(manual_total) &
      !is.na(auto_total)
  )


# ---------- 7) construct Prism-ready worksheets ----------

BA_total <- compare_paired |>
  select(
    manual_total,
    auto_total
  )

Scatter_total <- compare_paired |>
  transmute(
    image_id = image_id,
    X_manual_total = manual_total,
    Y_auto_total = auto_total
  )

BA_mean_per_mito <- compare_paired |>
  select(
    manual_mean_per_mito,
    auto_mean_per_mito
  )

Scatter_mean_per_mito <- compare_paired |>
  transmute(
    image_id = image_id,
    X_manual_mean_per_mito = manual_mean_per_mito,
    Y_auto_mean_per_mito = auto_mean_per_mito
  )

# Image-level class totals for method-specific Bland-Altman analyses.
BA_label_totals <- compare_paired |>
  select(
    image_id,
    group,
    starts_with("manual_label_"),
    starts_with("auto_label_")
  )


# ---------- 8) export the combined workbook ----------

write_xlsx(
  list(
    compare_images = compare,
    BA_total = BA_total,
    Scatter_total = Scatter_total,
    BA_mean_per_mito = BA_mean_per_mito,
    Scatter_mean_per_mito = Scatter_mean_per_mito,
    BA_label_totals = BA_label_totals,
    QC_missing_in_auto = qc_missing_in_auto,
    QC_missing_in_manual = qc_missing_in_manual
  ),
  path = out_file
)


# ---------- 9) print a concise run summary ----------

cat("\nCOMPLETED.\n")
cat(
  "Output workbook was saved to:\n",
  out_file,
  "\n"
)

cat(
  "Rows in compare_images:",
  nrow(compare),
  "\n"
)

cat(
  "Paired images:",
  nrow(compare_paired),
  "\n"
)

cat(
  "Images missing from Automated:",
  nrow(qc_missing_in_auto),
  "\n"
)

cat(
  "Images missing from Manual:",
  nrow(qc_missing_in_manual),
  "\n"
)
