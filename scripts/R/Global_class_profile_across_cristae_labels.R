#!/usr/bin/env Rscript

# ==============================================================================
# GLOBAL CLASS PROFILE ACROSS CRISTAE LABELS
# ==============================================================================
# Repository execution:
#   Rscript scripts/R/Global_class_profile_across_cristae_labels.R
#
# Input workbooks:
#   data/curated/cristae_manual.xlsx
#   data/curated/cristae_automated.xlsx
#
# Output directory:
#   results/derived/global_class_profile/
#
# Analytical principle:
#   1. Sum all valid values in Label 2 through Label 12 separately for the
#      manual and automated workbooks.
#   2. Calculate the relative abundance of each label within each method:
#
#        label percentage = label total / sum of totals for Label 2:12 * 100
#
#   3. Display the two relative-abundance profiles using the original dumbbell
#      plot design.
# ==============================================================================

options(stringsAsFactors = FALSE)

# ==============================================================================
# STEP 1 — VERIFY REQUIRED PACKAGES
# ==============================================================================

required_packages <- c(
  "readxl",
  "dplyr",
  "tidyr",
  "ggplot2",
  "openxlsx"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0L) {
  stop(
    "Missing required R package(s): ",
    paste(missing_packages, collapse = ", "),
    ". Install the missing package(s) before running this script.",
    call. = FALSE
  )
}

cat("[1/8] Required R packages are available.\n")

# ==============================================================================
# STEP 2 — DEFINE REPOSITORY PATHS AND EXPECTED LABELS
# ==============================================================================

repo_root <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

manual_file <- file.path(
  repo_root,
  "data", "curated", "cristae_manual.xlsx"
)

automated_file <- file.path(
  repo_root,
  "data", "curated", "cristae_automated.xlsx"
)

output_dir <- file.path(
  repo_root,
  "results", "derived", "global_class_profile"
)

output_data <- file.path(
  output_dir,
  "global_class_profile_data.xlsx"
)

output_png <- file.path(
  output_dir,
  "global_class_profile_dumbbell_colored.png"
)

output_pdf <- file.path(
  output_dir,
  "global_class_profile_dumbbell_colored.pdf"
)

label_order <- paste("Label", 2:12)

cat("[2/8] Repository paths and expected labels were defined.\n")

# ==============================================================================
# STEP 3 — VERIFY INPUT FILES AND CREATE OUTPUT DIRECTORY
# ==============================================================================

missing_input_files <- c(manual_file, automated_file)[
  !file.exists(c(manual_file, automated_file))
]

if (length(missing_input_files) > 0L) {
  stop(
    "Required input workbook(s) not found:\n  ",
    paste(missing_input_files, collapse = "\n  "),
    "\nRun the script from the repository root and verify the paths under ",
    "data/curated/.",
    call. = FALSE
  )
}

if (!dir.exists(output_dir)) {
  directory_created <- dir.create(
    output_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  if (!directory_created && !dir.exists(output_dir)) {
    stop(
      "The output directory could not be created: ",
      output_dir,
      call. = FALSE
    )
  }
}

cat("[3/8] Input workbooks were found and the output directory is ready.\n")

# ==============================================================================
# STEP 4 — DEFINE DATA-IMPORT AND VALIDATION FUNCTIONS
# ==============================================================================

# Convert values stored as numbers or numeric text to numeric values.
# Decimal commas and non-breaking spaces are supported. Non-numeric cells,
# including repeated header rows, are converted to NA and excluded from sums.
to_numeric <- function(x) {
  x <- trimws(as.character(x))
  x[x == ""] <- NA_character_
  x <- gsub("\u00A0", "", x, fixed = TRUE)
  x <- gsub(" ", "", x, fixed = TRUE)
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# Read one original workbook and sum Label 2 through Label 12 across all
# worksheets containing the complete label set. The source workbooks contain
# repeated header rows between image blocks; these rows are automatically
# ignored because their label cells are non-numeric.
summarize_cristae_workbook <- function(workbook_path, method_name) {
  sheet_names <- readxl::excel_sheets(workbook_path)

  if (length(sheet_names) == 0L) {
    stop(
      method_name,
      " workbook contains no worksheets: ",
      workbook_path,
      call. = FALSE
    )
  }

  workbook_totals <- stats::setNames(
    numeric(length(label_order)),
    label_order
  )

  data_sheets_found <- 0L
  valid_numeric_values <- 0L

  for (sheet_name in sheet_names) {
    raw_sheet <- readxl::read_excel(
      path = workbook_path,
      sheet = sheet_name,
      col_names = FALSE,
      col_types = "text",
      .name_repair = "minimal"
    )

    if (nrow(raw_sheet) == 0L || ncol(raw_sheet) == 0L) {
      next
    }

    raw_sheet <- as.data.frame(
      lapply(raw_sheet, function(column) trimws(as.character(column))),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )

    # Identify the unique worksheet column containing each required label.
    label_columns <- lapply(label_order, function(label_name) {
      which(vapply(
        raw_sheet,
        function(column) any(column == label_name, na.rm = TRUE),
        logical(1)
      ))
    })
    names(label_columns) <- label_order

    labels_present <- vapply(label_columns, length, integer(1)) > 0L

    # Worksheets without any target labels are ignored. A partial target-label
    # set is considered malformed and causes an explicit error.
    if (!any(labels_present)) {
      next
    }

    if (!all(labels_present)) {
      stop(
        method_name,
        " workbook, worksheet '", sheet_name,
        "', does not contain the complete set of columns Label 2 through ",
        "Label 12. Missing: ",
        paste(label_order[!labels_present], collapse = ", "),
        call. = FALSE
      )
    }

    ambiguous_labels <- names(label_columns)[
      vapply(label_columns, length, integer(1)) != 1L
    ]

    if (length(ambiguous_labels) > 0L) {
      stop(
        method_name,
        " workbook, worksheet '", sheet_name,
        "', contains ambiguous column positions for: ",
        paste(ambiguous_labels, collapse = ", "),
        call. = FALSE
      )
    }

    data_sheets_found <- data_sheets_found + 1L

    for (label_name in label_order) {
      column_index <- label_columns[[label_name]][1]
      numeric_values <- to_numeric(raw_sheet[[column_index]])
      finite_values <- numeric_values[is.finite(numeric_values)]

      workbook_totals[[label_name]] <-
        workbook_totals[[label_name]] + sum(finite_values)

      valid_numeric_values <-
        valid_numeric_values + length(finite_values)
    }
  }

  if (data_sheets_found == 0L) {
    stop(
      method_name,
      " workbook does not contain columns Label 2 through Label 12: ",
      workbook_path,
      call. = FALSE
    )
  }

  if (valid_numeric_values == 0L) {
    stop(
      "No valid numeric cristae-label data could be obtained from the ",
      method_name,
      " workbook: ",
      workbook_path,
      call. = FALSE
    )
  }

  list(
    totals = workbook_totals,
    data_sheets_found = data_sheets_found,
    valid_numeric_values = valid_numeric_values
  )
}

cat("[4/8] Import and validation functions were defined.\n")

# ==============================================================================
# STEP 5 — CALCULATE MANUAL AND AUTOMATED LABEL TOTALS
# ==============================================================================

manual_summary <- summarize_cristae_workbook(
  workbook_path = manual_file,
  method_name = "Manual"
)

automated_summary <- summarize_cristae_workbook(
  workbook_path = automated_file,
  method_name = "Automated"
)

manual_total_sum <- sum(manual_summary$totals)
automated_total_sum <- sum(automated_summary$totals)

if (!is.finite(manual_total_sum) || manual_total_sum == 0) {
  stop(
    "The sum of manual values required for percentage calculation is zero ",
    "or non-finite.",
    call. = FALSE
  )
}

if (!is.finite(automated_total_sum) || automated_total_sum == 0) {
  stop(
    "The sum of automated values required for percentage calculation is ",
    "zero or non-finite.",
    call. = FALSE
  )
}

cat("[5/8] Manual and automated totals were calculated.\n")

# ==============================================================================
# STEP 6 — CALCULATE RELATIVE ABUNDANCE FOR EACH LABEL
# ==============================================================================

profile <- data.frame(
  class = label_order,
  Manual_total = as.numeric(manual_summary$totals[label_order]),
  Automated_total = as.numeric(automated_summary$totals[label_order]),
  stringsAsFactors = FALSE
)

profile$Manual_pct <-
  profile$Manual_total / manual_total_sum * 100

profile$Automated_pct <-
  profile$Automated_total / automated_total_sum * 100

if (
  nrow(profile) == 0L ||
  !any(is.finite(profile$Manual_total)) ||
  !any(is.finite(profile$Automated_total))
) {
  stop(
    "No valid summarized data are available for output or plotting.",
    call. = FALSE
  )
}

# Preserve the exact order Label 2 through Label 12 in the exported table.
profile <- profile[match(label_order, profile$class), , drop = FALSE]

cat("[6/8] Relative abundance was calculated for Label 2 through Label 12.\n")

# ==============================================================================
# STEP 7 — CREATE THE ORIGINAL DUMBBELL PLOT
# ==============================================================================

# Reverse factor levels only for plotting so that Label 2 appears at the top.
plot_profile <- profile |>
  dplyr::mutate(
    class = factor(class, levels = rev(label_order))
  )

points_df <- plot_profile |>
  dplyr::select(class, Manual_pct, Automated_pct) |>
  tidyr::pivot_longer(
    cols = c(Manual_pct, Automated_pct),
    names_to = "method",
    values_to = "pct"
  ) |>
  dplyr::mutate(
    method = dplyr::recode(
      method,
      Manual_pct = "Manual",
      Automated_pct = "Automated"
    )
  )

manual_color <- "#1f77b4"
auto_color   <- "#ff7f0e"

p <- ggplot2::ggplot() +
  ggplot2::geom_segment(
    data = plot_profile,
    ggplot2::aes(
      x = Manual_pct, xend = Automated_pct,
      y = class, yend = class
    ),
    linewidth = 1.0,
    color = "grey55"
  ) +
  ggplot2::geom_point(
    data = points_df,
    ggplot2::aes(x = pct, y = class, color = method),
    size = 4.0
  ) +
  ggplot2::scale_color_manual(
    values = c("Manual" = manual_color, "Automated" = auto_color)
  ) +
  ggplot2::labs(
    title = "Global class profile across cristae labels",
    x = "Relative abundance of class (%)",
    y = "Cristae label",
    color = NULL
  ) +
  ggplot2::theme_classic(base_size = 12) +
  ggplot2::theme(
    plot.title = ggplot2::element_text(
      face = "bold",
      size = 16,
      hjust = 0.5
    ),
    axis.title.x = ggplot2::element_text(
      face = "bold",
      size = 14
    ),
    axis.title.y = ggplot2::element_text(
      face = "bold",
      size = 14
    ),
    axis.text.x = ggplot2::element_text(
      size = 12
    ),
    axis.text.y = ggplot2::element_text(
      size = 12
    ),
    legend.position = c(0.88, 0.50),
    legend.justification = c(0.5, 0.5),
    legend.background = ggplot2::element_blank(),
    legend.text = ggplot2::element_text(
      size = 12
    )
  )

print(p)

cat("[7/8] The dumbbell plot was created using the original design.\n")

# ==============================================================================
# STEP 8 — EXPORT THE SUMMARY TABLE AND FIGURES
# ==============================================================================

openxlsx::write.xlsx(
  x = profile,
  file = output_data,
  overwrite = TRUE
)

ggplot2::ggsave(
  filename = output_png,
  plot = p,
  width = 9.0,
  height = 6.2,
  dpi = 300
)

ggplot2::ggsave(
  filename = output_pdf,
  plot = p,
  width = 9.0,
  height = 6.2
)

cat("[8/8] Output files were saved successfully.\n\n")
cat("Manual worksheets analyzed: ", manual_summary$data_sheets_found, "\n", sep = "")
cat("Automated worksheets analyzed: ", automated_summary$data_sheets_found, "\n", sep = "")
cat("Manual total across Label 2-12: ", manual_total_sum, "\n", sep = "")
cat("Automated total across Label 2-12: ", automated_total_sum, "\n\n", sep = "")
cat("Output data:\n  ", output_data, "\n", sep = "")
cat("PNG figure:\n  ", output_png, "\n", sep = "")
cat("PDF figure:\n  ", output_pdf, "\n", sep = "")
