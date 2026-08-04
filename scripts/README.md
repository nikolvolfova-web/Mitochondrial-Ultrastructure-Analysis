# Analysis Scripts

This directory contains the computational workflows associated with the mitochondrial ultrastructure analysis.

## Current contents

### Python preprocessing

```text
scripts/python/count_cristae_per_mito.py
```

The Python script processes automated segmentation outputs originating from the associated Empanada-based image-analysis workflow.

It applies only to the automated measurement branch. Manual measurements were recorded independently and did not pass through this script.

The Python component is currently included and covered by synthetic tests.

## Planned R scripts

The R workflows are being reconstructed from the original analytical logic and will be added only after their inputs, transformations, and outputs have been validated.

### Prism input preparation

```text
scripts/R/prepare_prism_input.R
```

Planned responsibilities:

* read the manual and automated Excel workbooks;
* validate their expected schemas;
* standardize identifiers and data types;
* record missing and duplicated observations;
* combine the two measurement methods;
* export the combined Prism input;
* generate a validation log.

### Total cristae-count analysis

```text
scripts/analyze_total_cristae_glmm.R
```

Planned responsibilities:

* read the combined Prism input;
* validate the experimental structure;
* reproduce the original count-data analysis;
* generate diagnostics, contrasts, tables, and figures;
* compare reconstructed results with the original outputs and manuscript.

### Between-subject heterogeneity analysis

```text
scripts/analyze_subject_heterogeneity.R
```

Planned responsibilities:

* read the combined Prism input;
* calculate subject-level summaries;
* compare manual and automated measurements;
* generate plots and heatmaps;
* verify agreement with the original analysis.

### Cristae morphometry analysis

```text
scripts/analyze_cristae_morphometry_lmm.R
```

This workflow will process the original workbooks separately:

```text
Manual workbook
    → Manual LMM run

Automated workbook
    → Automated LMM run
```

Planned responsibilities:

* validate each method-specific input;
* reproduce the original linear mixed-effects analysis;
* generate separate diagnostics, tables, and figures;
* compare each run with its corresponding original results.

## Original versus reconstructed scripts

The new R scripts will be reconstructed implementations of the original analytical workflow.

They may add:

* explicit input arguments;
* schema validation;
* reproducible output directories;
* structured logs;
* dependency documentation;
* automated checks;
* clearer English names and messages.

Such improvements will be documented as part of the reconstructed workflow and will not be presented as procedures that were necessarily present in the original analysis.

## Validation requirements

An R script will be considered ready for inclusion only after:

* its source workbook or table has been identified;
* required worksheets and columns are documented;
* the observational unit is defined;
* exclusions and missing-value handling are documented;
* the script executes successfully on a protected working copy;
* generated outputs are compared with the original outputs;
* relevant results are compared with the manuscript;
* package dependencies are recorded;
* local paths and confidential information have been removed.

See:

* [`../docs/DATA_PROVENANCE.md`](../docs/DATA_PROVENANCE.md)
* [`../docs/VALIDATION_PLAN.md`](../docs/VALIDATION_PLAN.md)

## Data protection

The `scripts/` directory must not contain:

* original research workbooks;
* Python research CSV outputs;
* microscopy files;
* manuscript drafts;
* unpublished results;
* personal identifiers;
* credentials;
* hard-coded private filesystem paths.
