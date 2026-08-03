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


# ---------- 0) instalace chybejicich balicku ----------

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


# ---------- 1) nacteni balicku ----------

library(readxl)
library(dplyr)
library(stringr)
library(tidyr)
library(writexl)
library(tibble)


# ---------- 2) cesty k souborum v repozitari ----------

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

cat("Strojovy soubor:\n", auto_path, "\n\n")
cat("Rucni soubor:\n", man_path, "\n\n")

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


# ---------- 3) funkce pro parsovani jednoho listu ----------

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

    # sloupec A = Slice / image_id
    a <- x[[1]][i]

    # sloupec B = Number of mito
    b <- x[[2]][i]

    a_str <- ifelse(
      is.na(a),
      "",
      as.character(a)
    )

    a_str_trim <- str_trim(a_str)

    # preskoc header radek bloku
    if (tolower(a_str_trim) == "slice") {
      current_image <- NA_character_
      next
    }

    # mito radek = ve sloupci B je cislo
    b_num <- suppressWarnings(
      as.numeric(b)
    )

    if (!is.na(b_num)) {

      # pokud je v A na tomto radku image ID, uloz ho
      if (a_str_trim != "") {
        current_image <- a_str_trim
      }

      # pokud image ID neni zname, tento radek preskoc
      if (
        is.na(current_image) ||
        current_image == ""
      ) {
        next
      }

      # labely jsou v C:M = sloupce 3:13
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


# ---------- 4) funkce pro souhrn celeho workbooku ----------

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
      # pocet mitochondrii = pocet platnych mito radku
      n_mito = n(),

      # celkovy pocet crist v obrazku
      total = sum(mito_total),

      # prumerny pocet crist na mitochondrii
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


# ---------- 5) nacti a spocitej oba excely ----------

cat("Zpracovavam strojovy excel.\n")

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

cat("Zpracovavam rucni excel.\n")

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


# ---------- 6) spojeni manual vs auto ----------

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


# ---------- 6a) QC listy ----------

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


# pouze sparovane radky pro Prism
compare_paired <- compare |>
  filter(
    !is.na(manual_total) &
      !is.na(auto_total)
  )


# ---------- 7) listy pro Prism ----------

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

# labelove soucty po obrazcich
BA_label_totals <- compare_paired |>
  select(
    image_id,
    group,
    starts_with("manual_label_"),
    starts_with("auto_label_")
  )


# ---------- 8) export ----------

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


# ---------- 9) zaverecny vypis ----------

cat("\nHOTOVO.\n")
cat(
  "Vystupni soubor byl ulozen sem:\n",
  out_file,
  "\n"
)

cat(
  "Pocet radku v compare_images:",
  nrow(compare),
  "\n"
)

cat(
  "Pocet sparovanych obrazku:",
  nrow(compare_paired),
  "\n"
)

cat(
  "Obrazky chybejici v Automated:",
  nrow(qc_missing_in_auto),
  "\n"
)

cat(
  "Obrazky chybejici v Manual:",
  nrow(qc_missing_in_manual),
  "\n"
)
