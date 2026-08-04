# ==============================================================================
# MANUAL VS AUTOMATED CRISTAE COUNTS
# Bland-Altman analysis, Pearson correlation and linear regression
# ==============================================================================
#
# PURPOSE
# This script reproduces the analysis and graph design prepared in GraphPad Prism:
#   1) aggregation of Label 2-12 counts to one total count per image,
#   2) exact pairing of manual and automated measurements by sheet + image ID,
#   3) Bland-Altman agreement analysis,
#   4) Pearson correlation and ordinary least-squares linear regression,
#   5) export of processed data, statistics and publication-quality figures.
#
# IMPORTANT STATISTICAL DEFINITIONS
# For image i:
#   difference_i = automated_i - manual_i
#   mean_i       = (automated_i + manual_i) / 2
#   bias         = mean(difference_i)
#   95% limits of agreement = bias +/- 1.96 * SD(difference_i)
#
# Pearson correlation describes association, not agreement. Agreement is assessed
# primarily with the Bland-Altman analysis. The linear regression reproduces the
# Prism scatter-plot analysis and is reported separately from agreement.
#
# EXPECTED INPUT STRUCTURE
# - One Excel workbook for manual evaluation and one for automated evaluation.
# - The workbooks contain corresponding sheets (for example Ctrl., P1, ..., P10).
# - Within each sheet, each image starts with its image ID in column 1.
# - Mitochondria belonging to that image continue on subsequent rows.
# - Columns 3-13 contain Label 2 through Label 12 counts.
# - Repeated rows labelled "Slice" and blank separator rows are allowed.
#
# The script does not pair observations by row order. It pairs them using the
# combination of sheet name and image ID and stops if pairing is incomplete.
# ==============================================================================


# ------------------------------------------------------------------------------
# STEP LABELS DISPLAYED IN THE R CONSOLE
# ------------------------------------------------------------------------------
# This function clearly reports the current stage of the analysis.
# It does not change the data, statistical calculations, or graph appearance.
announce_step <- function(step_number, step_title) {
  separator <- paste(rep("=", 78), collapse = "")
  cat("\n", separator, "\n", sep = "")
  cat(sprintf("STEP %s: %s\n", step_number, step_title))
  cat(separator, "\n", sep = "")
}

# ==============================================================================
# STEP 0: USER SETTINGS
# ==============================================================================
announce_step(0, "User analysis settings")

# Default filenames. If these files are not found in the current working
# directory, an interactive file-selection window will be opened in RStudio.
MANUAL_DEFAULT_FILE    <- "cristae_manual.xlsx"
AUTOMATED_DEFAULT_FILE <- "cristae_automated.xlsx"

# Set to FALSE if package installation must be managed manually.
INSTALL_MISSING_PACKAGES <- TRUE

# Graph settings. The generic "sans" family maps to an Arial/Helvetica-like font
# and is more portable across Windows, macOS and Linux than a hard-coded font.
GRAPH_FONT <- "sans"
POINT_SIZE <- 2.35
POINT_STROKE <- 0.45
LINE_WIDTH <- 0.70

# Figure dimensions in millimetres.
SINGLE_FIGURE_WIDTH_MM  <- 92
SINGLE_FIGURE_HEIGHT_MM <- 78
PANEL_FIGURE_WIDTH_MM   <- 184
PANEL_FIGURE_HEIGHT_MM  <- 78

# Raster export resolution.
RASTER_DPI <- 600


# ==============================================================================
# STEP 1: REQUIRED PACKAGES
# ==============================================================================
announce_step(1, "Check and load required R packages")

required_packages <- c(
  "readxl",
  "dplyr",
  "ggplot2",
  "openxlsx",
  "patchwork",
  "scales"
)

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0 && INSTALL_MISSING_PACKAGES) {
  message(
    "Installing missing packages: ",
    paste(missing_packages, collapse = ", ")
  )
  install.packages(missing_packages, repos = "https://cloud.r-project.org")
}

missing_packages <- required_packages[
  !vapply(required_packages, requireNamespace, logical(1), quietly = TRUE)
]

if (length(missing_packages) > 0) {
  stop(
    "The following required packages are not installed: ",
    paste(missing_packages, collapse = ", "),
    "\nInstall them and run the script again."
  )
}


# ==============================================================================
# STEP 2: SELECT INPUT FILES AND CREATE THE OUTPUT DIRECTORY
# ==============================================================================
announce_step(2, "Select input Excel workbooks and create the output folder")

select_excel_file <- function(default_file, prompt_text) {
  if (file.exists(default_file)) {
    return(normalizePath(default_file, winslash = "/", mustWork = TRUE))
  }

  if (!interactive()) {
    stop(
      "Input file was not found: ", default_file,
      "\nSet the correct path in STEP 0 before running non-interactively."
    )
  }

  message(prompt_text)
  selected_file <- file.choose()
  normalizePath(selected_file, winslash = "/", mustWork = TRUE)
}

manual_file <- select_excel_file(
  MANUAL_DEFAULT_FILE,
  "Select the Excel workbook containing MANUAL cristae counts."
)

automated_file <- select_excel_file(
  AUTOMATED_DEFAULT_FILE,
  "Select the Excel workbook containing AUTOMATED cristae counts."
)

if (identical(manual_file, automated_file)) {
  stop("The manual and automated input files must be different files.")
}

output_dir <- file.path(
  dirname(manual_file),
  "cristae_manual_vs_automated_results"
)

dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

message("Manual input:    ", manual_file)
message("Automated input: ", automated_file)
message("Output folder:   ", normalizePath(output_dir, winslash = "/"))


# ==============================================================================
# STEP 3: FUNCTIONS FOR READING THE BLOCK-STRUCTURED EXCEL WORKBOOKS
# ==============================================================================
announce_step(3, "Define functions for reading block-structured data")

# Convert a single Excel cell to a trimmed character value.
cell_to_text <- function(x) {
  if (length(x) == 0 || is.na(x)) {
    return("")
  }
  trimws(as.character(x))
}

# Convert counts safely to numeric values. Decimal commas are accepted.
safe_numeric <- function(x) {
  x <- as.character(x)
  x <- trimws(x)
  x[x == ""] <- NA_character_
  x <- gsub(",", ".", x, fixed = TRUE)
  suppressWarnings(as.numeric(x))
}

# Read one worksheet and aggregate Label 2-12 counts to the image level.
# Each image is represented by one output row.
summarise_one_sheet <- function(file_path, sheet_name) {
  raw <- readxl::read_excel(
    path = file_path,
    sheet = sheet_name,
    col_names = FALSE,
    .name_repair = "minimal"
  )

  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # Ensure that columns 1-13 always exist, even if trailing columns are empty.
  if (ncol(raw) < 13) {
    for (j in seq_len(13 - ncol(raw))) {
      raw[[ncol(raw) + 1]] <- NA
    }
  }
  raw <- raw[, seq_len(13), drop = FALSE]

  label_names <- paste0("Label_", 2:12)
  result_rows <- list()

  current_image <- NULL
  current_counts <- rep(0, length(label_names))
  current_mitochondria_rows <- 0L

  # Save the currently open image block and reset the block variables.
  flush_current_image <- function() {
    if (!is.null(current_image)) {
      one_row <- data.frame(
        group = trimws(sheet_name),
        image_id = current_image,
        mitochondria_rows = current_mitochondria_rows,
        total_cristae = sum(current_counts),
        stringsAsFactors = FALSE,
        check.names = FALSE
      )

      for (k in seq_along(label_names)) {
        one_row[[label_names[k]]] <- current_counts[k]
      }

      result_rows[[length(result_rows) + 1L]] <<- one_row
    }

    current_image <<- NULL
    current_counts <<- rep(0, length(label_names))
    current_mitochondria_rows <<- 0L
  }

  if (nrow(raw) > 0) {
    for (i in seq_len(nrow(raw))) {
      first_cell <- cell_to_text(raw[[1]][i])
      second_cell <- cell_to_text(raw[[2]][i])

      # Repeated table headers separate image blocks and are not data.
      if (tolower(first_cell) == "slice") {
        flush_current_image()
        next
      }

      # A non-empty first cell starts a new image block.
      if (nzchar(first_cell)) {
        flush_current_image()
        current_image <- first_cell
      } else if (!nzchar(second_cell)) {
        # A row without image ID and without mitochondrion number is a separator.
        flush_current_image()
        next
      }

      # Count a row only when an image block is active and a mitochondrion number
      # is present in column 2.
      if (!is.null(current_image) && nzchar(second_cell)) {
        row_counts <- vapply(
          raw[i, 3:13, drop = FALSE],
          function(z) safe_numeric(z[[1]]),
          numeric(1)
        )

        row_counts[is.na(row_counts)] <- 0
        current_counts <- current_counts + row_counts
        current_mitochondria_rows <- current_mitochondria_rows + 1L
      }
    }
  }

  flush_current_image()

  if (length(result_rows) == 0) {
    return(data.frame())
  }

  dplyr::bind_rows(result_rows)
}

# Read all worksheets from one workbook.
summarise_workbook <- function(file_path) {
  sheet_names <- readxl::excel_sheets(file_path)

  workbook_rows <- lapply(
    sheet_names,
    function(sheet_name) summarise_one_sheet(file_path, sheet_name)
  )

  output <- dplyr::bind_rows(workbook_rows)

  if (nrow(output) == 0) {
    stop("No image-level data were detected in: ", file_path)
  }

  output
}


# ==============================================================================
# STEP 4: READ AND SUMMARISE MANUAL AND AUTOMATED DATA
# ==============================================================================
announce_step(4, "Read data and sum Label 2–12 counts for each image")

message("Reading and aggregating the manual workbook...")
manual_summary <- summarise_workbook(manual_file)
message("Manual images detected: ", nrow(manual_summary))

message("Reading and aggregating the automated workbook...")
automated_summary <- summarise_workbook(automated_file)
message("Automated images detected: ", nrow(automated_summary))

# Place Label columns before the total for easier checking in Excel.
summary_column_order <- c(
  "group",
  "image_id",
  "mitochondria_rows",
  paste0("Label_", 2:12),
  "total_cristae"
)

manual_summary <- manual_summary[, summary_column_order, drop = FALSE]
automated_summary <- automated_summary[, summary_column_order, drop = FALSE]


# ==============================================================================
# STEP 5: VALIDATE IDENTIFIERS AND PAIR THE TWO METHODS
# ==============================================================================
announce_step(5, "Validate identifiers and pair the two methods exactly")

check_duplicate_keys <- function(data, method_name) {
  duplicates <- data |>
    dplyr::count(group, image_id, name = "number_of_occurrences") |>
    dplyr::filter(number_of_occurrences > 1)

  if (nrow(duplicates) > 0) {
    stop(
      "Duplicate sheet + image ID combinations were detected in the ",
      method_name,
      " workbook. Pairing would be ambiguous.\nExamples:\n",
      paste(
        utils::capture.output(print(utils::head(duplicates, 10))),
        collapse = "\n"
      )
    )
  }
}

check_duplicate_keys(manual_summary, "manual")
check_duplicate_keys(automated_summary, "automated")

manual_keys <- manual_summary |>
  dplyr::select(group, image_id)

automated_keys <- automated_summary |>
  dplyr::select(group, image_id)

missing_in_automated <- dplyr::anti_join(
  manual_keys,
  automated_keys,
  by = c("group", "image_id")
)

missing_in_manual <- dplyr::anti_join(
  automated_keys,
  manual_keys,
  by = c("group", "image_id")
)

if (nrow(missing_in_automated) > 0 || nrow(missing_in_manual) > 0) {
  mismatch_file <- file.path(output_dir, "PAIRING_MISMATCHES.xlsx")

  openxlsx::write.xlsx(
    list(
      Missing_in_automated = missing_in_automated,
      Missing_in_manual = missing_in_manual
    ),
    file = mismatch_file,
    overwrite = TRUE
  )

  stop(
    "Manual and automated images could not be paired completely.\n",
    "A list of mismatches was saved to:\n",
    mismatch_file
  )
}

# Exact pairing by group and image ID. The order of the manual workbook is kept.
paired_data <- manual_summary |>
  dplyr::select(
    group,
    image_id,
    manual_mitochondria_rows = mitochondria_rows,
    manual_total = total_cristae
  ) |>
  dplyr::inner_join(
    automated_summary |>
      dplyr::select(
        group,
        image_id,
        automated_mitochondria_rows = mitochondria_rows,
        automated_total = total_cristae
      ),
    by = c("group", "image_id")
  ) |>
  dplyr::mutate(
    observation_id = dplyr::row_number(),
    mean_count = (manual_total + automated_total) / 2,
    difference = automated_total - manual_total
  ) |>
  dplyr::select(
    observation_id,
    group,
    image_id,
    manual_mitochondria_rows,
    automated_mitochondria_rows,
    manual_total,
    automated_total,
    mean_count,
    difference
  )

message("Successfully paired images: ", nrow(paired_data))

if (nrow(paired_data) < 3) {
  stop("At least three paired images are required for the analysis.")
}

if (any(!is.finite(paired_data$manual_total)) ||
    any(!is.finite(paired_data$automated_total))) {
  stop("Non-finite totals were detected after aggregation.")
}

if (any(paired_data$manual_total < 0) ||
    any(paired_data$automated_total < 0)) {
  warning("Negative count values were detected. Please check the input files.")
}

if (any(abs(paired_data$manual_total - round(paired_data$manual_total)) > 1e-8) ||
    any(abs(paired_data$automated_total - round(paired_data$automated_total)) > 1e-8)) {
  warning("Some cristae totals are not integers. Please verify the input counts.")
}


# ==============================================================================
# STEP 6: BLAND-ALTMAN AGREEMENT ANALYSIS
# ==============================================================================
announce_step(6, "Bland–Altman agreement analysis")

n_pairs <- nrow(paired_data)
differences <- paired_data$difference

bias <- mean(differences)
sd_difference <- stats::sd(differences)

# Prism-style 95% limits of agreement use 1.96 SD.
z_loa <- 1.96
lower_loa <- bias - z_loa * sd_difference
upper_loa <- bias + z_loa * sd_difference

# 95% confidence interval for the mean difference (bias).
t_critical <- stats::qt(0.975, df = n_pairs - 1)
se_bias <- sd_difference / sqrt(n_pairs)
bias_ci_lower <- bias - t_critical * se_bias
bias_ci_upper <- bias + t_critical * se_bias

# Approximate 95% confidence intervals for each limit of agreement.
# SE(LoA) = SD * sqrt(1/n + z^2 / (2*(n-1)))
se_loa <- sd_difference * sqrt(
  1 / n_pairs + z_loa^2 / (2 * (n_pairs - 1))
)

lower_loa_ci_lower <- lower_loa - t_critical * se_loa
lower_loa_ci_upper <- lower_loa + t_critical * se_loa
upper_loa_ci_lower <- upper_loa - t_critical * se_loa
upper_loa_ci_upper <- upper_loa + t_critical * se_loa

outside_loa <- paired_data$difference < lower_loa |
  paired_data$difference > upper_loa

message(sprintf("Bland–Altman bias: %.4f", bias))
message(sprintf("95%% limits of agreement: %.4f to %.4f", lower_loa, upper_loa))

bland_altman_statistics <- data.frame(
  statistic = c(
    "Number of paired images",
    "Bias: mean(automated - manual)",
    "SD of differences",
    "Lower 95% limit of agreement",
    "Upper 95% limit of agreement",
    "Images outside limits of agreement",
    "Percentage outside limits of agreement"
  ),
  estimate = c(
    n_pairs,
    bias,
    sd_difference,
    lower_loa,
    upper_loa,
    sum(outside_loa),
    100 * mean(outside_loa)
  ),
  ci_95_lower = c(
    NA,
    bias_ci_lower,
    NA,
    lower_loa_ci_lower,
    upper_loa_ci_lower,
    NA,
    NA
  ),
  ci_95_upper = c(
    NA,
    bias_ci_upper,
    NA,
    lower_loa_ci_upper,
    upper_loa_ci_upper,
    NA,
    NA
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# STEP 7: PEARSON CORRELATION AND LINEAR REGRESSION
# ==============================================================================
announce_step(7, "Pearson correlation, linear regression, and diagnostics")

pearson_test <- stats::cor.test(
  paired_data$manual_total,
  paired_data$automated_total,
  method = "pearson",
  conf.level = 0.95
)

pearson_r <- unname(pearson_test$estimate)

correlation_statistics <- data.frame(
  statistic = c(
    "Number of paired images",
    "Pearson r",
    "Pearson r 95% CI lower",
    "Pearson r 95% CI upper",
    "Two-sided p-value"
  ),
  estimate = c(
    n_pairs,
    pearson_r,
    pearson_test$conf.int[1],
    pearson_test$conf.int[2],
    pearson_test$p.value
  ),
  stringsAsFactors = FALSE
)

# Ordinary least-squares regression, matching the Prism scatter analysis:
# automated_total = intercept + slope * manual_total
regression_model <- stats::lm(
  automated_total ~ manual_total,
  data = paired_data
)

regression_summary <- summary(regression_model)
regression_coefficients <- stats::coef(regression_model)
regression_confidence_intervals <- stats::confint(
  regression_model,
  level = 0.95
)

regression_statistics <- data.frame(
  term = c(
    "Intercept",
    "Slope",
    "R-squared",
    "Adjusted R-squared",
    "Residual standard error",
    "Number of paired images"
  ),
  estimate = c(
    regression_coefficients[["(Intercept)"]],
    regression_coefficients[["manual_total"]],
    regression_summary$r.squared,
    regression_summary$adj.r.squared,
    regression_summary$sigma,
    n_pairs
  ),
  ci_95_lower = c(
    regression_confidence_intervals["(Intercept)", 1],
    regression_confidence_intervals["manual_total", 1],
    NA,
    NA,
    NA,
    NA
  ),
  ci_95_upper = c(
    regression_confidence_intervals["(Intercept)", 2],
    regression_confidence_intervals["manual_total", 2],
    NA,
    NA,
    NA,
    NA
  ),
  p_value = c(
    regression_summary$coefficients["(Intercept)", "Pr(>|t|)"],
    regression_summary$coefficients["manual_total", "Pr(>|t|)"],
    NA,
    NA,
    NA,
    NA
  ),
  stringsAsFactors = FALSE
)

# Diagnostic test for proportional bias in the Bland-Altman plot.
# A non-zero slope of difference vs mean_count indicates that the difference
# between methods changes systematically with measurement magnitude.
proportional_bias_model <- stats::lm(difference ~ mean_count, data = paired_data)
proportional_bias_summary <- summary(proportional_bias_model)
proportional_bias_ci <- stats::confint(proportional_bias_model, level = 0.95)

# Shapiro-Wilk is reported only as a diagnostic for the distribution of paired
# differences. Visual inspection of the Bland-Altman plot remains important.
if (n_pairs >= 3 && n_pairs <= 5000) {
  shapiro_result <- stats::shapiro.test(differences)
  shapiro_w <- unname(shapiro_result$statistic)
  shapiro_p <- shapiro_result$p.value
} else {
  shapiro_w <- NA_real_
  shapiro_p <- NA_real_
}

message(sprintf("Pearson r: %.4f", pearson_r))
message(sprintf(
  "Regression: automated = %.4f + %.4f × manual",
  regression_coefficients[["(Intercept)"]],
  regression_coefficients[["manual_total"]]
))

diagnostic_statistics <- data.frame(
  diagnostic = c(
    "Proportional-bias slope: difference ~ mean_count",
    "Proportional-bias slope 95% CI lower",
    "Proportional-bias slope 95% CI upper",
    "Proportional-bias slope p-value",
    "Shapiro-Wilk W for paired differences",
    "Shapiro-Wilk p-value for paired differences"
  ),
  estimate = c(
    stats::coef(proportional_bias_model)[["mean_count"]],
    proportional_bias_ci["mean_count", 1],
    proportional_bias_ci["mean_count", 2],
    proportional_bias_summary$coefficients["mean_count", "Pr(>|t|)"],
    shapiro_w,
    shapiro_p
  ),
  stringsAsFactors = FALSE
)


# ==============================================================================
# STEP 8: CREATE GRAPHPAD-LIKE FIGURES
# ==============================================================================
announce_step(8, "Create GraphPad Prism-style figures")

# A restrained Prism-like theme: white background, black axes, no grid and no
# legend for a single paired dataset.
prism_like_theme <- function() {
  ggplot2::theme_classic(base_family = GRAPH_FONT, base_size = 10.5) +
    ggplot2::theme(
      axis.line = ggplot2::element_line(
        colour = "black",
        linewidth = 0.55
      ),
      axis.ticks = ggplot2::element_line(
        colour = "black",
        linewidth = 0.55
      ),
      axis.ticks.length = grid::unit(2.2, "mm"),
      axis.text = ggplot2::element_text(
        colour = "black",
        size = 9.5
      ),
      axis.title = ggplot2::element_text(
        colour = "black",
        size = 10.5,
        face = "plain"
      ),
      axis.title.x = ggplot2::element_text(
        margin = ggplot2::margin(t = 7)
      ),
      axis.title.y = ggplot2::element_text(
        margin = ggplot2::margin(r = 7)
      ),
      plot.title = ggplot2::element_text(
        colour = "black",
        size = 11.5,
        face = "bold",
        hjust = 0.5,
        lineheight = 0.95,
        margin = ggplot2::margin(b = 8)
      ),
      plot.margin = ggplot2::margin(8, 10, 8, 8),
      legend.position = "none"
    )
}

# ----- Bland-Altman plot -----
ba_x_max <- max(10, ceiling(max(paired_data$mean_count) * 1.05 / 10) * 10)

ba_y_data_min <- min(c(paired_data$difference, lower_loa))
ba_y_data_max <- max(c(paired_data$difference, upper_loa))
ba_y_span <- ba_y_data_max - ba_y_data_min
if (!is.finite(ba_y_span) || ba_y_span == 0) {
  ba_y_span <- 2
}
ba_y_padding <- max(2, 0.14 * ba_y_span)
ba_y_limits <- c(
  ba_y_data_min - ba_y_padding,
  ba_y_data_max + ba_y_padding
)

ba_annotation_x <- 0.04 * ba_x_max
ba_annotation_y <- ba_y_limits[2] - 0.035 * diff(ba_y_limits)

ba_annotation <- sprintf(
  "Bias = %.2f\n95%% LoA = %.2f to %.2f",
  bias,
  lower_loa,
  upper_loa
)

bland_altman_plot <- ggplot2::ggplot(
  paired_data,
  ggplot2::aes(x = mean_count, y = difference)
) +
  ggplot2::geom_hline(
    yintercept = lower_loa,
    linewidth = LINE_WIDTH,
    linetype = "dashed",
    colour = "black"
  ) +
  ggplot2::geom_hline(
    yintercept = upper_loa,
    linewidth = LINE_WIDTH,
    linetype = "dashed",
    colour = "black"
  ) +
  ggplot2::geom_hline(
    yintercept = bias,
    linewidth = LINE_WIDTH,
    linetype = "solid",
    colour = "black"
  ) +
  ggplot2::geom_point(
    shape = 21,
    size = POINT_SIZE,
    stroke = POINT_STROKE,
    fill = "black",
    colour = "black"
  ) +
  ggplot2::annotate(
    geom = "text",
    x = ba_annotation_x,
    y = ba_annotation_y,
    label = ba_annotation,
    hjust = 0,
    vjust = 1,
    family = GRAPH_FONT,
    size = 3.25,
    lineheight = 1.05,
    colour = "black"
  ) +
  ggplot2::scale_x_continuous(
    limits = c(0, ba_x_max),
    breaks = scales::pretty_breaks(n = 6),
    expand = ggplot2::expansion(mult = c(0, 0))
  ) +
  ggplot2::scale_y_continuous(
    breaks = scales::pretty_breaks(n = 6),
    expand = ggplot2::expansion(mult = c(0, 0))
  ) +
  ggplot2::coord_cartesian(ylim = ba_y_limits, clip = "off") +
  ggplot2::labs(
    title = "Bland\nAltman agreement plot",
    x = "Mean count per image",
    y = "Automated - manual count"
  ) +
  prism_like_theme()

# ----- Scatter plot with Prism-style linear regression and Pearson r -----
xy_maximum <- max(
  paired_data$manual_total,
  paired_data$automated_total,
  na.rm = TRUE
)
xy_axis_max <- max(10, ceiling(xy_maximum * 1.05 / 10) * 10)

scatter_annotation <- sprintf("r = %.4f", pearson_r)

scatter_plot <- ggplot2::ggplot(
  paired_data,
  ggplot2::aes(x = manual_total, y = automated_total)
) +
  ggplot2::geom_abline(
    intercept = regression_coefficients[["(Intercept)"]],
    slope = regression_coefficients[["manual_total"]],
    linewidth = LINE_WIDTH,
    linetype = "solid",
    colour = "black"
  ) +
  ggplot2::geom_point(
    shape = 21,
    size = POINT_SIZE,
    stroke = POINT_STROKE,
    fill = "black",
    colour = "black"
  ) +
  ggplot2::annotate(
    geom = "text",
    x = 0.06 * xy_axis_max,
    y = 0.94 * xy_axis_max,
    label = scatter_annotation,
    hjust = 0,
    vjust = 1,
    family = GRAPH_FONT,
    size = 3.4,
    colour = "black"
  ) +
  ggplot2::scale_x_continuous(
    limits = c(0, xy_axis_max),
    breaks = scales::pretty_breaks(n = 6),
    expand = ggplot2::expansion(mult = c(0, 0))
  ) +
  ggplot2::scale_y_continuous(
    limits = c(0, xy_axis_max),
    breaks = scales::pretty_breaks(n = 6),
    expand = ggplot2::expansion(mult = c(0, 0))
  ) +
  ggplot2::coord_equal(clip = "off") +
  ggplot2::labs(
    title = "Manual vs automated cristae counts",
    x = "Manual count per image",
    y = "Automated count per image"
  ) +
  prism_like_theme()

# Combined two-panel figure.
combined_plot <- bland_altman_plot + scatter_plot +
  patchwork::plot_layout(ncol = 2, widths = c(1, 1))


# ==============================================================================
# STEP 9: EXPORT FIGURES AS PDF, PNG AND TIFF
# ==============================================================================
announce_step(9, "Export figures as PDF, PNG, and TIFF")

save_plot_all_formats <- function(plot_object, base_filename, width_mm, height_mm) {
  pdf_file <- file.path(output_dir, paste0(base_filename, ".pdf"))
  png_file <- file.path(output_dir, paste0(base_filename, ".png"))
  tiff_file <- file.path(output_dir, paste0(base_filename, ".tiff"))

  ggplot2::ggsave(
    filename = pdf_file,
    plot = plot_object,
    width = width_mm,
    height = height_mm,
    units = "mm",
    device = "pdf"
  )

  ggplot2::ggsave(
    filename = png_file,
    plot = plot_object,
    width = width_mm,
    height = height_mm,
    units = "mm",
    dpi = RASTER_DPI,
    bg = "white"
  )

  ggplot2::ggsave(
    filename = tiff_file,
    plot = plot_object,
    width = width_mm,
    height = height_mm,
    units = "mm",
    dpi = RASTER_DPI,
    compression = "lzw",
    bg = "white"
  )
}

save_plot_all_formats(
  bland_altman_plot,
  "Bland_Altman_agreement_plot",
  SINGLE_FIGURE_WIDTH_MM,
  SINGLE_FIGURE_HEIGHT_MM
)

save_plot_all_formats(
  scatter_plot,
  "Manual_vs_automated_scatter_plot",
  SINGLE_FIGURE_WIDTH_MM,
  SINGLE_FIGURE_HEIGHT_MM
)

message("Saving Bland–Altman plot, scatter plot and combined panel...")

save_plot_all_formats(
  combined_plot,
  "Bland_Altman_and_scatter_panel",
  PANEL_FIGURE_WIDTH_MM,
  PANEL_FIGURE_HEIGHT_MM
)


# ==============================================================================
# STEP 10: EXPORT PROCESSED DATA AND STATISTICAL RESULTS TO EXCEL
# ==============================================================================
announce_step(10, "Export processed data and statistics to Excel")

# Add an explicit flag for observations outside the limits of agreement.
paired_export <- paired_data |>
  dplyr::mutate(
    outside_95_percent_limits_of_agreement = outside_loa
  )

input_validation <- data.frame(
  item = c(
    "Manual input file",
    "Automated input file",
    "Manual input MD5",
    "Automated input MD5",
    "Manual images detected",
    "Automated images detected",
    "Paired images analysed",
    "Manual workbook sheets",
    "Automated workbook sheets"
  ),
  value = c(
    manual_file,
    automated_file,
    unname(tools::md5sum(manual_file)),
    unname(tools::md5sum(automated_file)),
    nrow(manual_summary),
    nrow(automated_summary),
    n_pairs,
    paste(readxl::excel_sheets(manual_file), collapse = ", "),
    paste(readxl::excel_sheets(automated_file), collapse = ", ")
  ),
  stringsAsFactors = FALSE
)

results_workbook <- openxlsx::createWorkbook()

sheets_to_write <- list(
  Paired_data = paired_export,
  Manual_image_summary = manual_summary,
  Automated_image_summary = automated_summary,
  Bland_Altman_statistics = bland_altman_statistics,
  Pearson_correlation = correlation_statistics,
  Linear_regression = regression_statistics,
  Diagnostics = diagnostic_statistics,
  Input_validation = input_validation
)

header_style <- openxlsx::createStyle(
  textDecoration = "bold",
  fgFill = "#D9EAF7",
  border = "Bottom",
  halign = "center"
)

for (sheet_name in names(sheets_to_write)) {
  openxlsx::addWorksheet(results_workbook, sheet_name)
  openxlsx::writeData(
    results_workbook,
    sheet = sheet_name,
    x = sheets_to_write[[sheet_name]],
    headerStyle = header_style,
    withFilter = TRUE
  )
  openxlsx::freezePane(
    results_workbook,
    sheet = sheet_name,
    firstActiveRow = 2
  )
  openxlsx::setColWidths(
    results_workbook,
    sheet = sheet_name,
    cols = seq_len(ncol(sheets_to_write[[sheet_name]])),
    widths = "auto"
  )
}

excel_output_file <- file.path(
  output_dir,
  "cristae_manual_vs_automated_results.xlsx"
)

message("Saving Excel workbook with processed data and statistical results...")

openxlsx::saveWorkbook(
  results_workbook,
  file = excel_output_file,
  overwrite = TRUE
)


# ==============================================================================
# STEP 11: EXPORT A HUMAN-READABLE ANALYSIS SUMMARY
# ==============================================================================
announce_step(11, "Save a text summary of the analysis and R session information")

analysis_summary_lines <- c(
  "MANUAL VS AUTOMATED CRISTAE COUNTS",
  "Bland-Altman agreement, Pearson correlation and linear regression",
  "",
  paste0("Manual input: ", manual_file),
  paste0("Automated input: ", automated_file),
  paste0("Number of paired images: ", n_pairs),
  "",
  "BLAND-ALTMAN ANALYSIS",
  "Difference was defined as automated - manual.",
  sprintf("Bias: %.4f", bias),
  sprintf("SD of differences: %.4f", sd_difference),
  sprintf("Lower 95%% limit of agreement: %.4f", lower_loa),
  sprintf("Upper 95%% limit of agreement: %.4f", upper_loa),
  sprintf(
    "Images outside the limits of agreement: %d of %d (%.2f%%)",
    sum(outside_loa),
    n_pairs,
    100 * mean(outside_loa)
  ),
  "",
  "PEARSON CORRELATION",
  sprintf("Pearson r: %.6f", pearson_r),
  sprintf(
    "95%% CI for r: %.6f to %.6f",
    pearson_test$conf.int[1],
    pearson_test$conf.int[2]
  ),
  sprintf("Two-sided p-value: %.6g", pearson_test$p.value),
  "",
  "ORDINARY LEAST-SQUARES REGRESSION",
  sprintf(
    "Automated = %.6f + %.6f x Manual",
    regression_coefficients[["(Intercept)"]],
    regression_coefficients[["manual_total"]]
  ),
  sprintf("R-squared: %.6f", regression_summary$r.squared),
  "",
  "INTERPRETATION NOTE",
  paste(
    "Pearson correlation and linear regression quantify association.",
    "They do not demonstrate agreement and should be interpreted together",
    "with the Bland-Altman bias and limits of agreement."
  )
)

summary_output_file <- file.path(output_dir, "analysis_summary.txt")
writeLines(analysis_summary_lines, con = summary_output_file)
message("Text summary saved: ", summary_output_file)

session_info_file <- file.path(output_dir, "R_session_info.txt")
utils::capture.output(utils::sessionInfo(), file = session_info_file)


# ==============================================================================
# STEP 12: PRINT THE KEY RESULTS IN THE R CONSOLE
# ==============================================================================
announce_step(12, "Final summary of the main results")

message("\nAnalysis completed successfully.")
message("Number of paired images: ", n_pairs)
message(sprintf("Bias (automated - manual): %.2f", bias))
message(sprintf("95%% limits of agreement: %.2f to %.2f", lower_loa, upper_loa))
message(sprintf("Pearson r: %.4f", pearson_r))
message(sprintf(
  "Regression: automated = %.4f + %.4f x manual",
  regression_coefficients[["(Intercept)"]],
  regression_coefficients[["manual_total"]]
))
message("\nAll outputs were saved to:\n", normalizePath(output_dir, winslash = "/"))

# Display the combined figure when the script is run interactively in RStudio.
if (interactive()) {
  print(combined_plot)
}
