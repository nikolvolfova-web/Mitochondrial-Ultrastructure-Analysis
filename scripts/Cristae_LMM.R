################################################################################
# CRISTAE LINEAR MIXED-MODEL ANALYSIS
#
# Statistical design
# ------------------
# For each metric, the script fits one linear mixed-effects model:
#
#   y ~ group + (1 | ID_cluster)
#
# All eligible groups are fitted simultaneously. Planned contrasts compare each
# patient group (P1-P10) with Controls. The model therefore uses one common estimate
# of the residual and random-intercept variance for all contrasts of a metric.
#
# The random-effect identifier is made globally unique from group, worksheet and
# the original ID. Missing IDs are filled only inside the worksheet in which
# they occur; they are never carried across worksheet or group boundaries.
#
# Main safeguards
# ---------------
# 1. IDs are completed separately inside each worksheet.
# 2. Globally unique cluster IDs are generated automatically.
# 3. A minimum number of independent IDs is required in every analysed group.
# 4. Descriptive statistics and models use the same validity rules.
# 5. Failed numeric conversions are audited and exported.
# 6. Singular or warning-producing models are retained for review but excluded
#    from adjusted inferential conclusions and significance annotations.
# 7. Effects are derived from the fitted model, not only from row-weighted means.
# 8. Log-scale effects are back-transformed correctly as ratios and confidence
#    intervals; standard errors are never exponentiated directly.
# 9. Plots display ID-level means, so visual points correspond to independent
#    clustering units rather than mitochondrion-level pseudoreplicates.
#
# Outputs
# -------
# - one structured Excel workbook for each input workbook
# - publication-style PNG and PDF plots
# - model diagnostic plots
# - summary effect heatmap and multi-metric contrast overview
# - QC tables, conversion audit, model means and planned contrasts
################################################################################


# ==============================================================================
# 0. USER SETTINGS
# ==============================================================================

# Install packages automatically when they are not available.
install_missing_packages <- TRUE

# Input files. Worksheet names must agree with the group specification below.
input_files <- c(
  manual = file.path("data", "curated", "cristae_manual.xlsx"),
  automated = file.path("data", "curated", "cristae_automated.xlsx")
)

# Root directory for all generated files.
output_root <- file.path(
  "results",
  "derived",
  "cristae_lmm_safe"
)

# Group-to-worksheet mapping.
# Additional worksheets can be assigned to a group by adding their names to the
# corresponding character vector.
groups <- list(
  "C" = list(
    "Controls" = c("Ctrl.")
  ),
  "P" = list(
    "P1" = c("P1"),
    "P2" = c("P2"),
    "P3" = c("P3"),
    "P4" = c("P4"),
    "P5" = c("P5"),
    "P6" = c("P6"),
    "P7" = c("P7"),
    "P8" = c("P8"),
    "P9" = c("P9"),
    "P10" = c("P10")
  )
)

control_group <- "Controls"

# Metrics listed here are modelled after natural-log transformation.
# All retained observations must be strictly positive for these metrics.
logs <- character(0)

# Minimum amount of information required independently in every group.
# The number of IDs, not the number of mitochondrion-level rows, determines
# whether a group has enough independent clustering units for inference.
min_unique_values_per_group <- 4
min_independent_ID_per_group <- 4
min_total_rows_per_group <- 4

# A random-intercept model requires repeated observations within at least some
# IDs. When TRUE, a metric is not fitted unless at least two IDs contain more
# than one valid row in the combined model data.
require_repeated_observations <- TRUE
min_ID_with_repeated_rows <- 2

# Significance and multiple-testing settings.
alpha <- 0.05
plot_significance_column <- "p_adj_BH_within_metric"
show_non_significant_labels <- FALSE

# Publication output settings.
export_dpi <- 300
plot_width_in <- 14
plot_height_in <- 8.5
plot_jitter_seed <- 20260804

# If TRUE, the script stops when a non-empty metric cell cannot be converted to
# a number. If FALSE, the value becomes NA and the failure is exported in the
# numeric_conversion_audit worksheet.
stop_on_numeric_conversion_failure <- FALSE


# ==============================================================================
# 1. PACKAGES
# ==============================================================================

required_packages <- c(
  "openxlsx",
  "lme4",
  "lmerTest",
  "emmeans",
  "ggplot2",
  "dplyr",
  "tibble"
)

#' Install required R packages that are not currently available.
#'
#' @param pkgs Character vector of package names.
#' @return Invisibly returns the names of packages that were missing before the
#'   installation attempt.
#' @details Package installation can be disabled with
#'   `install_missing_packages <- FALSE`. In that case, the function stops and
#'   reports all unavailable packages.
install_if_missing <- function(pkgs) {
  missing <- pkgs[
    !vapply(
      pkgs,
      requireNamespace,
      logical(1),
      quietly = TRUE
    )
  ]

  if (length(missing) > 0) {
    if (!install_missing_packages) {
      stop(
        "Missing R packages: ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }

    install.packages(
      missing,
      dependencies = TRUE
    )
  }

  invisible(missing)
}

install_if_missing(required_packages)

suppressPackageStartupMessages({
  library(openxlsx)
  library(lme4)
  library(lmerTest)
  library(emmeans)
  library(ggplot2)
  library(dplyr)
  library(tibble)
})

#' Validate user-editable analysis settings before any data are read.
#'
#' @return Invisibly returns TRUE when all settings are internally consistent.
#' @details The function prevents ambiguous group assignments, duplicate
#'   worksheet use, invalid thresholds and unsupported significance columns.
validate_analysis_settings <- function() {
  group_names <- unlist(lapply(groups, names), use.names = FALSE)
  worksheet_names <- unlist(
    lapply(
      groups,
      function(section) unlist(section, use.names = FALSE)
    ),
    use.names = FALSE
  )

  if (anyDuplicated(group_names)) {
    stop(
      "Group names must be unique across all sections.",
      call. = FALSE
    )
  }

  if (!control_group %in% group_names) {
    stop(
      "The configured control_group is not present in `groups`.",
      call. = FALSE
    )
  }

  if (anyDuplicated(worksheet_names)) {
    duplicated_sheets <- unique(
      worksheet_names[duplicated(worksheet_names)]
    )

    stop(
      "Each worksheet may be assigned to only one group. Duplicate assignment: ",
      paste(duplicated_sheets, collapse = ", "),
      call. = FALSE
    )
  }

  if (
    any(!is.finite(c(
      min_unique_values_per_group,
      min_independent_ID_per_group,
      min_total_rows_per_group,
      min_ID_with_repeated_rows
    ))) ||
    any(c(
      min_unique_values_per_group,
      min_independent_ID_per_group,
      min_total_rows_per_group,
      min_ID_with_repeated_rows
    ) < 1)
  ) {
    stop(
      "All minimum-data thresholds must be finite positive numbers.",
      call. = FALSE
    )
  }

  if (!is.finite(alpha) || alpha <= 0 || alpha >= 1) {
    stop(
      "alpha must be a finite number strictly between 0 and 1.",
      call. = FALSE
    )
  }

  if (
    length(plot_jitter_seed) != 1 ||
    !is.finite(plot_jitter_seed)
  ) {
    stop(
      "plot_jitter_seed must be one finite numeric value.",
      call. = FALSE
    )
  }

  supported_significance_columns <- c(
    "p_value",
    "p_adj_BH_within_metric",
    "p_adj_BH_all_tests"
  )

  if (!plot_significance_column %in% supported_significance_columns) {
    stop(
      "Unsupported plot_significance_column. Choose one of: ",
      paste(supported_significance_columns, collapse = ", "),
      call. = FALSE
    )
  }

  if (is.null(names(input_files)) || any(!nzchar(names(input_files)))) {
    stop(
      "Every input file must have a non-empty method name.",
      call. = FALSE
    )
  }

  if (anyDuplicated(names(input_files))) {
    stop(
      "Method names in input_files must be unique.",
      call. = FALSE
    )
  }

  if (anyDuplicated(logs)) {
    stop(
      "Metric names in `logs` must not be duplicated.",
      call. = FALSE
    )
  }

  invisible(TRUE)
}

validate_analysis_settings()


# ==============================================================================
# 2. GENERAL HELPER FUNCTIONS
# ==============================================================================

#' Divide two numeric vectors without producing infinite values.
#'
#' @param numerator Numeric vector used as the numerator.
#' @param denominator Numeric vector used as the denominator.
#' @return Numeric vector. Invalid divisions and divisions by zero return NA.
safe_divide <- function(numerator, denominator) {
  ifelse(
    is.finite(numerator) &
      is.finite(denominator) &
      denominator != 0,
    numerator / denominator,
    NA_real_
  )
}

#' Convert arbitrary text into a file-system-safe name.
#'
#' @param x Text to convert.
#' @param max_chars Maximum number of characters retained.
#' @return A character vector containing safe file names.
safe_filename <- function(x, max_chars = 120) {
  x <- enc2utf8(as.character(x))
  x <- gsub("[^A-Za-z0-9_.-]+", "_", x, perl = TRUE)
  x <- gsub("_+", "_", x, perl = TRUE)
  x <- gsub("^_|_$", "", x, perl = TRUE)
  substr(x, 1, max_chars)
}

#' Generate a publication-friendly label for a metric.
#'
#' @param metric Original metric name.
#' @return Character vector with human-readable labels.
publication_label_for_metric <- function(metric) {
  metric <- as.character(metric)

  ifelse(
    grepl("^Label [0-9]+$", metric),
    paste(
      "Cristae class",
      sub("^Label ", "", metric)
    ),
    metric
  )
}

#' Normalize a column name for robust matching.
#'
#' @param x Character vector of column names.
#' @return Lower-case alphanumeric keys without spaces or punctuation.
normalize_column_key <- function(x) {
  x <- tolower(enc2utf8(as.character(x)))
  gsub("[^a-z0-9]+", "", x, perl = TRUE)
}

excluded_column_keys <- c(
  "numberofmito",
  "erconnections",
  "lengthofcontact",
  "averagelengthofcontact"
)

#' Convert a path to a platform-independent display form.
#'
#' @param path File-system path.
#' @return Character path using forward slashes.
format_repo_path <- function(path) {
  gsub("\\\\", "/", path)
}

#' Convert a p-value into a conventional significance label.
#'
#' @param p Numeric p-value or adjusted p-value.
#' @return Character significance label.
p_to_stars <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < 0.001 ~ "***",
    p < 0.01 ~ "**",
    p < 0.05 ~ "*",
    show_non_significant_labels ~ "ns",
    TRUE ~ ""
  )
}

#' Fill missing values downward without crossing a worksheet boundary.
#'
#' @param x Vector containing identifiers.
#' @return Vector in which internal missing values inherit the nearest previous
#'   non-missing value. Leading missing values remain missing.
fill_down_within_vector <- function(x) {
  x <- as.character(x)

  if (length(x) <= 1) {
    return(x)
  }

  for (index in 2:length(x)) {
    if (is.na(x[index]) || !nzchar(trimws(x[index]))) {
      x[index] <- x[index - 1]
    }
  }

  x
}

#' Identify strings that should be treated as missing identifiers or values.
#'
#' @param x Vector to inspect.
#' @return Logical vector indicating missing-like entries.
is_missing_like <- function(x) {
  x_character <- trimws(as.character(x))

  is.na(x) |
    !nzchar(x_character) |
    tolower(x_character) %in% c("na", "n/a", "nan", "null")
}

#' Convert one candidate metric column to numeric values and audit failures.
#'
#' @param x Original column.
#' @param column_name Name of the source column.
#' @return A list with `values` and a one-row `audit` tibble.
#' @details Character numbers using a decimal comma are accepted when no decimal
#'   point is present. Non-breaking spaces and ordinary spaces are removed.
convert_numeric_with_audit <- function(x, column_name) {
  original <- x
  missing_before <- is_missing_like(original)

  if (is.numeric(original)) {
    converted <- as.numeric(original)
  } else {
    normalized <- trimws(as.character(original))
    normalized[missing_before] <- NA_character_
    normalized <- gsub("\u00A0", "", normalized, fixed = TRUE)
    normalized <- gsub("[[:space:]]+", "", normalized, perl = TRUE)

    comma_decimal <- !is.na(normalized) &
      grepl(",", normalized, fixed = TRUE) &
      !grepl(".", normalized, fixed = TRUE)

    normalized[comma_decimal] <- gsub(
      ",",
      ".",
      normalized[comma_decimal],
      fixed = TRUE
    )

    converted <- suppressWarnings(as.numeric(normalized))
  }

  conversion_failure <- !missing_before & is.na(converted)

  audit <- tibble::tibble(
    column = column_name,
    original_class = paste(class(original), collapse = "; "),
    n_rows = length(original),
    n_missing_before = sum(missing_before),
    n_conversion_failures = sum(conversion_failure),
    example_failed_values = if (any(conversion_failure)) {
      paste(
        head(unique(as.character(original[conversion_failure])), 10),
        collapse = "; "
      )
    } else {
      NA_character_
    },
    n_finite_after = sum(is.finite(converted)),
    n_missing_after = sum(is.na(converted))
  )

  list(
    values = converted,
    audit = audit
  )
}

#' Test whether a model group satisfies all minimum-data requirements.
#'
#' @param values Numeric values on the model scale.
#' @param IDs Cluster identifiers aligned with `values`.
#' @return A one-row tibble containing counts, eligibility and an explanatory
#'   status message.
assess_group_eligibility <- function(values, IDs) {
  valid <- is.finite(values) & !is.na(IDs)
  values <- values[valid]
  IDs <- droplevels(factor(IDs[valid]))

  n_rows <- length(values)
  n_ID <- dplyr::n_distinct(IDs, na.rm = TRUE)
  n_unique <- length(unique(values))

  ID_sizes <- if (n_rows > 0) {
    table(IDs)
  } else {
    integer(0)
  }

  n_ID_with_repeated_rows <- sum(ID_sizes > 1)

  eligible <-
    n_rows >= min_total_rows_per_group &&
    n_ID >= min_independent_ID_per_group &&
    n_unique >= min_unique_values_per_group

  reasons <- character(0)

  if (n_rows < min_total_rows_per_group) {
    reasons <- c(
      reasons,
      paste0("fewer than ", min_total_rows_per_group, " valid rows")
    )
  }

  if (n_ID < min_independent_ID_per_group) {
    reasons <- c(
      reasons,
      paste0(
        "fewer than ",
        min_independent_ID_per_group,
        " independent IDs"
      )
    )
  }

  if (n_unique < min_unique_values_per_group) {
    reasons <- c(
      reasons,
      paste0(
        "fewer than ",
        min_unique_values_per_group,
        " unique finite values"
      )
    )
  }

  tibble::tibble(
    n_rows = n_rows,
    n_ID = n_ID,
    n_unique = n_unique,
    n_ID_with_repeated_rows = n_ID_with_repeated_rows,
    eligible = eligible,
    eligibility_detail = if (eligible) {
      NA_character_
    } else {
      paste(reasons, collapse = "; ")
    }
  )
}

#' Fit an LMM while capturing warnings and errors instead of losing them.
#'
#' @param formula Model formula passed to `lmerTest::lmer`.
#' @param data Data frame used for model fitting.
#' @return A list containing the fitted model, warning text and error text.
#' @details REML is used because all planned contrasts are extracted from one
#'   fixed model for the metric rather than from competing fixed-effect models.
capture_lmer <- function(formula, data) {
  warning_messages <- character(0)
  error_message <- NA_character_

  fit <- tryCatch(
    withCallingHandlers(
      lmerTest::lmer(
        formula,
        data = data,
        REML = TRUE,
        na.action = na.omit
      ),
      warning = function(warning_condition) {
        warning_messages <<- c(
          warning_messages,
          conditionMessage(warning_condition)
        )
        invokeRestart("muffleWarning")
      }
    ),
    error = function(error_condition) {
      error_message <<- conditionMessage(error_condition)
      NULL
    }
  )

  list(
    fit = fit,
    warning = if (length(warning_messages) > 0) {
      paste(unique(warning_messages), collapse = " | ")
    } else {
      NA_character_
    },
    error = error_message
  )
}

#' Extract optimizer convergence messages from a fitted lme4 model.
#'
#' @param fit Fitted `merMod` model.
#' @return One character string or NA when no convergence message is present.
extract_convergence_message <- function(fit) {
  messages <- fit@optinfo$conv$lme4$messages

  if (is.null(messages) || length(messages) == 0) {
    return(NA_character_)
  }

  paste(unique(as.character(messages)), collapse = " | ")
}

#' Extract variance components and the intraclass correlation coefficient.
#'
#' @param fit Fitted random-intercept model.
#' @return One-row tibble with random-intercept variance, residual variance and
#'   ICC. ICC is defined as var(ID)/(var(ID) + var(residual)).
extract_variance_components <- function(fit) {
  variance_table <- as.data.frame(lme4::VarCorr(fit))

  ID_variance <- variance_table$vcov[
    variance_table$grp == "ID_cluster"
  ][1]

  residual_variance <- variance_table$vcov[
    variance_table$grp == "Residual"
  ][1]

  tibble::tibble(
    random_intercept_variance = ID_variance,
    residual_variance = residual_variance,
    ICC = safe_divide(
      ID_variance,
      ID_variance + residual_variance
    )
  )
}

#' Return the first existing column from a data frame.
#'
#' @param data Data frame.
#' @param candidates Candidate column names in priority order.
#' @param default Value returned when none of the names exists.
#' @return Selected vector or `default` repeated to the number of rows.
get_first_existing_column <- function(data, candidates, default = NA_real_) {
  existing <- candidates[candidates %in% names(data)]

  if (length(existing) == 0) {
    return(rep(default, nrow(data)))
  }

  data[[existing[1]]]
}

#' Create an empty model-mean table with a stable export schema.
#'
#' @return Zero-row tibble containing all model-mean columns.
empty_model_means_table <- function() {
  tibble::tibble(
    metric = character(0),
    publication_label = character(0),
    group = character(0),
    transformed_for_model = logical(0),
    response_interpretation = character(0),
    emmean_model_scale = numeric(0),
    SE_model_scale = numeric(0),
    degrees_freedom = numeric(0),
    CI_95_low_model_scale = numeric(0),
    CI_95_high_model_scale = numeric(0),
    emmean_response = numeric(0),
    CI_95_low_response = numeric(0),
    CI_95_high_response = numeric(0),
    model_status = character(0),
    inferential_valid = logical(0)
  )
}

#' Create an empty diagnostic-plot index with a stable export schema.
#'
#' @return Zero-row tibble containing all diagnostic file-index columns.
empty_diagnostic_plot_index_table <- function() {
  tibble::tibble(
    metric = character(0),
    residuals_vs_fitted_png = character(0),
    residuals_vs_fitted_pdf = character(0),
    QQ_png = character(0),
    QQ_pdf = character(0)
  )
}

#' Apply the common publication theme used by all metric plots.
#'
#' @param base_size Base font size.
#' @return A ggplot2 theme object.
publication_theme <- function(base_size = 13) {
  theme_bw(base_size = base_size) +
    theme(
      plot.title = element_text(
        face = "bold",
        size = base_size + 2
      ),
      plot.subtitle = element_text(
        size = base_size,
        margin = margin(b = 8)
      ),
      axis.title = element_text(
        face = "bold",
        size = base_size
      ),
      axis.text = element_text(
        size = base_size - 1,
        colour = "black"
      ),
      plot.caption = element_text(
        size = base_size - 2,
        hjust = 0
      ),
      panel.grid.minor = element_blank(),
      panel.grid.major.x = element_blank()
    )
}

#' Add a formatted worksheet to an openxlsx workbook.
#'
#' @param wb Open workbook object.
#' @param sheet_name Desired worksheet name.
#' @param dat Data frame to export.
#' @return Invisibly returns the workbook object after modification.
add_sheet <- function(wb, sheet_name, dat) {
  sheet_name <- substr(sheet_name, 1, 31)

  openxlsx::addWorksheet(wb, sheet_name)
  openxlsx::writeData(
    wb,
    sheet_name,
    dat,
    keepNA = FALSE
  )

  if (ncol(dat) > 0) {
    header_style <- openxlsx::createStyle(
      fgFill = "#1F4E78",
      fontColour = "#FFFFFF",
      textDecoration = "bold",
      halign = "center",
      valign = "center",
      border = "Bottom"
    )

    openxlsx::addStyle(
      wb,
      sheet_name,
      header_style,
      rows = 1,
      cols = seq_len(ncol(dat)),
      gridExpand = TRUE,
      stack = TRUE
    )

    openxlsx::freezePane(
      wb,
      sheet_name,
      firstRow = TRUE
    )

    if (nrow(dat) > 0) {
      openxlsx::addFilter(
        wb,
        sheet_name,
        rows = 1,
        cols = seq_len(ncol(dat))
      )
    }

    old_max_width <- getOption("openxlsx.maxWidth")
    options("openxlsx.maxWidth" = 40)

    openxlsx::setColWidths(
      wb,
      sheet_name,
      cols = seq_len(ncol(dat)),
      widths = "auto"
    )

    options("openxlsx.maxWidth" = old_max_width)

    text_cols <- which(
      names(dat) %in% c(
        "model_warning",
        "model_error",
        "convergence_message",
        "status_detail",
        "eligibility_detail",
        "note",
        "value",
        "example_failed_values"
      )
    )

    if (length(text_cols) > 0 && nrow(dat) > 0) {
      wrap_style <- openxlsx::createStyle(
        wrapText = TRUE,
        valign = "top"
      )

      openxlsx::addStyle(
        wb,
        sheet_name,
        wrap_style,
        rows = 2:(nrow(dat) + 1),
        cols = text_cols,
        gridExpand = TRUE,
        stack = TRUE
      )
    }

    p_cols <- grep(
      "(^p_value$|^p_adj_|^shapiro_p_)",
      names(dat)
    )

    if (length(p_cols) > 0 && nrow(dat) > 0) {
      p_style <- openxlsx::createStyle(numFmt = "0.000E+00")

      openxlsx::addStyle(
        wb,
        sheet_name,
        p_style,
        rows = 2:(nrow(dat) + 1),
        cols = p_cols,
        gridExpand = TRUE,
        stack = TRUE
      )
    }
  }

  invisible(wb)
}


# ==============================================================================
# 3. SAFE WORKBOOK IMPORT
# ==============================================================================

#' Read and validate one worksheet before it is combined with other groups.
#'
#' @param path Excel workbook path.
#' @param sheet_name Worksheet to read.
#' @param group_name Experimental group assigned to the worksheet.
#' @return Data frame with completed IDs, source metadata and a globally unique
#'   `ID_cluster` variable.
#' @details ID completion is intentionally performed here, before worksheets are
#'   combined. Consequently, an empty ID can never inherit an identifier from a
#'   preceding worksheet or experimental group.
read_and_prepare_sheet <- function(path, sheet_name, group_name) {
  sheet_data <- openxlsx::read.xlsx(
    path,
    sheet = sheet_name,
    check.names = TRUE
  )

  if (ncol(sheet_data) == 0) {
    stop(
      "Worksheet contains no columns: ",
      sheet_name,
      call. = FALSE
    )
  }

  names(sheet_data)[1] <- "ID"
  sheet_data$source_sheet <- sheet_name
  sheet_data$source_row <- seq_len(nrow(sheet_data))
  sheet_data$group <- group_name

  ID_text <- trimws(as.character(sheet_data$ID))

  # Remove embedded header rows before filling IDs downward.
  embedded_header <- !is.na(ID_text) &
    tolower(ID_text) == "slice"

  if (any(embedded_header)) {
    sheet_data <- sheet_data[!embedded_header, , drop = FALSE]
    ID_text <- ID_text[!embedded_header]
  }

  ID_text[is_missing_like(ID_text)] <- NA_character_
  sheet_data$ID <- fill_down_within_vector(ID_text)

  if (any(is.na(sheet_data$ID) | !nzchar(trimws(sheet_data$ID)))) {
    problematic_rows <- sheet_data$source_row[
      is.na(sheet_data$ID) | !nzchar(trimws(sheet_data$ID))
    ]

    stop(
      "Worksheet '",
      sheet_name,
      "' contains leading or unresolved missing IDs at original row(s): ",
      paste(problematic_rows, collapse = ", "),
      ". IDs are not allowed to propagate across worksheet boundaries.",
      call. = FALSE
    )
  }

  # The composite label guarantees uniqueness even when worksheets reuse
  # simple labels such as 1, 2, 3, ...
  sheet_data$ID_cluster <- paste(
    group_name,
    sheet_name,
    sheet_data$ID,
    sep = "__"
  )

  # Metric columns are temporarily standardized to character before worksheets
  # are combined. This prevents bind_rows() from failing when Excel stores the
  # same metric as numeric in one sheet and as text in another sheet. Numeric
  # conversion is performed once, centrally, with a complete audit trail.
  sheet_metadata <- c(
    "ID",
    "ID_cluster",
    "source_sheet",
    "source_row",
    "group"
  )

  metric_columns <- setdiff(names(sheet_data), sheet_metadata)

  for (metric_column in metric_columns) {
    sheet_data[[metric_column]] <- as.character(
      sheet_data[[metric_column]]
    )
  }

  sheet_data
}

#' Read, validate and combine all worksheets used by one analysis workbook.
#'
#' @param path Excel workbook path.
#' @return A list containing cleaned data, excluded columns, worksheet names and
#'   a numeric-conversion audit table.
read_cristae_workbook <- function(path) {
  if (!file.exists(path)) {
    stop(
      "Input workbook not found: ",
      path,
      call. = FALSE
    )
  }

  sheet_names <- openxlsx::getSheetNames(path)

  requested_sheet_names <- unlist(
    lapply(
      groups,
      function(section) unlist(section, use.names = FALSE)
    ),
    use.names = FALSE
  )

  missing_sheets <- setdiff(requested_sheet_names, sheet_names)

  if (length(missing_sheets) > 0) {
    stop(
      "Incorrect or missing worksheet name(s): ",
      paste(missing_sheets, collapse = ", "),
      call. = FALSE
    )
  }

  sheet_list <- list()
  sheet_index <- 1

  for (section in names(groups)) {
    for (group_name in names(groups[[section]])) {
      for (sheet_name in groups[[section]][[group_name]]) {
        sheet_list[[sheet_index]] <- read_and_prepare_sheet(
          path = path,
          sheet_name = sheet_name,
          group_name = group_name
        )

        sheet_index <- sheet_index + 1
      }
    }
  }

  X <- dplyr::bind_rows(sheet_list)

  # Preserve human-readable metric names while preventing accidental duplicate
  # column names after replacing periods with spaces.
  names(X) <- make.unique(
    gsub("\\.", " ", names(X)),
    sep = "_duplicate_"
  )

  metadata_columns <- c(
    "ID",
    "ID cluster",
    "source sheet",
    "source row",
    "group"
  )

  # Restore stable metadata names after the human-readable name conversion.
  names(X)[names(X) == "ID cluster"] <- "ID_cluster"
  names(X)[names(X) == "source sheet"] <- "source_sheet"
  names(X)[names(X) == "source row"] <- "source_row"

  metadata_columns <- c(
    "ID",
    "ID_cluster",
    "source_sheet",
    "source_row",
    "group"
  )

  exclusion_mask <- normalize_column_key(names(X)) %in%
    excluded_column_keys

  excluded_found <- names(X)[exclusion_mask]
  X <- X[, !exclusion_mask, drop = FALSE]

  candidate_metrics <- setdiff(names(X), metadata_columns)

  conversion_audit_list <- vector(
    "list",
    length(candidate_metrics)
  )

  for (index in seq_along(candidate_metrics)) {
    metric <- candidate_metrics[index]

    converted <- convert_numeric_with_audit(
      X[[metric]],
      column_name = metric
    )

    X[[metric]] <- converted$values
    conversion_audit_list[[index]] <- converted$audit
  }

  conversion_audit <- dplyr::bind_rows(conversion_audit_list)

  if (
    stop_on_numeric_conversion_failure &&
    any(conversion_audit$n_conversion_failures > 0)
  ) {
    failed_columns <- conversion_audit$column[
      conversion_audit$n_conversion_failures > 0
    ]

    stop(
      "Non-empty values could not be converted to numeric form in: ",
      paste(failed_columns, collapse = ", "),
      ". Review the workbook or set stop_on_numeric_conversion_failure <- FALSE ",
      "to continue with an explicit audit trail.",
      call. = FALSE
    )
  }

  group_levels <- unlist(
    lapply(groups, names),
    use.names = FALSE
  )

  X$group <- factor(
    X$group,
    levels = group_levels
  )

  X$ID <- factor(X$ID)
  X$ID_cluster <- factor(X$ID_cluster)

  # Confirm that every cluster belongs to exactly one worksheet and one group.
  cluster_validation <- X %>%
    group_by(ID_cluster) %>%
    summarise(
      n_groups = n_distinct(group),
      n_sheets = n_distinct(source_sheet),
      .groups = "drop"
    )

  if (any(cluster_validation$n_groups != 1 | cluster_validation$n_sheets != 1)) {
    stop(
      "Internal ID_cluster validation failed: at least one cluster spans more ",
      "than one group or worksheet.",
      call. = FALSE
    )
  }

  list(
    data = X,
    excluded_columns = excluded_found,
    worksheets = sheet_names,
    conversion_audit = conversion_audit
  )
}


# ==============================================================================
# 4. DESCRIPTIVE STATISTICS AND MODEL INPUT PREPARATION
# ==============================================================================

#' Create the model-scale response and the common row-validity mask.
#'
#' @param X Clean analysis data.
#' @param metric Metric column name.
#' @return List containing raw values, model-scale values and a validity mask.
#' @details For log-transformed metrics, zero and negative values are excluded
#'   because the natural logarithm is undefined for them.
prepare_metric_response <- function(X, metric) {
  raw <- X[[metric]]

  if (metric %in% logs) {
    model_value <- suppressWarnings(log(raw))
  } else {
    model_value <- raw
  }

  valid <- is.finite(model_value) &
    is.finite(raw) &
    !is.na(X$ID_cluster)

  list(
    raw = raw,
    model = model_value,
    valid = valid
  )
}

#' Summarize one metric by group at both row and independent-ID levels.
#'
#' @param X Clean analysis data.
#' @param metric Metric column name.
#' @return Tibble with row-level descriptives, ID-level descriptives and group
#'   eligibility information.
#' @details `mean_of_ID_means` weights every ID equally. `row_mean` weights IDs
#'   according to the number of mitochondrion-level rows they contain. Both are
#'   exported so the distinction is explicit.
summarise_metric_by_group <- function(X, metric) {
  prepared <- prepare_metric_response(X, metric)

  working <- tibble::tibble(
    group = X$group,
    ID_cluster = X$ID_cluster,
    raw_value = prepared$raw,
    model_value = prepared$model,
    valid = prepared$valid
  ) %>%
    filter(valid)

  group_output <- vector(
    "list",
    length(levels(X$group))
  )

  for (index in seq_along(levels(X$group))) {
    group_name <- levels(X$group)[index]
    group_data <- working %>% filter(group == group_name)

    eligibility <- assess_group_eligibility(
      values = group_data$model_value,
      IDs = group_data$ID_cluster
    )

    ID_summary <- group_data %>%
      group_by(ID_cluster) %>%
      summarise(
        ID_mean = mean(raw_value),
        ID_median = median(raw_value),
        rows_per_ID = n(),
        .groups = "drop"
      )

    group_output[[index]] <- tibble::tibble(
      metric = metric,
      publication_label = publication_label_for_metric(metric),
      group = group_name,
      transformed_for_model = metric %in% logs,
      n_rows = eligibility$n_rows,
      n_ID = eligibility$n_ID,
      n_unique = eligibility$n_unique,
      n_ID_with_repeated_rows = eligibility$n_ID_with_repeated_rows,
      eligible = eligibility$eligible,
      eligibility_detail = eligibility$eligibility_detail,
      row_mean = if (nrow(group_data) > 0) {
        mean(group_data$raw_value)
      } else {
        NA_real_
      },
      row_median = if (nrow(group_data) > 0) {
        median(group_data$raw_value)
      } else {
        NA_real_
      },
      row_sd = if (nrow(group_data) > 1) {
        sd(group_data$raw_value)
      } else {
        NA_real_
      },
      row_min = if (nrow(group_data) > 0) {
        min(group_data$raw_value)
      } else {
        NA_real_
      },
      row_max = if (nrow(group_data) > 0) {
        max(group_data$raw_value)
      } else {
        NA_real_
      },
      mean_of_ID_means = if (nrow(ID_summary) > 0) {
        mean(ID_summary$ID_mean)
      } else {
        NA_real_
      },
      median_of_ID_means = if (nrow(ID_summary) > 0) {
        median(ID_summary$ID_mean)
      } else {
        NA_real_
      },
      sd_of_ID_means = if (nrow(ID_summary) > 1) {
        sd(ID_summary$ID_mean)
      } else {
        NA_real_
      },
      min_rows_per_ID = if (nrow(ID_summary) > 0) {
        min(ID_summary$rows_per_ID)
      } else {
        NA_integer_
      },
      median_rows_per_ID = if (nrow(ID_summary) > 0) {
        median(ID_summary$rows_per_ID)
      } else {
        NA_real_
      },
      max_rows_per_ID = if (nrow(ID_summary) > 0) {
        max(ID_summary$rows_per_ID)
      } else {
        NA_integer_
      }
    )
  }

  dplyr::bind_rows(group_output)
}

#' Build one skipped contrast row with a standardized output schema.
#'
#' @param metric Metric name.
#' @param patient Patient group name.
#' @param group_summary Group-level summary table for the metric.
#' @param status_detail Explanation of why the contrast was not fitted.
#' @return One-row tibble compatible with fitted contrast output.
make_skipped_contrast <- function(
  metric,
  patient,
  group_summary,
  status_detail
) {
  control_row <- group_summary %>% filter(group == control_group)
  patient_row <- group_summary %>% filter(group == patient)

  tibble::tibble(
    metric = metric,
    publication_label = publication_label_for_metric(metric),
    comparison = paste(control_group, "vs.", patient),
    contrast_direction = "patient minus control",
    control_group = control_group,
    patient_group = patient,
    transformed_for_model = metric %in% logs,
    model_formula = "y ~ group + (1 | ID_cluster)",
    model_status = "skipped",
    inferential_valid = FALSE,
    status_detail = status_detail,
    n_control_rows = control_row$n_rows,
    n_patient_rows = patient_row$n_rows,
    n_control_ID = control_row$n_ID,
    n_patient_ID = patient_row$n_ID,
    n_unique_control = control_row$n_unique,
    n_unique_patient = patient_row$n_unique,
    raw_row_mean_control = control_row$row_mean,
    raw_row_mean_patient = patient_row$row_mean,
    raw_ID_mean_control = control_row$mean_of_ID_means,
    raw_ID_mean_patient = patient_row$mean_of_ID_means,
    control_emmean_model_scale = NA_real_,
    patient_emmean_model_scale = NA_real_,
    control_emmean_response = NA_real_,
    patient_emmean_response = NA_real_,
    effect_type = if (metric %in% logs) "ratio" else "difference",
    estimate_model_scale = NA_real_,
    std_error_model_scale = NA_real_,
    degrees_freedom = NA_real_,
    t_value = NA_real_,
    p_value = NA_real_,
    CI_95_low_model_scale = NA_real_,
    CI_95_high_model_scale = NA_real_,
    effect_response = NA_real_,
    CI_95_low_response = NA_real_,
    CI_95_high_response = NA_real_,
    model_based_difference = NA_real_,
    ratio_patient_to_control = NA_real_,
    percent_change_model_based = NA_real_,
    direction = NA_character_,
    singular_model = NA,
    convergence_message = NA_character_,
    model_warning = NA_character_,
    model_error = NA_character_
  )
}


# ==============================================================================
# 5. MODEL FITTING AND PLANNED CONTRASTS
# ==============================================================================

#' Analyse one metric with one LMM and planned patient-versus-control contrasts.
#'
#' @param X Clean analysis data.
#' @param metric Metric column name.
#' @return A list containing contrast results, group summaries, model means,
#'   model diagnostics and the fitted model object.
#' @details Groups failing the pre-specified ID, row or variability thresholds
#'   are excluded from the model and returned as explicit skipped comparisons.
#'   P-values are raw contrast p-values; BH adjustment is applied after all
#'   metrics have been analysed.
run_metric_model <- function(X, metric) {
  prepared <- prepare_metric_response(X, metric)
  group_summary <- summarise_metric_by_group(X, metric)

  patient_groups <- names(groups$P)
  eligible_groups <- as.character(
    group_summary$group[group_summary$eligible]
  )

  skipped_results <- list()
  skipped_index <- 1

  for (patient in patient_groups) {
    control_eligible <- control_group %in% eligible_groups
    patient_eligible <- patient %in% eligible_groups

    if (!(control_eligible && patient_eligible)) {
      control_detail <- group_summary$eligibility_detail[
        group_summary$group == control_group
      ]
      patient_detail <- group_summary$eligibility_detail[
        group_summary$group == patient
      ]

      status_parts <- character(0)

      if (!control_eligible) {
        status_parts <- c(
          status_parts,
          paste0("Control group ineligible: ", control_detail)
        )
      }

      if (!patient_eligible) {
        status_parts <- c(
          status_parts,
          paste0(patient, " ineligible: ", patient_detail)
        )
      }

      skipped_results[[skipped_index]] <- make_skipped_contrast(
        metric = metric,
        patient = patient,
        group_summary = group_summary,
        status_detail = paste(status_parts, collapse = " | ")
      )

      skipped_index <- skipped_index + 1
    }
  }

  eligible_model_groups <- c(
    control_group,
    patient_groups[patient_groups %in% eligible_groups]
  )

  eligible_model_groups <- unique(
    eligible_model_groups[eligible_model_groups %in% eligible_groups]
  )

  if (
    !control_group %in% eligible_model_groups ||
    length(eligible_model_groups) < 2
  ) {
    diagnostics <- tibble::tibble(
      metric = metric,
      model_status = "skipped",
      n_observations = 0,
      n_ID = 0,
      n_groups = length(eligible_model_groups),
      n_ID_with_repeated_rows = 0,
      singular_model = NA,
      convergence_message = NA_character_,
      model_warning = NA_character_,
      model_error = NA_character_,
      random_intercept_variance = NA_real_,
      residual_variance = NA_real_,
      ICC = NA_real_,
      residual_mean = NA_real_,
      residual_sd = NA_real_,
      max_absolute_standardized_residual = NA_real_,
      shapiro_W_residuals = NA_real_,
      shapiro_p_residuals = NA_real_,
      diagnostic_note = "Model not fitted because fewer than two eligible groups remained or the control group was ineligible."
    )

    return(
      list(
        contrasts = dplyr::bind_rows(skipped_results),
        group_summary = group_summary,
        model_means = empty_model_means_table(),
        diagnostics = diagnostics,
        fit = NULL
      )
    )
  }

  model_data <- tibble::tibble(
    y = prepared$model,
    raw_value = prepared$raw,
    group = X$group,
    ID_cluster = X$ID_cluster,
    valid = prepared$valid
  ) %>%
    filter(
      valid,
      group %in% eligible_model_groups
    ) %>%
    mutate(
      group = factor(
        as.character(group),
        levels = eligible_model_groups
      ),
      ID_cluster = droplevels(factor(ID_cluster))
    )

  ID_sizes <- table(model_data$ID_cluster)
  n_ID_with_repeated_rows <- sum(ID_sizes > 1)

  if (
    require_repeated_observations &&
    n_ID_with_repeated_rows < min_ID_with_repeated_rows
  ) {
    repeated_detail <- paste0(
      "Random-intercept model not fitted: only ",
      n_ID_with_repeated_rows,
      " ID(s) contained repeated valid rows; at least ",
      min_ID_with_repeated_rows,
      " are required."
    )

    additional_skipped <- lapply(
      patient_groups[
        patient_groups %in% eligible_model_groups
      ],
      function(patient) {
        make_skipped_contrast(
          metric = metric,
          patient = patient,
          group_summary = group_summary,
          status_detail = repeated_detail
        )
      }
    )

    diagnostics <- tibble::tibble(
      metric = metric,
      model_status = "skipped",
      n_observations = nrow(model_data),
      n_ID = n_distinct(model_data$ID_cluster),
      n_groups = n_distinct(model_data$group),
      n_ID_with_repeated_rows = n_ID_with_repeated_rows,
      singular_model = NA,
      convergence_message = NA_character_,
      model_warning = NA_character_,
      model_error = NA_character_,
      random_intercept_variance = NA_real_,
      residual_variance = NA_real_,
      ICC = NA_real_,
      residual_mean = NA_real_,
      residual_sd = NA_real_,
      max_absolute_standardized_residual = NA_real_,
      shapiro_W_residuals = NA_real_,
      shapiro_p_residuals = NA_real_,
      diagnostic_note = repeated_detail
    )

    return(
      list(
        contrasts = dplyr::bind_rows(
          skipped_results,
          additional_skipped
        ),
        group_summary = group_summary,
        model_means = empty_model_means_table(),
        diagnostics = diagnostics,
        fit = NULL
      )
    )
  }

  model_capture <- capture_lmer(
    y ~ group + (1 | ID_cluster),
    data = model_data
  )

  if (is.null(model_capture$fit)) {
    failed_detail <- "The mixed model could not be fitted."

    failed_results <- lapply(
      patient_groups[patient_groups %in% eligible_model_groups],
      function(patient) {
        result <- make_skipped_contrast(
          metric = metric,
          patient = patient,
          group_summary = group_summary,
          status_detail = failed_detail
        )

        result$model_status <- "failed"
        result$model_warning <- model_capture$warning
        result$model_error <- model_capture$error
        result
      }
    )

    diagnostics <- tibble::tibble(
      metric = metric,
      model_status = "failed",
      n_observations = nrow(model_data),
      n_ID = n_distinct(model_data$ID_cluster),
      n_groups = n_distinct(model_data$group),
      n_ID_with_repeated_rows = n_ID_with_repeated_rows,
      singular_model = NA,
      convergence_message = NA_character_,
      model_warning = model_capture$warning,
      model_error = model_capture$error,
      random_intercept_variance = NA_real_,
      residual_variance = NA_real_,
      ICC = NA_real_,
      residual_mean = NA_real_,
      residual_sd = NA_real_,
      max_absolute_standardized_residual = NA_real_,
      shapiro_W_residuals = NA_real_,
      shapiro_p_residuals = NA_real_,
      diagnostic_note = failed_detail
    )

    return(
      list(
        contrasts = dplyr::bind_rows(
          skipped_results,
          failed_results
        ),
        group_summary = group_summary,
        model_means = empty_model_means_table(),
        diagnostics = diagnostics,
        fit = NULL
      )
    )
  }

  fit <- model_capture$fit
  singular_model <- lme4::isSingular(fit, tol = 1e-4)
  convergence_message <- extract_convergence_message(fit)

  inferential_valid <-
    !singular_model &&
    is.na(convergence_message) &&
    is.na(model_capture$warning) &&
    is.na(model_capture$error)

  model_status <- if (inferential_valid) {
    "fitted"
  } else {
    "fitted_review_required"
  }

  emm <- emmeans::emmeans(
    fit,
    specs = ~ group,
    lmer.df = "satterthwaite"
  )

  emm_table <- as.data.frame(
    summary(
      emm,
      infer = c(TRUE, TRUE),
      adjust = "none"
    )
  )

  emm_table$group <- as.character(emm_table$group)
  emm_table$emmean_model_scale <- emm_table$emmean
  emm_table$SE_model_scale <- emm_table$SE
  emm_table$CI_95_low_model_scale <- get_first_existing_column(
    emm_table,
    c("lower.CL", "asymp.LCL")
  )
  emm_table$CI_95_high_model_scale <- get_first_existing_column(
    emm_table,
    c("upper.CL", "asymp.UCL")
  )

  if (metric %in% logs) {
    emm_table$emmean_response <- exp(emm_table$emmean_model_scale)
    emm_table$CI_95_low_response <- exp(
      emm_table$CI_95_low_model_scale
    )
    emm_table$CI_95_high_response <- exp(
      emm_table$CI_95_high_model_scale
    )
    response_interpretation <- "geometric mean"
  } else {
    emm_table$emmean_response <- emm_table$emmean_model_scale
    emm_table$CI_95_low_response <- emm_table$CI_95_low_model_scale
    emm_table$CI_95_high_response <- emm_table$CI_95_high_model_scale
    response_interpretation <- "model-estimated mean"
  }

  model_means <- emm_table %>%
    transmute(
      metric = metric,
      publication_label = publication_label_for_metric(metric),
      group = group,
      transformed_for_model = metric %in% logs,
      response_interpretation = response_interpretation,
      emmean_model_scale = emmean_model_scale,
      SE_model_scale = SE_model_scale,
      degrees_freedom = df,
      CI_95_low_model_scale = CI_95_low_model_scale,
      CI_95_high_model_scale = CI_95_high_model_scale,
      emmean_response = emmean_response,
      CI_95_low_response = CI_95_low_response,
      CI_95_high_response = CI_95_high_response,
      model_status = model_status,
      inferential_valid = inferential_valid
    )

  contrast_object <- emmeans::contrast(
    emm,
    method = "trt.vs.ctrl",
    ref = 1,
    adjust = "none"
  )

  contrast_table <- as.data.frame(
    summary(
      contrast_object,
      infer = c(TRUE, TRUE),
      adjust = "none"
    )
  )

  fitted_patients <- eligible_model_groups[
    eligible_model_groups != control_group
  ]

  if (nrow(contrast_table) != length(fitted_patients)) {
    stop(
      "Unexpected number of planned contrasts for metric: ",
      metric,
      call. = FALSE
    )
  }

  contrast_table$patient_group <- fitted_patients

  control_mean_table <- model_means %>%
    filter(group == control_group)

  fitted_results <- vector("list", nrow(contrast_table))

  for (index in seq_len(nrow(contrast_table))) {
    patient <- contrast_table$patient_group[index]
    patient_mean_table <- model_means %>% filter(group == patient)
    control_summary <- group_summary %>% filter(group == control_group)
    patient_summary <- group_summary %>% filter(group == patient)

    estimate <- contrast_table$estimate[index]
    SE <- contrast_table$SE[index]
    df_value <- contrast_table$df[index]
    t_value <- get_first_existing_column(
      contrast_table[index, , drop = FALSE],
      c("t.ratio", "z.ratio")
    )[1]
    p_value <- contrast_table$p.value[index]
    lower_model <- get_first_existing_column(
      contrast_table[index, , drop = FALSE],
      c("lower.CL", "asymp.LCL")
    )[1]
    upper_model <- get_first_existing_column(
      contrast_table[index, , drop = FALSE],
      c("upper.CL", "asymp.UCL")
    )[1]

    control_response <- control_mean_table$emmean_response
    patient_response <- patient_mean_table$emmean_response

    if (metric %in% logs) {
      effect_type <- "ratio"
      effect_response <- exp(estimate)
      lower_response <- exp(lower_model)
      upper_response <- exp(upper_model)
      model_based_difference <- patient_response - control_response
      ratio_response <- effect_response
      percent_change <- 100 * (effect_response - 1)
    } else {
      effect_type <- "difference"
      effect_response <- estimate
      lower_response <- lower_model
      upper_response <- upper_model
      model_based_difference <- estimate
      ratio_response <- safe_divide(
        patient_response,
        control_response
      )
      percent_change <- 100 * safe_divide(
        estimate,
        control_response
      )
    }

    fitted_results[[index]] <- tibble::tibble(
      metric = metric,
      publication_label = publication_label_for_metric(metric),
      comparison = paste(control_group, "vs.", patient),
      contrast_direction = "patient minus control",
      control_group = control_group,
      patient_group = patient,
      transformed_for_model = metric %in% logs,
      model_formula = "y ~ group + (1 | ID_cluster)",
      model_status = model_status,
      inferential_valid = inferential_valid,
      status_detail = if (inferential_valid) {
        NA_character_
      } else {
        paste(
          na.omit(
            c(
              if (singular_model) "singular random-effect fit" else NA_character_,
              convergence_message,
              model_capture$warning
            )
          ),
          collapse = " | "
        )
      },
      n_control_rows = control_summary$n_rows,
      n_patient_rows = patient_summary$n_rows,
      n_control_ID = control_summary$n_ID,
      n_patient_ID = patient_summary$n_ID,
      n_unique_control = control_summary$n_unique,
      n_unique_patient = patient_summary$n_unique,
      raw_row_mean_control = control_summary$row_mean,
      raw_row_mean_patient = patient_summary$row_mean,
      raw_ID_mean_control = control_summary$mean_of_ID_means,
      raw_ID_mean_patient = patient_summary$mean_of_ID_means,
      control_emmean_model_scale = control_mean_table$emmean_model_scale,
      patient_emmean_model_scale = patient_mean_table$emmean_model_scale,
      control_emmean_response = control_response,
      patient_emmean_response = patient_response,
      effect_type = effect_type,
      estimate_model_scale = estimate,
      std_error_model_scale = SE,
      degrees_freedom = df_value,
      t_value = t_value,
      p_value = p_value,
      CI_95_low_model_scale = lower_model,
      CI_95_high_model_scale = upper_model,
      effect_response = effect_response,
      CI_95_low_response = lower_response,
      CI_95_high_response = upper_response,
      model_based_difference = model_based_difference,
      ratio_patient_to_control = ratio_response,
      percent_change_model_based = percent_change,
      direction = dplyr::case_when(
        estimate > 0 ~ "higher_in_patient",
        estimate < 0 ~ "lower_in_patient",
        TRUE ~ "no_model_difference"
      ),
      singular_model = singular_model,
      convergence_message = convergence_message,
      model_warning = model_capture$warning,
      model_error = model_capture$error
    )
  }

  residual_values <- residuals(fit)
  standardized_residuals <- if (
    length(residual_values) > 1 &&
    is.finite(sd(residual_values)) &&
    sd(residual_values) > 0
  ) {
    as.numeric(scale(residual_values))
  } else {
    rep(NA_real_, length(residual_values))
  }

  shapiro_result <- if (
    length(residual_values) >= 3 &&
    length(residual_values) <= 5000 &&
    length(unique(residual_values)) >= 3
  ) {
    tryCatch(
      stats::shapiro.test(residual_values),
      error = function(e) NULL
    )
  } else {
    NULL
  }

  variance_components <- extract_variance_components(fit)

  diagnostics <- tibble::tibble(
    metric = metric,
    model_status = model_status,
    n_observations = stats::nobs(fit),
    n_ID = n_distinct(model_data$ID_cluster),
    n_groups = n_distinct(model_data$group),
    n_ID_with_repeated_rows = n_ID_with_repeated_rows,
    singular_model = singular_model,
    convergence_message = convergence_message,
    model_warning = model_capture$warning,
    model_error = model_capture$error,
    random_intercept_variance = variance_components$random_intercept_variance,
    residual_variance = variance_components$residual_variance,
    ICC = variance_components$ICC,
    residual_mean = mean(residual_values),
    residual_sd = sd(residual_values),
    max_absolute_standardized_residual = if (
      any(is.finite(standardized_residuals))
    ) {
      max(abs(standardized_residuals), na.rm = TRUE)
    } else {
      NA_real_
    },
    shapiro_W_residuals = if (!is.null(shapiro_result)) {
      unname(shapiro_result$statistic)
    } else {
      NA_real_
    },
    shapiro_p_residuals = if (!is.null(shapiro_result)) {
      shapiro_result$p.value
    } else {
      NA_real_
    },
    diagnostic_note = paste0(
      "Residual diagnostics are screening tools, not automatic proof of model ",
      "validity. Inspect the exported residual-versus-fitted and Q-Q plots."
    )
  )

  list(
    contrasts = dplyr::bind_rows(
      skipped_results,
      fitted_results
    ),
    group_summary = group_summary,
    model_means = model_means,
    diagnostics = diagnostics,
    fit = fit
  )
}


# ==============================================================================
# 6. MODEL DIAGNOSTIC PLOTS
# ==============================================================================

#' Save residual-versus-fitted and normal Q-Q plots for one fitted model.
#'
#' @param fit Fitted `merMod` object or NULL.
#' @param metric Metric name.
#' @param diagnostic_dir Output directory.
#' @return One-row tibble indexing generated files, or an empty tibble when no
#'   fitted model is available.
save_model_diagnostic_plots <- function(fit, metric, diagnostic_dir) {
  if (is.null(fit)) {
    return(empty_diagnostic_plot_index_table())
  }

  file_base <- safe_filename(metric)

  residual_png <- file.path(
    diagnostic_dir,
    paste0(file_base, "_residuals_vs_fitted.png")
  )

  residual_pdf <- file.path(
    diagnostic_dir,
    paste0(file_base, "_residuals_vs_fitted.pdf")
  )

  QQ_png <- file.path(
    diagnostic_dir,
    paste0(file_base, "_QQ.png")
  )

  QQ_pdf <- file.path(
    diagnostic_dir,
    paste0(file_base, "_QQ.pdf")
  )

  fitted_values <- fitted(fit)
  residual_values <- residuals(fit)

  grDevices::png(
    residual_png,
    width = 1800,
    height = 1300,
    res = 180
  )
  plot(
    fitted_values,
    residual_values,
    xlab = "Fitted values",
    ylab = "Conditional residuals",
    main = paste0(
      publication_label_for_metric(metric),
      ": residuals versus fitted"
    ),
    pch = 16,
    cex = 0.7
  )
  abline(h = 0, lty = 2)
  grDevices::dev.off()

  grDevices::pdf(
    residual_pdf,
    width = 9,
    height = 6.5
  )
  plot(
    fitted_values,
    residual_values,
    xlab = "Fitted values",
    ylab = "Conditional residuals",
    main = paste0(
      publication_label_for_metric(metric),
      ": residuals versus fitted"
    ),
    pch = 16,
    cex = 0.7
  )
  abline(h = 0, lty = 2)
  grDevices::dev.off()

  grDevices::png(
    QQ_png,
    width = 1800,
    height = 1300,
    res = 180
  )
  stats::qqnorm(
    residual_values,
    main = paste0(
      publication_label_for_metric(metric),
      ": residual Q-Q plot"
    ),
    pch = 16,
    cex = 0.7
  )
  stats::qqline(residual_values, lty = 2)
  grDevices::dev.off()

  grDevices::pdf(
    QQ_pdf,
    width = 9,
    height = 6.5
  )
  stats::qqnorm(
    residual_values,
    main = paste0(
      publication_label_for_metric(metric),
      ": residual Q-Q plot"
    ),
    pch = 16,
    cex = 0.7
  )
  stats::qqline(residual_values, lty = 2)
  grDevices::dev.off()

  tibble::tibble(
    metric = metric,
    residuals_vs_fitted_png = format_repo_path(residual_png),
    residuals_vs_fitted_pdf = format_repo_path(residual_pdf),
    QQ_png = format_repo_path(QQ_png),
    QQ_pdf = format_repo_path(QQ_pdf)
  )
}


# ==============================================================================
# 7. PUBLICATION PLOTS
# ==============================================================================

#' Create a publication plot based on independent ID-level means.
#'
#' @param X Clean analysis data.
#' @param metric Metric name.
#' @param metric_statistics Contrast results for the metric.
#' @param metric_model_means Model-estimated means for the metric.
#' @param plot_dir Output directory.
#' @return One-row tibble indexing generated PNG and PDF files.
#' @details Each jittered point is the mean of all valid rows belonging to one
#'   `ID_cluster`. Model-estimated means and 95% confidence intervals are added
#'   separately. Significance brackets are based only on inferentially valid,
#'   BH-adjusted planned contrasts.
make_metric_plot <- function(
  X,
  metric,
  metric_statistics,
  metric_model_means,
  plot_dir
) {
  prepared <- prepare_metric_response(X, metric)

  plot_data <- tibble::tibble(
    group = X$group,
    ID_cluster = X$ID_cluster,
    raw_value = prepared$raw,
    model_value = prepared$model,
    valid = prepared$valid
  ) %>%
    filter(valid) %>%
    group_by(group, ID_cluster) %>%
    summarise(
      value = if (metric %in% logs) {
        exp(mean(model_value))
      } else {
        mean(raw_value)
      },
      n_rows_in_ID = n(),
      .groups = "drop"
    )

  if (nrow(plot_data) == 0) {
    return(
      tibble::tibble(
        metric = metric,
        publication_label = publication_label_for_metric(metric),
        plot_status = "skipped_no_valid_ID_level_data",
        png = NA_character_,
        pdf = NA_character_,
        n_significant_BH_within_metric = 0
      )
    )
  }

  annotations <- metric_statistics %>%
    filter(
      inferential_valid,
      !is.na(.data[[plot_significance_column]])
    ) %>%
    mutate(
      significance_value = .data[[plot_significance_column]],
      label = p_to_stars(significance_value),
      x_control = match(
        control_group,
        levels(X$group)
      ),
      x_patient = match(
        patient_group,
        levels(X$group)
      )
    )

  if (!show_non_significant_labels) {
    annotations <- annotations %>%
      filter(significance_value < alpha)
  }

  annotations <- annotations %>%
    filter(
      label != "",
      !is.na(x_control),
      !is.na(x_patient)
    ) %>%
    arrange(x_patient)

  model_mean_plot <- metric_model_means %>%
    filter(
      group %in% levels(X$group),
      is.finite(emmean_response),
      is.finite(CI_95_low_response),
      is.finite(CI_95_high_response)
    ) %>%
    mutate(
      group = factor(group, levels = levels(X$group))
    )

  all_y <- c(
    plot_data$value,
    model_mean_plot$CI_95_low_response,
    model_mean_plot$CI_95_high_response
  )

  all_y <- all_y[is.finite(all_y)]
  y_min <- min(all_y)
  y_max <- max(all_y)
  y_range <- y_max - y_min

  if (!is.finite(y_range) || y_range <= 0) {
    y_range <- max(abs(y_max), 1)
  }

  if (nrow(annotations) > 0) {
    if (metric %in% logs) {
      positive_max <- max(all_y[all_y > 0], na.rm = TRUE)

      annotations <- annotations %>%
        mutate(
          bracket_index = row_number(),
          y = positive_max * 1.14^bracket_index,
          tick = y * 0.018,
          y_label = y * 1.025
        )
    } else {
      annotations <- annotations %>%
        mutate(
          bracket_index = row_number(),
          y = y_max + bracket_index * 0.10 * y_range,
          tick = 0.018 * y_range,
          y_label = y + 0.025 * y_range
        )
    }
  }

  significance_description <- switch(
    plot_significance_column,
    p_value = "raw p values",
    p_adj_BH_within_metric = "BH-adjusted q values within the metric",
    p_adj_BH_all_tests = "BH-adjusted q values across all workbook tests"
  )

  p <- ggplot(
    plot_data,
    aes(
      x = group,
      y = value
    )
  ) +
    geom_violin(
      trim = FALSE,
      fill = "grey90",
      colour = "grey45",
      alpha = 0.8,
      linewidth = 0.35,
      na.rm = TRUE
    ) +
    geom_boxplot(
      width = 0.18,
      outlier.shape = NA,
      fill = "white",
      colour = "black",
      linewidth = 0.4,
      na.rm = TRUE
    ) +
    geom_point(
      position = position_jitter(
        width = 0.10,
        height = 0,
        seed = plot_jitter_seed
      ),
      alpha = 0.70,
      size = 1.6,
      colour = "black",
      na.rm = TRUE
    ) +
    labs(
      title = publication_label_for_metric(metric),
      subtitle = paste0(
        "One LMM per metric; planned Controls-versus-patient contrasts; ",
        "random intercept for independent ID"
      ),
      x = NULL,
      y = publication_label_for_metric(metric),
      caption = paste0(
        "Each jittered point is one ID-level mean (geometric mean for a ",
        "log-transformed metric). Diamonds and error bars are ",
        "model-estimated means with 95% confidence intervals. Stars indicate ",
        significance_description,
        " (* < 0.05, ** < 0.01, *** < 0.001). Singular or warning-producing ",
        "models are not annotated."
      )
    ) +
    publication_theme(base_size = 13) +
    theme(
      legend.position = "none",
      axis.text.x = element_text(
        angle = 45,
        hjust = 1
      ),
      plot.margin = margin(
        t = 12,
        r = 14,
        b = 10,
        l = 10
      )
    )

  if (nrow(model_mean_plot) > 0) {
    p <- p +
      geom_errorbar(
        data = model_mean_plot,
        aes(
          x = group,
          ymin = CI_95_low_response,
          ymax = CI_95_high_response
        ),
        inherit.aes = FALSE,
        width = 0.08,
        linewidth = 0.65
      ) +
      geom_point(
        data = model_mean_plot,
        aes(
          x = group,
          y = emmean_response
        ),
        inherit.aes = FALSE,
        shape = 23,
        size = 3.2,
        fill = "white",
        colour = "black"
      )
  }

  if (nrow(annotations) > 0) {
    p <- p +
      geom_segment(
        data = annotations,
        aes(
          x = x_control,
          xend = x_patient,
          y = y,
          yend = y
        ),
        inherit.aes = FALSE,
        linewidth = 0.45
      ) +
      geom_segment(
        data = annotations,
        aes(
          x = x_control,
          xend = x_control,
          y = y,
          yend = y - tick
        ),
        inherit.aes = FALSE,
        linewidth = 0.45
      ) +
      geom_segment(
        data = annotations,
        aes(
          x = x_patient,
          xend = x_patient,
          y = y,
          yend = y - tick
        ),
        inherit.aes = FALSE,
        linewidth = 0.45
      ) +
      geom_text(
        data = annotations,
        aes(
          x = (x_control + x_patient) / 2,
          y = y_label,
          label = label
        ),
        inherit.aes = FALSE,
        fontface = "bold",
        size = 5,
        vjust = 0
      ) +
      geom_blank(
        data = annotations,
        aes(
          x = x_patient,
          y = y_label
        ),
        inherit.aes = FALSE
      ) +
      coord_cartesian(clip = "off")
  }

  if (metric %in% logs) {
    p <- p +
      scale_y_log10(
        expand = expansion(mult = c(0.05, 0.20))
      )
  } else {
    p <- p +
      scale_y_continuous(
        expand = expansion(mult = c(0.05, 0.18))
      )
  }

  filename_base <- safe_filename(metric)
  png_file <- file.path(plot_dir, paste0(filename_base, ".png"))
  pdf_file <- file.path(plot_dir, paste0(filename_base, ".pdf"))

  ggsave(
    filename = png_file,
    plot = p,
    width = plot_width_in,
    height = plot_height_in,
    units = "in",
    dpi = export_dpi,
    bg = "white",
    limitsize = FALSE
  )

  ggsave(
    filename = pdf_file,
    plot = p,
    width = plot_width_in,
    height = plot_height_in,
    units = "in",
    device = grDevices::pdf,
    bg = "white",
    limitsize = FALSE
  )

  tibble::tibble(
    metric = metric,
    publication_label = publication_label_for_metric(metric),
    plot_status = "created",
    png = format_repo_path(png_file),
    pdf = format_repo_path(pdf_file),
    n_significant_BH_within_metric = sum(
      metric_statistics$inferential_valid &
        !is.na(metric_statistics[[plot_significance_column]]) &
        metric_statistics[[plot_significance_column]] < alpha
    )
  )
}


# ==============================================================================
# 8. SUMMARY COMPARISON PLOTS
# ==============================================================================

#' Prepare a common model-based effect table for summary figures.
#'
#' @param statistics_all Complete planned-contrast table after p-value
#'   adjustment.
#' @param metric_order Metric names in the desired plotting order.
#' @return A tibble containing model-based percentage changes, corresponding
#'   95% confidence limits and significance labels.
#' @details For untransformed metrics, the percentage change is the estimated
#'   patient-minus-Control difference divided by the model-estimated Control
#'   mean. For log-transformed metrics, it is calculated from the
#'   back-transformed patient-to-Control ratio. These definitions are identical
#'   to the percentage-effect calculation exported in `statistics_all`.
prepare_summary_effect_data <- function(statistics_all, metric_order) {
  statistics_all %>%
    mutate(
      patient_group = factor(
        as.character(patient_group),
        levels = names(groups$P)
      ),
      publication_label = factor(
        publication_label,
        levels = publication_label_for_metric(metric_order)
      ),
      significance_value = .data[[plot_significance_column]],
      significance_label = p_to_stars(significance_value),
      CI_95_low_percent = dplyr::case_when(
        effect_type == "ratio" ~
          100 * (CI_95_low_response - 1),
        effect_type == "difference" ~
          100 * safe_divide(
            CI_95_low_response,
            control_emmean_response
          ),
        TRUE ~ NA_real_
      ),
      CI_95_high_percent = dplyr::case_when(
        effect_type == "ratio" ~
          100 * (CI_95_high_response - 1),
        effect_type == "difference" ~
          100 * safe_divide(
            CI_95_high_response,
            control_emmean_response
          ),
        TRUE ~ NA_real_
      )
    ) %>%
    arrange(publication_label, patient_group)
}

#' Save cross-metric summary figures for one analysis method.
#'
#' @param statistics_all Complete contrast table after p-value adjustment.
#' @param metric_order Metric names in the desired plotting order.
#' @param method_name Analysis label, for example `manual` or `automated`.
#' @param summary_plot_dir Output directory for summary figures.
#' @return A list containing a file index and the effect table used by the
#'   figures.
#' @details Two complementary outputs are created. The heatmap provides a
#'   compact overview of model-based percentage changes for P1-P10 relative to
#'   Controls across all metrics. The contrast overview displays the same
#'   effects together with 95% confidence intervals. Only inferentially valid
#'   models are coloured or plotted; unavailable or review-required results are
#'   shown as grey cells in the heatmap and omitted from the contrast panel.
#'
#' The heatmap uses a symmetric colour scale centred at zero. Consequently,
#' equal-magnitude increases and decreases receive equal visual emphasis.
#' Significance stars are based on the p-value column selected in
#' `plot_significance_column`, which is BH adjustment within each metric by
#' default.
save_summary_comparison_plots <- function(
  statistics_all,
  metric_order,
  method_name,
  summary_plot_dir
) {
  dir.create(
    summary_plot_dir,
    recursive = TRUE,
    showWarnings = FALSE
  )

  method_label <- paste0(
    stringr::str_to_title(method_name),
    " quantification"
  )

  effect_data <- prepare_summary_effect_data(
    statistics_all = statistics_all,
    metric_order = metric_order
  )

  patient_levels <- names(groups$P)
  metric_labels <- publication_label_for_metric(metric_order)

  heatmap_data <- tidyr::expand_grid(
    metric = metric_order,
    patient_group = patient_levels
  ) %>%
    left_join(
      effect_data %>%
        mutate(
          metric = as.character(metric),
          patient_group = as.character(patient_group)
        ) %>%
        select(
          metric,
          patient_group,
          inferential_valid,
          percent_change_model_based,
          CI_95_low_percent,
          CI_95_high_percent,
          significance_value,
          significance_label,
          model_status
        ),
      by = c("metric", "patient_group")
    ) %>%
    mutate(
      publication_label = publication_label_for_metric(metric),
      publication_label = factor(
        publication_label,
        levels = rev(metric_labels)
      ),
      patient_group = factor(
        patient_group,
        levels = patient_levels
      ),
      plotted_percent = ifelse(
        inferential_valid %in% TRUE,
        percent_change_model_based,
        NA_real_
      ),
      tile_label = dplyr::case_when(
        inferential_valid %in% TRUE &
          is.finite(plotted_percent) &
          significance_label != "" ~
          paste0(
            sprintf("%.0f%%", plotted_percent),
            "\n",
            significance_label
          ),
        inferential_valid %in% TRUE &
          is.finite(plotted_percent) ~
          sprintf("%.0f%%", plotted_percent),
        TRUE ~ ""
      )
    )

  finite_heat_values <- heatmap_data$plotted_percent[
    is.finite(heatmap_data$plotted_percent)
  ]

  symmetric_limit <- if (length(finite_heat_values) > 0) {
    max(abs(finite_heat_values))
  } else {
    1
  }

  if (!is.finite(symmetric_limit) || symmetric_limit <= 0) {
    symmetric_limit <- 1
  }

  heatmap_plot <- ggplot(
    heatmap_data,
    aes(
      x = patient_group,
      y = publication_label,
      fill = plotted_percent
    )
  ) +
    geom_tile(
      colour = "white",
      linewidth = 0.45
    ) +
    geom_text(
      aes(label = tile_label),
      size = 3.2,
      lineheight = 0.90
    ) +
    scale_fill_gradient2(
      name = "Change vs\nControls",
      low = "#2166AC",
      mid = "white",
      high = "#B2182B",
      midpoint = 0,
      limits = c(-symmetric_limit, symmetric_limit),
      na.value = "grey90",
      labels = function(x) paste0(round(x), "%")
    ) +
    labs(
      title = "Model-based effect heatmap",
      subtitle = paste0(
        method_label,
        ": patient groups relative to Controls"
      ),
      x = "Patient group",
      y = NULL,
      caption = paste0(
        "Cell values are model-based percentage changes relative to Controls. ",
        "Blue indicates lower and red indicates higher values. Stars represent ",
        "BH-adjusted significance within each metric. Grey cells indicate ",
        "unavailable or review-required model results."
      )
    ) +
    publication_theme(base_size = 12) +
    theme(
      panel.grid = element_blank(),
      axis.text.x = element_text(face = "bold"),
      axis.text.y = element_text(size = 10),
      legend.title = element_text(face = "bold"),
      plot.margin = margin(12, 16, 10, 10)
    )

  heatmap_png <- file.path(
    summary_plot_dir,
    "summary_effect_heatmap.png"
  )
  heatmap_pdf <- file.path(
    summary_plot_dir,
    "summary_effect_heatmap.pdf"
  )

  heatmap_height <- max(
    6,
    2.8 + 0.48 * length(metric_order)
  )

  ggsave(
    filename = heatmap_png,
    plot = heatmap_plot,
    width = 12,
    height = heatmap_height,
    units = "in",
    dpi = export_dpi,
    bg = "white",
    limitsize = FALSE
  )

  ggsave(
    filename = heatmap_pdf,
    plot = heatmap_plot,
    width = 12,
    height = heatmap_height,
    units = "in",
    device = grDevices::pdf,
    bg = "white",
    limitsize = FALSE
  )

  valid_contrast_data <- effect_data %>%
    filter(
      inferential_valid,
      is.finite(percent_change_model_based),
      is.finite(CI_95_low_percent),
      is.finite(CI_95_high_percent)
    ) %>%
    mutate(
      publication_label = factor(
        publication_label,
        levels = metric_labels
      )
    )

  contrast_png <- file.path(
    summary_plot_dir,
    "summary_contrast_overview.png"
  )
  contrast_pdf <- file.path(
    summary_plot_dir,
    "summary_contrast_overview.pdf"
  )

  contrast_status <- "skipped_no_valid_contrasts"

  if (nrow(valid_contrast_data) > 0) {
    panel_ranges <- valid_contrast_data %>%
      group_by(metric) %>%
      summarise(
        panel_low = min(
          c(CI_95_low_percent, percent_change_model_based, 0),
          na.rm = TRUE
        ),
        panel_high = max(
          c(CI_95_high_percent, percent_change_model_based, 0),
          na.rm = TRUE
        ),
        .groups = "drop"
      ) %>%
      mutate(
        annotation_offset = pmax(
          0.07 * (panel_high - panel_low),
          0.5
        )
      )

    valid_contrast_data <- valid_contrast_data %>%
      left_join(panel_ranges, by = "metric") %>%
      mutate(
        annotation_y = ifelse(
          percent_change_model_based >= 0,
          CI_95_high_percent + annotation_offset,
          CI_95_low_percent - annotation_offset
        ),
        annotation_vjust = ifelse(
          percent_change_model_based >= 0,
          0,
          1
        )
      )

    contrast_plot <- ggplot(
      valid_contrast_data,
      aes(
        x = patient_group,
        y = percent_change_model_based
      )
    ) +
      geom_hline(
        yintercept = 0,
        linetype = "dashed",
        linewidth = 0.45,
        colour = "grey45"
      ) +
      geom_errorbar(
        aes(
          ymin = CI_95_low_percent,
          ymax = CI_95_high_percent
        ),
        width = 0.12,
        linewidth = 0.55
      ) +
      geom_point(
        size = 2.5,
        shape = 21,
        fill = "white",
        stroke = 0.7
      ) +
      geom_text(
        data = valid_contrast_data %>%
          filter(significance_label != ""),
        aes(
          y = annotation_y,
          label = significance_label,
          vjust = annotation_vjust
        ),
        fontface = "bold",
        size = 4
      ) +
      facet_wrap(
        ~ publication_label,
        scales = "free_y",
        ncol = 3
      ) +
      scale_y_continuous(
        labels = function(x) paste0(round(x), "%"),
        expand = expansion(mult = c(0.14, 0.18))
      ) +
      labs(
        title = "Patient-versus-Controls contrast overview",
        subtitle = paste0(
          method_label,
          ": model-based percentage changes with 95% confidence intervals"
        ),
        x = "Patient group",
        y = "Change relative to Controls",
        caption = paste0(
          "Points are model-based percentage changes relative to Controls; ",
          "error bars are 95% confidence intervals. The dashed line denotes ",
          "no difference. Stars represent BH-adjusted significance within ",
          "each metric. Only inferentially valid models are shown."
        )
      ) +
      publication_theme(base_size = 11) +
      theme(
        axis.text.x = element_text(
          angle = 45,
          hjust = 1,
          size = 9
        ),
        strip.text = element_text(
          face = "bold",
          size = 10
        ),
        panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(),
        plot.margin = margin(12, 16, 10, 10)
      )

    contrast_height <- max(
      7,
      3.25 * ceiling(length(metric_order) / 3)
    )

    ggsave(
      filename = contrast_png,
      plot = contrast_plot,
      width = 14,
      height = contrast_height,
      units = "in",
      dpi = export_dpi,
      bg = "white",
      limitsize = FALSE
    )

    ggsave(
      filename = contrast_pdf,
      plot = contrast_plot,
      width = 14,
      height = contrast_height,
      units = "in",
      device = grDevices::pdf,
      bg = "white",
      limitsize = FALSE
    )

    contrast_status <- "created"
  }

  file_index <- tibble::tibble(
    plot = c(
      "summary_effect_heatmap",
      "summary_contrast_overview"
    ),
    description = c(
      paste0(
        "Heatmap of model-based percentage changes for P1-P10 relative to ",
        "Controls across all metrics."
      ),
      paste0(
        "Multi-metric overview of model-based patient-versus-Controls ",
        "percentage effects and 95% confidence intervals."
      )
    ),
    status = c(
      "created",
      contrast_status
    ),
    png = c(
      format_repo_path(heatmap_png),
      if (contrast_status == "created") {
        format_repo_path(contrast_png)
      } else {
        NA_character_
      }
    ),
    pdf = c(
      format_repo_path(heatmap_pdf),
      if (contrast_status == "created") {
        format_repo_path(contrast_pdf)
      } else {
        NA_character_
      }
    )
  )

  list(
    index = file_index,
    effect_data = effect_data,
    heatmap_data = heatmap_data
  )
}


# ==============================================================================
# 9. COMPLETE ANALYSIS FOR ONE WORKBOOK
# ==============================================================================

#' Run the complete validated analysis for one manual or automated workbook.
#'
#' @param method_name Short analysis label used in output names.
#' @param input_path Path to the source workbook.
#' @return Invisibly returns a list containing cleaned data, statistics and
#'   output paths.
#' @details This function coordinates import, QC, model fitting, BH correction,
#'   plotting and structured Excel export. It does not silently discard model
#'   warnings: all such models are marked for review and excluded from the main
#'   inferential result table.
analyse_one_workbook <- function(method_name, input_path) {
  message("\n============================================================")
  message("Analysing ", method_name, " workbook")
  message("Input: ", input_path)
  message("============================================================\n")

  loaded <- read_cristae_workbook(input_path)
  X <- loaded$data

  metadata_columns <- c(
    "ID",
    "ID_cluster",
    "source_sheet",
    "source_row",
    "group"
  )

  variables <- setdiff(names(X), metadata_columns)
  variables <- variables[
    vapply(X[variables], is.numeric, logical(1))
  ]

  variables <- variables[
    vapply(
      X[variables],
      function(metric_values) any(is.finite(metric_values)),
      logical(1)
    )
  ]

  if (length(variables) == 0) {
    stop(
      "No numeric metric with at least one finite value remained after the ",
      "explicit exclusions in ",
      input_path,
      call. = FALSE
    )
  }

  unknown_log_metrics <- setdiff(logs, variables)

  if (length(unknown_log_metrics) > 0) {
    stop(
      "The following metrics are listed in `logs` but are not available after ",
      "data cleaning: ",
      paste(unknown_log_metrics, collapse = ", "),
      call. = FALSE
    )
  }

  method_dir <- file.path(output_root, method_name)
  plot_dir <- file.path(method_dir, "plots")
  summary_plot_dir <- file.path(method_dir, "summary_plots")
  diagnostic_dir <- file.path(method_dir, "model_diagnostics")

  dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(summary_plot_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(diagnostic_dir, recursive = TRUE, showWarnings = FALSE)

  contrast_list <- vector("list", length(variables))
  group_summary_list <- vector("list", length(variables))
  model_mean_list <- vector("list", length(variables))
  diagnostic_list <- vector("list", length(variables))
  diagnostic_plot_index_list <- vector("list", length(variables))
  fitted_models <- vector("list", length(variables))
  names(fitted_models) <- variables

  for (index in seq_along(variables)) {
    metric <- variables[index]
    message("Metric: ", metric)

    metric_result <- run_metric_model(X, metric)

    contrast_list[[index]] <- metric_result$contrasts
    group_summary_list[[index]] <- metric_result$group_summary
    model_mean_list[[index]] <- metric_result$model_means
    diagnostic_list[[index]] <- metric_result$diagnostics
    fitted_models[[metric]] <- metric_result$fit

    diagnostic_plot_index_list[[index]] <-
      save_model_diagnostic_plots(
        fit = metric_result$fit,
        metric = metric,
        diagnostic_dir = diagnostic_dir
      )
  }

  statistics_all <- dplyr::bind_rows(contrast_list) %>%
    mutate(
      p_value_for_inference = ifelse(
        inferential_valid,
        p_value,
        NA_real_
      )
    ) %>%
    group_by(metric) %>%
    mutate(
      p_adj_BH_within_metric = p.adjust(
        p_value_for_inference,
        method = "BH"
      )
    ) %>%
    ungroup() %>%
    mutate(
      p_adj_BH_all_tests = p.adjust(
        p_value_for_inference,
        method = "BH"
      ),
      patient_group = factor(
        patient_group,
        levels = names(groups$P)
      )
    ) %>%
    arrange(metric, patient_group)

  summary_by_group <- dplyr::bind_rows(group_summary_list) %>%
    mutate(
      group = factor(
        group,
        levels = unlist(lapply(groups, names), use.names = FALSE)
      )
    ) %>%
    arrange(metric, group)

  model_estimated_means <- dplyr::bind_rows(model_mean_list) %>%
    mutate(
      group = factor(
        group,
        levels = unlist(lapply(groups, names), use.names = FALSE)
      )
    ) %>%
    arrange(metric, group)

  model_diagnostics <- dplyr::bind_rows(diagnostic_list) %>%
    arrange(metric)

  diagnostic_plot_index <- dplyr::bind_rows(
    diagnostic_plot_index_list
  )

  significant_results <- statistics_all %>%
    filter(
      inferential_valid,
      !is.na(p_adj_BH_within_metric),
      p_adj_BH_within_metric < alpha
    ) %>%
    arrange(p_adj_BH_within_metric, p_value)

  review_required <- statistics_all %>%
    filter(
      model_status != "fitted" |
        !inferential_valid |
        !is.na(model_warning) |
        !is.na(model_error) |
        !is.na(convergence_message)
    ) %>%
    select(
      metric,
      comparison,
      model_status,
      inferential_valid,
      status_detail,
      singular_model,
      convergence_message,
      model_warning,
      model_error
    )

  # Legacy-format columns remain available for comparison with earlier output.
  # The estimate is the planned contrast on the model scale.
  legacy_results <- statistics_all %>%
    filter(model_status %in% c("fitted", "fitted_review_required")) %>%
    transmute(
      metric = metric,
      comparison = comparison,
      Estimate = estimate_model_scale,
      `Std. Error` = std_error_model_scale,
      df = degrees_freedom,
      `t-value` = t_value,
      `p-value` = p_value,
      inferential_valid = inferential_valid
    )

  QC_counts <- X %>%
    group_by(group, source_sheet) %>%
    summarise(
      n_rows = n(),
      n_unique_original_ID = n_distinct(ID, na.rm = TRUE),
      n_unique_ID_cluster = n_distinct(ID_cluster, na.rm = TRUE),
      .groups = "drop"
    )

  QC_missing <- tibble::tibble(
    metric = variables,
    publication_label = publication_label_for_metric(variables),
    n_rows = nrow(X),
    n_missing = vapply(
      X[variables],
      function(x) sum(is.na(x)),
      integer(1)
    ),
    n_non_finite = vapply(
      X[variables],
      function(x) sum(!is.na(x) & !is.finite(x)),
      integer(1)
    ),
    n_finite = vapply(
      X[variables],
      function(x) sum(is.finite(x)),
      integer(1)
    ),
    n_unique_finite = vapply(
      X[variables],
      function(x) length(unique(x[is.finite(x)])),
      integer(1)
    )
  ) %>%
    mutate(
      percent_missing = 100 * safe_divide(n_missing, n_rows)
    ) %>%
    arrange(desc(percent_missing), metric)

  QC_nonpositive_for_log <- if (length(logs) > 0) {
    tibble::tibble(
      metric = logs,
      n_zero = vapply(
        X[logs],
        function(x) sum(x == 0, na.rm = TRUE),
        integer(1)
      ),
      n_negative = vapply(
        X[logs],
        function(x) sum(x < 0, na.rm = TRUE),
        integer(1)
      ),
      n_excluded_from_log_model = vapply(
        X[logs],
        function(x) sum(!is.na(x) & (!is.finite(x) | x <= 0)),
        integer(1)
      )
    )
  } else {
    tibble::tibble(
      metric = character(0),
      n_zero = integer(0),
      n_negative = integer(0),
      n_excluded_from_log_model = integer(0)
    )
  }

  metrics_used <- tibble::tibble(
    metric = variables,
    publication_label = publication_label_for_metric(variables),
    transformed_for_model = variables %in% logs,
    model = "y ~ group + (1 | ID_cluster)",
    fixed_effect_strategy = paste0(
      "One model per metric; treatment-versus-control planned contrasts from ",
      "emmeans"
    ),
    minimum_rows_per_group = min_total_rows_per_group,
    minimum_independent_ID_per_group = min_independent_ID_per_group,
    minimum_unique_finite_values_per_group =
      min_unique_values_per_group
  )

  excluded_columns <- tibble::tibble(
    column = loaded$excluded_columns,
    reason = dplyr::case_when(
      normalize_column_key(column) == "numberofmito" ~
        "Explicitly excluded from this analysis.",
      normalize_column_key(column) == "erconnections" ~
        "Removed from this analysis by the project decision.",
      normalize_column_key(column) == "lengthofcontact" ~
        "Removed from this analysis by the project decision.",
      normalize_column_key(column) == "averagelengthofcontact" ~
        paste0(
          "Removed from this analysis; this derived variable is not ",
          "calculated."
        ),
      TRUE ~ "Explicitly excluded."
    )
  )

  plot_index_list <- vector("list", length(variables))

  for (index in seq_along(variables)) {
    metric <- variables[index]

    plot_index_list[[index]] <- make_metric_plot(
      X = X,
      metric = metric,
      metric_statistics = statistics_all %>%
        filter(.data$metric == .env$metric),
      metric_model_means = model_estimated_means %>%
        filter(.data$metric == .env$metric),
      plot_dir = plot_dir
    )
  }

  plot_index <- dplyr::bind_rows(plot_index_list)

  summary_plot_results <- save_summary_comparison_plots(
    statistics_all = statistics_all,
    metric_order = variables,
    method_name = method_name,
    summary_plot_dir = summary_plot_dir
  )

  summary_plot_index <- summary_plot_results$index
  summary_effects <- summary_plot_results$effect_data
  summary_heatmap_data <- summary_plot_results$heatmap_data

  output_excel <- file.path(
    method_dir,
    paste0(
      "cristae_lmm_",
      method_name,
      "_safe_results.xlsx"
    )
  )

  n_expected_contrasts <- length(variables) * length(names(groups$P))

  input_info <- tibble::tibble(
    item = c(
      "analysis",
      "method",
      "input_file",
      "output_excel",
      "plot_directory",
      "summary_plot_directory",
      "diagnostic_directory",
      "analysis_datetime",
      "model_formula",
      "random_effect",
      "ID_safety_rule",
      "fixed_effect_strategy",
      "pairwise_comparisons",
      "minimum_rows_per_group",
      "minimum_independent_ID_per_group",
      "minimum_unique_finite_values_per_group",
      "require_repeated_observations",
      "minimum_ID_with_repeated_rows",
      "log_transformed_metrics",
      "excluded_columns",
      "n_rows_clean",
      "n_unique_ID_cluster_clean",
      "n_metrics_analysed",
      "n_contrasts_expected",
      "n_contrasts_fitted_valid",
      "n_contrasts_review_required",
      "n_contrasts_skipped_or_failed",
      "multiple_testing_primary",
      "multiple_testing_secondary",
      "plot_significance_column",
      "alpha",
      "plot_jitter_seed",
      "numeric_conversion_strict_mode",
      "effect_reporting_note",
      "diagnostic_policy"
    ),
    value = c(
      "Cristae LMM analysis: safe documented publication version",
      method_name,
      format_repo_path(input_path),
      format_repo_path(output_excel),
      format_repo_path(plot_dir),
      format_repo_path(summary_plot_dir),
      format_repo_path(diagnostic_dir),
      as.character(Sys.time()),
      "y ~ group + (1 | ID_cluster)",
      "Globally unique ID_cluster",
      paste0(
        "Missing IDs are completed only inside each worksheet; ID_cluster is ",
        "the interaction of group, worksheet and original ID."
      ),
      paste0(
        "One model per metric followed by planned treatment-versus-control ",
        "contrasts."
      ),
      "Controls compared with P1-P10",
      as.character(min_total_rows_per_group),
      as.character(min_independent_ID_per_group),
      as.character(min_unique_values_per_group),
      as.character(require_repeated_observations),
      as.character(min_ID_with_repeated_rows),
      if (length(logs) > 0) {
        paste(logs, collapse = "; ")
      } else {
        "none"
      },
      if (length(loaded$excluded_columns) > 0) {
        paste(loaded$excluded_columns, collapse = "; ")
      } else {
        "none found"
      },
      as.character(nrow(X)),
      as.character(n_distinct(X$ID_cluster)),
      as.character(length(variables)),
      as.character(n_expected_contrasts),
      as.character(sum(statistics_all$inferential_valid)),
      as.character(sum(
        statistics_all$model_status == "fitted_review_required"
      )),
      as.character(sum(
        statistics_all$model_status %in% c("skipped", "failed")
      )),
      paste0(
        "Benjamini-Hochberg correction across Controls-versus-P1-P10 contrasts ",
        "within each metric."
      ),
      "Benjamini-Hochberg correction across all valid contrasts in the workbook.",
      plot_significance_column,
      as.character(alpha),
      as.character(plot_jitter_seed),
      as.character(stop_on_numeric_conversion_failure),
      paste0(
        "Untransformed metrics are reported as model-estimated differences. ",
        "Log-transformed metrics are reported as back-transformed ratios."
      ),
      paste0(
        "Singular, non-converged or warning-producing models are exported for ",
        "review but excluded from BH-adjusted inferential conclusions and ",
        "significance brackets."
      )
    )
  )

  session_info <- tibble::tibble(
    line = capture.output(sessionInfo())
  )

  workbook <- openxlsx::createWorkbook()

  add_sheet(workbook, "input_info", input_info)
  add_sheet(workbook, "session_info", session_info)
  add_sheet(workbook, "QC_counts", QC_counts)
  add_sheet(workbook, "QC_missing", QC_missing)
  add_sheet(workbook, "QC_log_values", QC_nonpositive_for_log)
  add_sheet(
    workbook,
    "numeric_conversion_audit",
    loaded$conversion_audit
  )
  add_sheet(workbook, "excluded_columns", excluded_columns)
  add_sheet(workbook, "metrics_used", metrics_used)
  add_sheet(workbook, "summary_by_group", summary_by_group)
  add_sheet(workbook, "model_means", model_estimated_means)
  add_sheet(workbook, "statistics_all", statistics_all)
  add_sheet(workbook, "significant_results", significant_results)
  add_sheet(workbook, "review_required", review_required)
  add_sheet(workbook, "model_diagnostics", model_diagnostics)
  add_sheet(workbook, "legacy_results", legacy_results)
  add_sheet(workbook, "plot_index", plot_index)
  add_sheet(workbook, "summary_effects", summary_effects)
  add_sheet(workbook, "summary_heatmap_data", summary_heatmap_data)
  add_sheet(workbook, "summary_plot_index", summary_plot_index)
  add_sheet(workbook, "diagnostic_plot_index", diagnostic_plot_index)
  add_sheet(workbook, "data_clean", X)

  openxlsx::saveWorkbook(
    workbook,
    output_excel,
    overwrite = TRUE
  )

  message("\nCompleted: ", method_name)
  message("Excel: ", output_excel)
  message("Individual plots: ", plot_dir)
  message("Summary plots: ", summary_plot_dir)
  message("Diagnostics: ", diagnostic_dir)
  message(
    "Valid planned contrasts: ",
    sum(statistics_all$inferential_valid),
    " / ",
    nrow(statistics_all)
  )
  message(
    "BH-significant valid results within metric: ",
    nrow(significant_results),
    "\n"
  )

  invisible(
    list(
      method = method_name,
      data = X,
      statistics_all = statistics_all,
      summary_by_group = summary_by_group,
      model_estimated_means = model_estimated_means,
      model_diagnostics = model_diagnostics,
      fitted_models = fitted_models,
      output_excel = output_excel,
      plot_dir = plot_dir,
      summary_plot_dir = summary_plot_dir,
      diagnostic_dir = diagnostic_dir
    )
  )
}


# ==============================================================================
# 10. RUN MANUAL AND AUTOMATED ANALYSES
# ==============================================================================

# Create the root output directory before either workbook is analysed.
dir.create(
  output_root,
  recursive = TRUE,
  showWarnings = FALSE
)

analysis_results <- vector(
  "list",
  length(input_files)
)

names(analysis_results) <- names(input_files)

for (method_name in names(input_files)) {
  analysis_results[[method_name]] <- analyse_one_workbook(
    method_name = method_name,
    input_path = input_files[[method_name]]
  )
}

message("\n============================================================")
message("ALL SAFE CRISTAE LMM ANALYSES COMPLETED")
message("Output root: ", output_root)
message("============================================================")
