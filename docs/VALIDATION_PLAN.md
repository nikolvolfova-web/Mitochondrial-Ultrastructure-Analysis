# Validation Plan

This document defines the validation procedure for reconstructing the mitochondrial ultrastructure analysis workflow.

The validation has two purposes:

1. to verify that the reconstructed workflow accurately represents the original analysis;
2. to identify and document any differences between the original analytical files, reconstructed scripts, and manuscript results.

No component will be described as reproducible until its inputs, transformations, and outputs have been verified.

## Validation principles

The validation will follow these principles:

* original files will be preserved unchanged;
* validation will be performed on working copies;
* manual and automated measurements will be treated as separate data-generation branches;
* original manual preparation steps will be documented explicitly;
* reconstructed automation will not be presented as part of the original workflow;
* every exclusion, transformation, and aggregation will be recorded;
* discrepancies will be investigated before files or manuscript results are modified;
* unpublished or potentially identifiable data will remain outside the public repository until reviewed.

## Reference files

The following original files will be preserved as private validation references:

* original manual Excel workbook;
* original automated Excel workbook;
* Python-generated CSV outputs used to prepare the automated workbook;
* original combined Prism input;
* original R scripts;
* original statistical output tables;
* original figures;
* manuscript tables and reported numerical results.

Exact filenames will be added after the reference files have been inventoried.

## Validation stages

### Stage 1 — Reference-file preservation

Create unchanged private copies of all original analytical files.

For each reference file, record:

* original filename;
* file type;
* file size;
* modification date;
* analytical purpose;
* source or creator;
* whether it was used directly in the manuscript analysis;
* SHA-256 checksum.

The checksum will allow later confirmation that the reference file has not changed.

### Stage 2 — Manual workbook audit

The manual workbook will be reviewed for:

* worksheet names;
* column names;
* units;
* row-level observational unit;
* subject and image identifiers;
* duplicated records;
* missing values;
* unexpected text values;
* inconsistent data types;
* implausible numerical values;
* formulas versus stored values;
* hidden worksheets, rows, or columns;
* filters and formatting that may affect interpretation.

Where original manual counting records remain available, selected workbook values may be compared against those records.

The audit does not assume that the manual measurements can be regenerated computationally.

### Stage 3 — Automated workbook audit

The automated workbook will first be reviewed using the same structural checks as the manual workbook.

It will then be compared with the Python-generated CSV outputs from which its values were manually transferred.

The comparison will verify:

* correspondence of sample and image identifiers;
* correspondence of selected columns;
* row counts;
* duplicated or omitted records;
* values copied into the wrong row or column;
* numerical equality;
* decimal and data-type conversions;
* missing-value handling;
* any manual corrections or exclusions.

The expected relationship is:

```text
Python CSV outputs
    → documented manual transfer
    → automated Excel workbook
```

Any value in the automated workbook that cannot be traced to a Python output or a documented correction will be flagged for investigation.

### Stage 4 — Workbook schema harmonization

The manual and automated workbooks were prepared with matching structures for downstream analysis.

The validation will document:

* columns shared by both workbooks;
* method-specific columns;
* identifier format;
* categorical levels;
* measurement units;
* required columns;
* optional columns;
* allowed missing values;
* expected uniqueness constraints.

A machine-readable or tabular schema will be added after the workbooks have been reviewed.

### Stage 5 — Prism input reconstruction

A new script will be created:

```text
scripts/R/prepare_prism_input.R
```

The script will:

* read the manual and automated workbooks;
* validate required worksheets and columns;
* standardize data types;
* add an explicit measurement-method variable;
* identify missing and duplicated records;
* combine compatible observations;
* record input and output row counts;
* export the reconstructed Prism input;
* write a validation log.

The reconstructed output will be compared with the original Prism input.

The comparison will include:

* dimensions;
* column names and order;
* identifier combinations;
* categorical values;
* numerical values;
* missing values;
* excluded rows;
* row ordering where relevant.

### Stage 6 — Total cristae-count analysis reconstruction

A new script will be created:

```text
scripts/analyze_total_cristae_glmm.R
```

Before fitting the statistical model, the script will validate:

* expected input columns;
* observation counts;
* subject and image structure;
* measurement-method levels;
* experimental groups;
* missing values;
* count-variable ranges;
* duplicated observations.

The reconstructed analysis will then be compared with:

* the original model specification;
* original coefficients;
* estimated contrasts;
* confidence intervals;
* p-values;
* diagnostics;
* manuscript tables and figures.

The exact model specification will not be documented as final until this comparison is complete.

### Stage 7 — Subject-heterogeneity analysis reconstruction

A new script will be created:

```text
scripts/analyze_subject_heterogeneity.R
```

Validation will include:

* subject-level observation counts;
* manual and automated measurement pairing;
* summary-statistic definitions;
* ordering of subjects and groups;
* values shown in plots and heatmaps;
* agreement with original analytical outputs;
* agreement with manuscript figures or reported values.

### Stage 8 — Morphometry LMM reconstruction

A new script will be created:

```text
scripts/analyze_cristae_morphometry_lmm.R
```

The script will process the two workbooks separately:

```text
Manual workbook
    → Manual LMM run

Automated workbook
    → Automated LMM run
```

For each run, validation will include:

* input worksheet and columns;
* measurement units;
* number of observations;
* number of subjects and images;
* missing and excluded values;
* statistical model formula;
* random-effects structure;
* contrasts;
* diagnostics;
* tables and figures;
* comparison with the original analysis;
* comparison with manuscript results.

Outputs from the manual and automated runs will remain clearly separated.

### Stage 9 — Software environment capture

After the R scripts execute successfully, the repository will record:

* R version;
* operating-system information;
* package versions;
* locale where relevant;
* random seeds where relevant;
* `renv.lock`;
* installation and execution instructions.

The environment lock will be created only after the validated dependency set is known.

### Stage 10 — End-to-end manuscript comparison

A private comparison table will map reconstructed results to the manuscript.

Suggested structure:

| Manuscript location | Reported value | Reconstructed value | Agreement | Explanation | Required action |
| ------------------- | -------------: | ------------------: | --------- | ----------- | --------------- |
| `<TABLE_OR_FIGURE>` |           TODO |                TODO | TODO      | TODO        | TODO            |

The comparison should include:

* sample sizes;
* descriptive statistics;
* model coefficients;
* contrasts;
* confidence intervals;
* p-values;
* plotted values;
* figure labels;
* statements in Results;
* statements in the abstract or conclusions that depend on the analysis.

## Discrepancy classification

Each discrepancy will be assigned one of the following categories.

### No issue

Examples:

* row ordering differs but values are identical;
* formatting differs;
* displayed rounding differs without changing the underlying value.

### Technical reproducibility issue

Examples:

* local filesystem path;
* missing package-version record;
* locale-dependent parsing;
* undocumented worksheet name.

### Data-transfer discrepancy

Examples:

* value copied incorrectly from CSV to workbook;
* omitted image;
* duplicated observation;
* identifier assigned to the wrong record.

### Data-processing discrepancy

Examples:

* undocumented filtering;
* inconsistent missing-value handling;
* different aggregation rule;
* accidental exclusion or inclusion.

### Statistical discrepancy

Examples:

* different model formula;
* different random-effects structure;
* incorrect contrast;
* different analysis population.

### Manuscript-impacting discrepancy

A discrepancy is manuscript-impacting when it changes:

* a reported numerical result;
* a table or figure;
* statistical significance;
* direction or magnitude of an effect;
* interpretation;
* conclusion.

## Priority levels

Findings will be classified as:

* **Blocking** — prevents reliable reconstruction or may invalidate a main result;
* **High priority** — affects analytical correctness or manuscript values;
* **Medium priority** — affects reproducibility or documentation;
* **Low priority** — affects clarity or maintainability;
* **Optional** — improvement without impact on correctness.

## Required documentation for each finding

Every identified issue should record:

* affected file;
* affected worksheet, column, row, or script section;
* what was observed;
* expected behavior;
* likely cause;
* analytical impact;
* proposed correction;
* verification procedure;
* resolution status.

## Release criteria

The workflow will be considered ready for a formal software release only when:

* original reference files have been preserved;
* workbook schemas are documented;
* the automated workbook has been compared with the source Python CSV outputs;
* the Prism input is reproducibly generated;
* all R scripts execute successfully;
* analytical outputs are compared with the original outputs;
* manuscript values are checked;
* discrepancies are resolved or transparently documented;
* Python and R dependencies are recorded;
* sensitive data and metadata have been reviewed;
* README and citation metadata accurately describe the validated workflow;
* no unsupported reproducibility claims remain.

## Current status

| Validation stage                         | Status  |
| ---------------------------------------- | ------- |
| Preserve original reference files        | Pending |
| Manual workbook audit                    | Pending |
| Automated workbook audit                 | Pending |
| Python CSV comparison                    | Pending |
| Workbook schema documentation            | Pending |
| Prism input reconstruction               | Planned |
| Total cristae-count reconstruction       | Planned |
| Subject-heterogeneity reconstruction     | Planned |
| Manual morphometry LMM reconstruction    | Planned |
| Automated morphometry LMM reconstruction | Planned |
| R environment capture                    | Pending |
| Manuscript comparison                    | Pending |
| Release-readiness review                 | Pending |
