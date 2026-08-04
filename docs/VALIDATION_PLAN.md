# Validation Plan

This document defines the validation and release-readiness procedure for the
Mitochondrial Ultrastructure Analysis repository.

The Python preprocessing workflow and all six R analysis workflows are
implemented and have passed their GitHub Actions checks. The analyses contained
in this repository represent the current analytical workflow. The curated data
and analytical outputs in this repository are those reported in the associated
publication.

The remaining work focuses on traceability, internal consistency,
reproducibility, confidentiality review, publication consistency, and formal
release preparation.

## Validation objectives

The validation has four objectives:

1. verify that every repository analytical input has a documented origin;
2. confirm that all repository workflows execute successfully and create the
   expected outputs;
3. verify that generated results are internally consistent and correspond to
   those reported in the associated publication;
4. ensure that the repository is safe, documented, citable, and suitable for a
   later versioned GitHub Release and Zenodo archive.

## Validation principles

The project follows these principles:

- source and reference files are preserved unchanged where applicable;
- validation is performed on working copies or repository copies;
- manual and automated measurements remain distinct data-generation branches;
- manual transfer and curation steps are documented explicitly;
- the repository scripts define the current analytical workflow;
- exclusions, transformations, aggregation rules, and statistical models are
  documented;
- generated outputs are checked before publication or formal release;
- confidential, identifying, or unpublished material is not released without
  review;
- discrepancies are investigated before repository files or publication text
  are finalized;
- unknown metadata are marked as pending rather than invented.

## Repository components covered by validation

### Curated analytical inputs

```text
data/curated/cristae_manual.xlsx
data/curated/cristae_automated.xlsx
```

### Processed Python outputs

```text
data/processed/python/all_cristae_instances.csv
data/processed/python/cristae_counts_per_mito.csv
data/processed/python/cristae_counts_image_summary.csv
```

### Representative QC example

```text
docs/qc_examples/C2_002_30000x/
```

This directory contains the representative mitochondrial-label and cristae QC
files, its own `README.md`, and `qc_manifest.csv`.

### Analysis scripts

```text
scripts/python/count_cristae_per_mito.py

scripts/R/prepare_prism_input.R
scripts/R/analyze-total-cristae.R
scripts/R/Heterogeneity_subjects.R
scripts/R/Cristae_LMM.R
scripts/R/Global_class_profile_across_cristae_labels.R
scripts/R/cristae_Bland_Altman.R
```

### Automated workflows

```text
.github/workflows/python-tests.yml
.github/workflows/r-prepare-prism.yml
.github/workflows/r-total-cristae.yml
.github/workflows/r-heterogeneity.yml
.github/workflows/r-cristae-lmm.yml
.github/workflows/r-global-class-profile.yml
.github/workflows/r-cristae-bland-altman.yml
```

## Completed automated validation

### 1. Python preprocessing test

The synthetic Python test suite is located in:

```text
tests/python/
```

It is executed by:

```text
.github/workflows/python-tests.yml
```

The workflow checks that the documented Python command-line implementation
executes on controlled synthetic fixtures and satisfies the tested invariants.

Status:

```text
Passed
```

This test validates the repository implementation. It does not reproduce the
complete research workflow from raw microscopy images.

### 2. Prism input preparation

The workflow:

```text
.github/workflows/r-prepare-prism.yml
```

runs:

```text
scripts/R/prepare_prism_input.R
```

against:

```text
data/curated/cristae_manual.xlsx
data/curated/cristae_automated.xlsx
```

The workflow verifies successful generation of:

```text
results/derived/Prism_input.xlsx
```

Status:

```text
Passed
```

### 3. Total cristae-count analysis

The workflow:

```text
.github/workflows/r-total-cristae.yml
```

runs:

```text
scripts/R/analyze-total-cristae.R
```

against the generated Prism input and verifies the expected analytical outputs.

Status:

```text
Passed
```

### 4. Between-subject heterogeneity analysis

The workflow:

```text
.github/workflows/r-heterogeneity.yml
```

runs:

```text
scripts/R/Heterogeneity_subjects.R
```

against the generated Prism input and verifies the expected analytical outputs.

Status:

```text
Passed
```

### 5. Cristae linear mixed-model analysis

The workflow:

```text
.github/workflows/r-cristae-lmm.yml
```

runs:

```text
scripts/R/Cristae_LMM.R
```

against both curated workbooks and verifies the expected manual and automated
Excel workbooks, plots, summary plots, and diagnostic outputs.

Status:

```text
Passed
```

### 6. Global cristae class-profile analysis

The workflow:

```text
.github/workflows/r-global-class-profile.yml
```

runs:

```text
scripts/R/Global_class_profile_across_cristae_labels.R
```

against both curated workbooks.

The workflow verifies generation of:

```text
results/derived/global_class_profile/global_class_profile_data.xlsx
results/derived/global_class_profile/global_class_profile_dumbbell_colored.png
results/derived/global_class_profile/global_class_profile_dumbbell_colored.pdf
```

Status:

```text
Passed
```

### 7. Manual-versus-automated agreement analysis

The workflow:

```text
.github/workflows/r-cristae-bland-altman.yml
```

runs:

```text
scripts/R/cristae_Bland_Altman.R
```

against both curated workbooks.

The workflow verifies the statistical workbook, text summaries, R session
information, and Bland-Altman, scatter, and combined figures exported as PDF,
PNG, and TIFF.

Status:

```text
Passed
```

## Validation stages

## Stage 1 — Preserve source and reference files

The following files should be preserved as reference material when available:

- original manual workbook;
- original automated workbook;
- original Python-generated outputs;
- original combined Prism input;
- original scripts and analysis notes;
- original statistical output tables;
- original figures.

For each reference file, record where practical:

- filename;
- file type;
- file size;
- modification date;
- analytical purpose;
- source or creator;
- SHA-256 checksum;
- protected storage location.

These files are preserved for traceability. The current repository analysis is
not required to reproduce an earlier analytical implementation exactly.

## Stage 2 — Manual workbook audit

Audit:

```text
data/curated/cristae_manual.xlsx
```

Review:

- worksheet names;
- column names;
- row-level observational unit;
- subject and image identifiers;
- duplicated records;
- missing values;
- unexpected text values;
- inconsistent data types;
- formulas versus stored values;
- hidden worksheets, rows, or columns;
- implausible numerical values;
- compatibility with all downstream R workflows.

The workbook has passed operational validation because all relevant R workflows
execute successfully against it.

Before formal public release, confirm that its schema is documented clearly
enough for an external user and that workbook metadata have been reviewed.

## Stage 3 — Automated workbook audit

Audit:

```text
data/curated/cristae_automated.xlsx
```

Perform the same structural checks as for the manual workbook.

In addition, compare the workbook with:

```text
data/processed/python/all_cristae_instances.csv
data/processed/python/cristae_counts_per_mito.csv
data/processed/python/cristae_counts_image_summary.csv
```

The comparison should verify:

- sample and image identifiers;
- transferred columns;
- row counts;
- duplicated or omitted records;
- values copied into the wrong row or column;
- numerical equality where direct equality is expected;
- decimal and data-type conversions;
- missing-value handling;
- documented manual exclusions;
- correspondence between the curated workbook and visual QC decisions.

The expected relationship is:

```text
Python-generated outputs
    → manual transfer of relevant values
    → visual review of mitochondrial labels
    → exclusion of confirmed segmentation errors
    → curated automated workbook
```

A value that cannot be traced to a Python output or a documented curation
decision should be flagged.

## Stage 4 — Representative QC verification

Review:

```text
docs/qc_examples/C2_002_30000x/
```

Verify that:

- every listed QC file exists;
- `qc_manifest.csv` matches the directory contents;
- the local `README.md` explains the example correctly;
- labels 1 and 4 are documented as valid mitochondrial profiles;
- labels 2 and 3 are documented as segmentation errors;
- exclusion is not described as being caused by a zero crista count;
- the example does not expose confidential metadata;
- no protected patient-level QC material is included.

## Stage 5 — Prism input verification

Run:

```bash
Rscript scripts/R/prepare_prism_input.R
```

Verify:

- both curated workbooks are read successfully;
- the expected worksheets and columns are found;
- manual and automated records are joined as intended;
- missing images are reported;
- output dimensions are plausible;
- the generated workbook contains the expected sheets;
- generated values agree with the repository inputs.

Primary output:

```text
results/derived/Prism_input.xlsx
```

Automated execution and expected-output verification have passed.

## Stage 6 — Total cristae-count analysis verification

Run:

```bash
Rscript scripts/R/analyze-total-cristae.R
```

Verify:

- expected input columns;
- image and subject structure;
- measurement-method levels;
- count ranges;
- missing-value handling;
- offset definition;
- random-effects structure;
- planned contrasts;
- model diagnostics;
- generated tables and figures;
- numerical consistency across exported tables, figures, and summaries.

Automated workflow status:

```text
Passed
```

Publication consistency status:

```text
Confirmed
```

## Stage 7 — Between-subject heterogeneity verification

Run:

```bash
Rscript scripts/R/Heterogeneity_subjects.R
```

Verify:

- subject identifiers;
- manual and automated method separation;
- subject-level aggregation rules;
- control reference-range calculations;
- image-level variability summaries;
- crista-class profile calculations;
- generated tables, plots, and heatmaps;
- numerical consistency across exported outputs.

Automated workflow status:

```text
Passed
```

Publication consistency status:

```text
Confirmed
```

## Stage 8 — Cristae LMM verification

Run:

```bash
Rscript scripts/R/Cristae_LMM.R
```

Verify separately for the manual and automated workbooks:

- imported worksheets and columns;
- globally unique `ID_cluster` construction;
- minimum-data eligibility rules;
- retained metrics;
- excluded variables;
- model formula;
- planned Controls-versus-P1-P10 contrasts;
- multiple-testing correction;
- singularity and convergence flags;
- model diagnostics;
- Excel result tables;
- individual and summary plots;
- numerical consistency across all exported outputs.

The implemented model formula is:

```text
y ~ group + (1 | ID_cluster)
```

The excluded columns are:

```text
Number of mito
ER connections
length of contact
average length of contact
```

Automated workflow status:

```text
Passed
```

Publication consistency status:

```text
Confirmed
```

## Stage 9 — Global cristae class-profile verification

Run:

```bash
Rscript scripts/R/Global_class_profile_across_cristae_labels.R
```

Verify:

- both curated workbooks are read directly;
- all required columns from `Label 2` through `Label 12` are identified;
- repeated non-numeric header rows are not included in totals;
- valid values are summed separately for manual and automated methods;
- relative abundances sum to approximately 100% within each method;
- label order is preserved from `Label 2` through `Label 12`;
- the exported Excel table matches the values plotted;
- PNG and PDF figures are readable and non-empty;
- output paths match the documentation.

Primary outputs:

```text
results/derived/global_class_profile/global_class_profile_data.xlsx
results/derived/global_class_profile/global_class_profile_dumbbell_colored.png
results/derived/global_class_profile/global_class_profile_dumbbell_colored.pdf
```

Automated workflow status:

```text
Passed
```

Publication consistency status:

```text
Confirmed
```

## Stage 10 — Manual-versus-automated agreement verification

Run:

```bash
Rscript scripts/R/cristae_Bland_Altman.R
```

Verify:

- both curated workbooks are read directly;
- Label 2-Label 12 counts are aggregated correctly at image level;
- pairing uses worksheet name and image identifier rather than row order;
- duplicate pairing keys are absent;
- manual and automated image sets pair completely;
- the difference is defined as `automated - manual`;
- bias and 95% limits of agreement are calculated as documented;
- confidence intervals are exported correctly;
- Pearson correlation is reported separately from agreement;
- the ordinary least-squares regression matches the exported plot;
- proportional-bias and Shapiro-Wilk diagnostics are exported;
- the statistical workbook and text summary agree;
- PDF, PNG, and TIFF figures are readable and non-empty;
- the combined panel contains both expected plots.

Primary output root:

```text
results/derived/cristae_bland_altman/
```

Automated workflow status:

```text
Passed
```

Publication consistency status:

```text
Confirmed
```

## Stage 11 — Software environment capture

### Python

The Python dependency record is stored in:

```text
requirements-python.txt
```

Before formal release, verify:

- supported Python version;
- clean installation in a new environment;
- successful local test execution;
- agreement between local and GitHub Actions execution.

### R

The workflows install the packages required by the individual scripts.

The LMM workflow records session information in its generated result workbook.
The Bland-Altman workflow exports:

```text
results/derived/cristae_bland_altman/R_session_info.txt
```

Before formal release, decide whether to:

1. add a verified `renv.lock` file; or
2. document the exact R and package versions used for the release in another
   reproducible form.

Do not claim an R dependency lock while no verified lock file exists.

## Stage 12 — Publication reporting consistency

The curated data and analytical outputs in this repository are those reported
in the associated publication.

Verify that:

- sample sizes match the validated repository outputs;
- descriptive statistics correspond to the correct tables;
- model coefficients and effect measures correspond to the exported results;
- contrasts and confidence intervals match the exported results;
- raw and adjusted p-values are distinguished;
- Bland-Altman bias and limits of agreement match the exported results;
- Pearson correlation is not presented as evidence of agreement;
- global class-profile values match the exported summary table;
- figure labels match the generated plots;
- the Methods section describes the implemented workflows;
- the Results section corresponds to the repository analyses;
- statements in the abstract and conclusions are supported by the results;
- repository version and release information are cited consistently.

## Stage 13 — Documentation consistency audit

Verify consistency across:

```text
README.md
scripts/README.md
data/README.md
docs/DATA_PROVENANCE.md
docs/VALIDATION_PLAN.md
CITATION.cff
LICENSE
CONTRIBUTING.md
SECURITY.md
GitHub Release notes
Zenodo metadata
```

Check:

- repository title;
- repository URL;
- author names and order;
- ORCID identifiers;
- affiliations;
- software version;
- release date;
- license;
- workflow names;
- script names;
- file paths;
- input and output descriptions;
- data-availability statements;
- article citation;
- DOI values;
- keywords;
- funding information;
- related identifiers.

Unknown values must remain omitted or explicitly marked as pending.

## Discrepancy classification

### No issue

Examples:

- row ordering differs but values are identical;
- formatting differs;
- displayed rounding differs without changing the underlying value.

### Technical reproducibility issue

Examples:

- local filesystem path;
- missing dependency-version record;
- locale-dependent parsing;
- undocumented worksheet name;
- workflow path mismatch.

### Data-transfer discrepancy

Examples:

- value copied incorrectly from CSV to workbook;
- omitted image;
- duplicated observation;
- identifier assigned to the wrong record.

### Data-processing discrepancy

Examples:

- undocumented filtering;
- inconsistent missing-value handling;
- different aggregation rule;
- accidental exclusion or inclusion.

### Statistical discrepancy

Examples:

- inconsistent model formula between code and documentation;
- incorrect random-effects description;
- incorrect Bland-Altman difference definition;
- incorrect limit-of-agreement calculation;
- incorrect offset;
- incorrect contrast;
- inconsistent analysis population;
- incorrect multiple-testing description.

### Publication-reporting discrepancy

A publication-reporting discrepancy occurs when the publication does not match
the validated repository analysis, for example:

- an inconsistent numerical result;
- an incorrect table or figure value;
- an incorrect significance statement;
- an inconsistent method description;
- an interpretation unsupported by the analysis;
- correlation incorrectly described as agreement.

## Priority levels

Findings are classified as:

- **Blocking** — prevents reliable validation or publication;
- **High priority** — affects analytical correctness or reported results;
- **Medium priority** — affects reproducibility or essential documentation;
- **Low priority** — affects clarity or maintainability;
- **Optional** — improvement without impact on correctness.

## Required record for each finding

Every identified issue should record:

- priority;
- affected file;
- affected worksheet, column, row, or script section;
- observed behavior;
- expected behavior;
- likely cause;
- analytical impact;
- proposed correction;
- file to change;
- verification procedure;
- resolution status.

## Release criteria

The repository is ready for a formal software release only when:

- source and reference files have been inventoried where applicable;
- curated workbook schemas are documented;
- the automated workbook has been checked against processed Python outputs and
  curation records;
- the representative QC example has passed confidentiality review;
- all seven GitHub Actions workflows pass on the release candidate;
- generated R outputs have been reviewed;
- publication text, values, and figures are consistent with the validated
  repository results;
- discrepancies are resolved or transparently documented;
- Python and R dependency information is sufficient for the release;
- README and script documentation match the final repository tree;
- `CITATION.cff` contains verified release metadata;
- no DOI, ORCID, affiliation, funding, or author information is invented;
- sensitive data and embedded metadata have been reviewed;
- the release tag and GitHub Release use the same version;
- Zenodo metadata are consistent with GitHub and `CITATION.cff`.

## Current status

| Validation item | Status |
| --- | --- |
| Python preprocessing script | Included |
| Python dependency record | Included |
| Synthetic Python tests | Passed |
| Python GitHub Actions workflow | Passed |
| Processed Python CSV files | Included |
| Curated manual workbook | Included |
| Curated automated workbook | Included |
| Representative QC example | Included |
| Prism input preparation script | Implemented |
| Prism input GitHub Actions workflow | Passed |
| Total cristae-count script | Implemented |
| Total cristae-count GitHub Actions workflow | Passed |
| Subject-heterogeneity script | Implemented |
| Subject-heterogeneity GitHub Actions workflow | Passed |
| Manual and automated LMM script | Implemented |
| LMM GitHub Actions workflow | Passed |
| Global cristae class-profile script | Implemented |
| Global class-profile GitHub Actions workflow | Passed |
| Manual-versus-automated agreement script | Implemented |
| Bland-Altman GitHub Actions workflow | Passed |
| Expected R output verification | Passed |
| Publication consistency with repository analyses | Confirmed |
| Python CSV-to-workbook traceability audit | Pending final release audit |
| Source and reference-file inventory | Pending verification |
| Final review of generated analytical outputs | Completed |
| R dependency lock with `renv` | Not currently implemented |
| Root-level `CITATION.cff` | Included |
| Final release metadata in `CITATION.cff` | Pending formal release |
| Formal GitHub Release | Pending |
| Zenodo archive and DOI | Pending |
