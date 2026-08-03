# =============================================================================
# PREPARE PRISM INPUT
#
# Purpose:
#   Combine the curated manual and automated cristae workbooks into aligned
#   image-level tables for downstream statistical analyses and Prism.
#
# Expected inputs:
#   data/curated/cristae_manual*.xlsx
#   data/curated/cristae_automated*.xlsx
#
# Output:
#   results/derived/Prism_input.xlsx
#
# Run from the repository:
#   Rscript scripts/prepare_prism_input.R
# =============================================================================


# -----------------------------------------------------------------------------
# 1. Package checks
# -----------------------------------------------------------------------------

required_packages <- c(
  "readxl",
  "dplyr",
  "stringr",
  "tibble",
  "writexl"
)

missing_packages <- required_packages[
  !vapply(
    required_packages,
    requireNamespace,
    logical(1),
    quietly = TRUE
  )
]

if (length(missing_packages) > 0) {
  stop(
    paste0(
      "Missing R packages: ",
      paste(missing_packages, collapse = ", "),
      "\nInstall the project dependencies before running this script."
    ),
    call. = FALSE
  )
}


# -----------------------------------------------------------------------------
# 2. Locate repository and input files
# -----------------------------------------------------------------------------

find_repository_root <- function(start_directory = getwd()) {
  current_directory <- normalizePath(
    start_directory,
    winslash = "/",
    mustWork = TRUE
  )

  repeat {
    repository_marker_found <-
      dir.exists(file.path(current_directory, ".git")) ||
      file.exists(
        file.path(
          current_directory,
          "Mitochondrial-Ultrastructure-R-Analysis.Rproj"
        )
      ) ||
      (
        dir.exists(file.path(current_directory, "data")) &&
        dir.exists(file.path(current_directory, "scripts"))
      )

    if (repository_marker_found) {
      return(current_directory)
    }

    parent_directory <- dirname(current_directory)

    if (identical(parent_directory, current_directory)) {
      stop(
        "Repository root could not be located. Run the script from inside the repository.",
        call. = FALSE
      )
    }

    current_directory <- parent_directory
  }
}


find_single_input <- function(directory, pattern, description) {
  files <- list.files(
    path = directory,
    pattern = pattern,
    full.names = TRUE,
    ignore.case = TRUE
  )

  files <- files[!startsWith(basename(files), "~$")]

  if (length(files) == 0) {
    stop(
      paste0(
        "No ", description, " was found in:\n",
        directory
      ),
      call. = FALSE
    )
  }

  if (length(files) > 1) {
    stop(
      paste0(
        "More than one ", description, " was found:\n",
        paste(files, collapse = "\n"),
        "\nKeep exactly one final input workbook in data/curated."
      ),
      call. = FALSE
    )
  }

  normalizePath(files, winslash = "/", mustWork = TRUE)
}


repository_root <- find_repository_root()
curated_directory <- file.path(repository_root, "data", "curated")

manual_path <- find_single_input(
  directory = curated_directory,
  pattern = "^cristae_manual.*\\.xlsx$",
  description = "manual cristae workbook"
)

automated_path <- find_single_input(
  directory = curated_directory,
  pattern = "^cristae_automated.*\\.xlsx$",
  description = "automated cristae workbook"
)

output_directory <- file.path(repository_root, "results", "derived")
dir.create(output_directory, recursive = TRUE, showWarnings = FALSE)

output_path <- file.path(output_directory, "Prism_input.xlsx")

message("Manual workbook:    ", manual_path)
message("Automated workbook: ", automated_path)
message("Output workbook:    ", output_path)


# -----------------------------------------------------------------------------
# 3. Normalize group and subject identifiers
# -----------------------------------------------------------------------------

normalize_group <- function(sheet_name, image_id) {
  is_control_sheet <- stringr::str_detect(
    sheet_name,
    stringr::regex("^Ctrl", ignore_case = TRUE)
  )

  if (!is_control_sheet) {
    return(sheet_name)
  }

  dplyr::case_when(
    stringr::str_detect(image_id, "^C1_") ~ "Ctrl. R",
    stringr::str_detect(image_id, "^C2_") ~ "Ctrl. C",
    TRUE ~ NA_character_
  )
}


derive_subject_id <- function(group) {
  dplyr::case_when(
    group == "Ctrl. R" ~ "C1",
    group == "Ctrl. C" ~ "C2",
    TRUE ~ group
  )
}


# -----------------------------------------------------------------------------
# 4. Parse one worksheet
# -----------------------------------------------------------------------------

parse_sheet <- function(path, sheet_name) {
  raw_sheet <- readxl::read_excel(
    path,
    sheet = sheet_name,
    col_names = FALSE,
    .name_repair = "minimal"
  )

  if (nrow(raw_sheet) == 0) {
    return(tibble::tibble())
  }

  if (ncol(raw_sheet) < 13) {
    stop(
      paste0(
        "Worksheet '", sheet_name,
        "' in ", basename(path),
        " has fewer than 13 columns."
      ),
      call. = FALSE
    )
  }

  current_image <- NA_character_
  parsed_rows <- vector("list", length = 0)

  for (row_index in seq_len(nrow(raw_sheet))) {
    image_cell <- raw_sheet[[1]][row_index]
    mitochondrion_cell <- raw_sheet[[2]][row_index]

    image_text <- ifelse(
      is.na(image_cell),
      "",
      stringr::str_trim(as.character(image_cell))
    )

    # Start of a new table block.
    if (tolower(image_text) == "slice") {
      current_image <- NA_character_
      next
    }

    mitochondrion_id <- suppressWarnings(
      as.numeric(mitochondrion_cell)
    )

    # A data row is identified by a numeric mitochondrion ID in column B.
    if (is.na(mitochondrion_id)) {
      next
    }

    if (image_text != "") {
      current_image <- image_text
    }

    if (is.na(current_image) || current_image == "") {
      next
    }

    label_values <- raw_sheet[row_index, 3:13] |>
      unlist(use.names = FALSE) |>
      suppressWarnings(as.numeric())

    label_values[is.na(label_values)] <- 0

    parsed_rows[[length(parsed_rows) + 1]] <- tibble::tibble(
      source_sheet = sheet_name,
      image_id = current_image,
      workbook_row = row_index,
      mitochondrion_id = mitochondrion_id,
      mitochondrion_total = sum(label_values),
      label_2 = label_values[1],
      label_3 = label_values[2],
      label_4 = label_values[3],
      label_5 = label_values[4],
      label_6 = label_values[5],
      label_7 = label_values[6],
      label_8 = label_values[7],
      label_9 = label_values[8],
      label_10 = label_values[9],
      label_11 = label_values[10],
      label_12 = label_values[11]
    )
  }

  if (length(parsed_rows) == 0) {
    return(tibble::tibble())
  }

  dplyr::bind_rows(parsed_rows) |>
    dplyr::mutate(
      group = normalize_group(source_sheet, image_id),
      disease_status = dplyr::if_else(
        stringr::str_detect(group, "^Ctrl"),
        "Ctrl",
        "HD"
      ),
      subject_id = derive_subject_id(group)
    ) |>
    dplyr::relocate(
      group,
      disease_status,
      subject_id,
      image_id
    )
}


# -----------------------------------------------------------------------------
# 5. Parse and summarize one workbook
# -----------------------------------------------------------------------------

summarize_workbook <- function(path) {
  sheets <- readxl::excel_sheets(path)

  per_mitochondrion <- lapply(
    sheets,
    function(sheet_name) parse_sheet(path, sheet_name)
  ) |>
    dplyr::bind_rows()

  if (nrow(per_mitochondrion) == 0) {
    stop(
      paste0("No mitochondrial data rows were found in ", basename(path)),
      call. = FALSE
    )
  }

  invalid_control_groups <- per_mitochondrion |>
    dplyr::filter(
      stringr::str_detect(source_sheet, stringr::regex("^Ctrl", ignore_case = TRUE)),
      is.na(group)
    )

  if (nrow(invalid_control_groups) > 0) {
    print(
      invalid_control_groups |>
        dplyr::distinct(source_sheet, image_id)
    )

    stop(
      "At least one control image could not be assigned to C1 or C2.",
      call. = FALSE
    )
  }

  per_image <- per_mitochondrion |>
    dplyr::group_by(
      group,
      disease_status,
      subject_id,
      image_id
    ) |>
    dplyr::summarise(
      n_mito = dplyr::n(),
      total = sum(mitochondrion_total),
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

  list(
    per_mitochondrion = per_mitochondrion,
    per_image = per_image
  )
}


message("Reading manual workbook...")
manual_data <- summarize_workbook(manual_path)

message("Reading automated workbook...")
automated_data <- summarize_workbook(automated_path)


# -----------------------------------------------------------------------------
# 6. Prepare paired image-level data
# -----------------------------------------------------------------------------

manual_images <- manual_data$per_image |>
  dplyr::rename_with(
    function(column_name) paste0("manual_", column_name),
    -dplyr::all_of(c("group", "disease_status", "subject_id", "image_id"))
  )

automated_images <- automated_data$per_image |>
  dplyr::rename_with(
    function(column_name) paste0("auto_", column_name),
    -dplyr::all_of(c("group", "disease_status", "subject_id", "image_id"))
  )

join_columns <- c(
  "group",
  "disease_status",
  "subject_id",
  "image_id"
)

missing_in_automated <- dplyr::anti_join(
  manual_images,
  automated_images,
  by = join_columns
)

missing_in_manual <- dplyr::anti_join(
  automated_images,
  manual_images,
  by = join_columns
)

if (nrow(missing_in_automated) > 0) {
  print(
    missing_in_automated |>
      dplyr::select(dplyr::all_of(join_columns))
  )

  stop(
    "Some manual images are missing from the automated workbook.",
    call. = FALSE
  )
}

if (nrow(missing_in_manual) > 0) {
  print(
    missing_in_manual |>
      dplyr::select(dplyr::all_of(join_columns))
  )

  stop(
    "Some automated images are missing from the manual workbook.",
    call. = FALSE
  )
}

compare_images <- dplyr::inner_join(
  manual_images,
  automated_images,
  by = join_columns
)

expected_group_order <- c(
  "Ctrl. R",
  "Ctrl. C",
  paste0("P", 1:10)
)

compare_images <- compare_images |>
  dplyr::mutate(
    .group_order = match(group, expected_group_order)
  ) |>
  dplyr::arrange(.group_order, image_id) |>
  dplyr::select(-.group_order)


# -----------------------------------------------------------------------------
# 7. Mandatory QC checks
# -----------------------------------------------------------------------------

if (nrow(compare_images) != 100) {
  stop(
    paste0(
      "Expected 100 paired images, but found ",
      nrow(compare_images),
      "."
    ),
    call. = FALSE
  )
}

mitochondria_mismatch <- compare_images |>
  dplyr::filter(manual_n_mito != auto_n_mito) |>
  dplyr::select(
    group,
    subject_id,
    image_id,
    manual_n_mito,
    auto_n_mito
  )

if (nrow(mitochondria_mismatch) > 0) {
  print(mitochondria_mismatch)

  stop(
    "Manual and automated mitochondrion counts do not match for all images.",
    call. = FALSE
  )
}

if (
  any(compare_images$manual_n_mito <= 0) ||
  any(compare_images$auto_n_mito <= 0)
) {
  stop(
    "At least one image has a non-positive mitochondrion count.",
    call. = FALSE
  )
}


# -----------------------------------------------------------------------------
# 8. Prepare Prism and analysis sheets
# -----------------------------------------------------------------------------

BA_total <- compare_images |>
  dplyr::select(
    manual_total,
    auto_total
  )

Scatter_total <- compare_images |>
  dplyr::transmute(
    image_id,
    X_manual_total = manual_total,
    Y_auto_total = auto_total
  )

BA_mean_per_mito <- compare_images |>
  dplyr::select(
    manual_mean_per_mito,
    auto_mean_per_mito
  )

Scatter_mean_per_mito <- compare_images |>
  dplyr::transmute(
    image_id,
    X_manual_mean_per_mito = manual_mean_per_mito,
    Y_auto_mean_per_mito = auto_mean_per_mito
  )

BA_label_totals <- compare_images |>
  dplyr::select(
    image_id,
    group,
    subject_id,
    dplyr::starts_with("manual_label_"),
    dplyr::starts_with("auto_label_")
  )

QC_summary <- tibble::tibble(
  check = c(
    "paired_images",
    "manual_mitochondria",
    "automated_mitochondria",
    "mitochondrion_count_mismatches",
    "manual_total_cristae",
    "automated_total_cristae"
  ),
  value = as.character(
    c(
      nrow(compare_images),
      sum(compare_images$manual_n_mito),
      sum(compare_images$auto_n_mito),
      nrow(mitochondria_mismatch),
      sum(compare_images$manual_total),
      sum(compare_images$auto_total)
    )
  )
)


# -----------------------------------------------------------------------------
# 9. Export
# -----------------------------------------------------------------------------

writexl::write_xlsx(
  list(
    compare_images = compare_images,
    manual_per_mito = manual_data$per_mitochondrion,
    auto_per_mito = automated_data$per_mitochondrion,
    BA_total = BA_total,
    Scatter_total = Scatter_total,
    BA_mean_per_mito = BA_mean_per_mito,
    Scatter_mean_per_mito = Scatter_mean_per_mito,
    BA_label_totals = BA_label_totals,
    QC_summary = QC_summary,
    QC_n_mito_mismatch = mitochondria_mismatch
  ),
  path = output_path
)

message("")
message("Preparation completed successfully.")
message("Paired images: ", nrow(compare_images))
message("Mitochondria per method: ", sum(compare_images$manual_n_mito))
message("Manual cristae: ", sum(compare_images$manual_total))
message("Automated cristae: ", sum(compare_images$auto_total))
message("Output: ", output_path)
