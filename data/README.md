# Data Directory

This directory is reserved for documented, reviewed, and release-appropriate data files associated with the mitochondrial ultrastructure analysis workflow.

The original research workbooks, microscopy data, intermediate analytical files, and unpublished results are not currently included in this repository.

## Data provenance summary

The study contains two measurement branches:

1. **Manual measurements** recorded directly in a manually prepared Excel workbook.
2. **Automated measurements** derived from Empanada segmentation outputs and processed using the Python preprocessing workflow.

Relevant values from the Python-generated CSV outputs were manually transferred into an automated Excel workbook structured to match the manual workbook.

The manual and automated workbooks were then used in the downstream R workflows.

See [`docs/DATA_PROVENANCE.md`](../docs/DATA_PROVENANCE.md) for the complete provenance description.

## Directory policy

Only files that have passed a release review may be committed under `data/`.

Before inclusion, every research-derived file must be reviewed for:

* subject and sample identifiers;
* image and acquisition filenames;
* local filesystem paths;
* worksheet and document metadata;
* hidden worksheets, rows, or columns;
* formulas and external links;
* personal or confidential information;
* unpublished results;
* licensing and consent restrictions;
* consistency with the associated manuscript;
* sufficient documentation of provenance and schema.

## Files not currently included

The following files must remain outside the repository until explicitly reviewed and approved:

* original manual Excel workbook;
* original automated Excel workbook;
* original combined Prism input;
* raw or processed microscopy images;
* segmentation masks;
* complete Python output directories;
* per-image research CSV files;
* unpublished statistical tables;
* unpublished figures;
* manuscript drafts;
* files containing real names or identifying information;
* files containing internal paths or credentials.

These files should be stored in a protected research-data location rather than in the Git working directory.

## Private local data

Local research files may be organized outside the public repository using a structure such as:

```text
private_validation_data/
├── manual_workbook/
├── automated_workbook/
├── python_csv_outputs/
├── original_prism_input/
├── original_r_outputs/
└── manuscript_reference/
```

This directory name is illustrative. The actual protected location must not be committed to Git.

The repository `.gitignore` should exclude any local private-data directory used during validation.

## Potential future repository contents

After validation and release review, this directory may contain selected files such as:

```text
data/
├── README.md
├── schemas/
│   ├── manual_workbook_schema.csv
│   ├── automated_workbook_schema.csv
│   └── prism_input_schema.csv
├── examples/
│   └── synthetic_example_data.csv
└── reference/
    └── pseudonymized_release_table.csv
```

The inclusion of these files is not guaranteed. Each file must be evaluated separately.

## Preferred public data types

Where possible, the repository should prefer:

* synthetic test fixtures;
* empty schema templates;
* column dictionaries;
* pseudonymized and publication-compatible summary tables;
* machine-readable validation reports;
* small example datasets created specifically for documentation.

Synthetic or example data must be clearly labelled and must not be presented as original research observations.

## Python outputs

The Python preprocessing script may generate:

* per-image CSV files;
* summary CSV files;
* instance-level quality-control tables;
* label images;
* image overlays;
* run logs.

Generated outputs should initially be written to a protected location:

```text
<PROTECTED_OUTPUT_DIRECTORY>
```

They must not be committed automatically.

Before any Python-derived table is added to the repository, verify:

* filename and identifier pseudonymization;
* absence of absolute local paths;
* absence of confidential metadata;
* correspondence with the documented Python run;
* correspondence with the automated Excel workbook where applicable;
* relevance to reproducibility;
* appropriate licensing.

## Excel workbooks

The original Excel workbooks are analytical source files and are not currently public repository assets.

Before considering release of any workbook, inspect:

* all worksheets;
* hidden worksheets;
* hidden rows and columns;
* formulas;
* named ranges;
* comments and notes;
* external links;
* workbook properties;
* author and organization metadata;
* revision information;
* file paths;
* subject and sample identifiers.

Where practical, a reviewed CSV or other non-proprietary tabular export may be preferable to releasing the original workbook.

Any released export must be compared with the source workbook to confirm that values, missing data, identifiers, units, and categorical levels remain correct.

## Combined Prism input

The combined Prism input is a derived analytical table generated from the manual and automated workbooks.

The reconstructed version will be created using:

```text
scripts/prepare_prism_input.R
```

The original and reconstructed Prism input files must remain private until they have been compared and reviewed.

Before release, document:

* source workbooks;
* source worksheets;
* required columns;
* row-level observational unit;
* method designation;
* transformation rules;
* exclusions;
* missing-value handling;
* output dimensions;
* checksum or version identifier.

## File naming

Public data filenames should:

* use English;
* avoid personal names;
* avoid internal laboratory abbreviations unless documented;
* avoid dates that reveal internal processing history unless relevant;
* use lowercase letters and underscores where practical;
* clearly distinguish synthetic, example, derived, and research data.

Examples:

```text
synthetic_cristae_counts.csv
manual_workbook_schema.csv
automated_workbook_schema.csv
reconstructed_prism_input_v1.csv
```

Do not use filenames containing:

```text
<REAL_SUBJECT_NAME>
<LOCAL_USERNAME>
<ABSOLUTE_PATH>
<CONFIDENTIAL_PROJECT_CODE>
```

## Identifiers

Any released research-derived data must use verified pseudonymous identifiers.

Current intended public identifier patterns are:

```text
C1–C2
P1–P10
```

These patterns must be verified against the final manuscript and release dataset before publication.

The repository must not contain a lookup table connecting pseudonymous identifiers to real persons or confidential records.

## Validation requirement

A data file may be committed only when the following information is available:

| Requirement                         | Required |
| ----------------------------------- | -------- |
| Provenance documented               | Yes      |
| Observational unit documented       | Yes      |
| Columns and units documented        | Yes      |
| Identifier audit completed          | Yes      |
| Missing values reviewed             | Yes      |
| Duplicate records reviewed          | Yes      |
| Local paths removed                 | Yes      |
| Embedded metadata reviewed          | Yes      |
| Manuscript consistency checked      | Yes      |
| Release permission confirmed        | Yes      |
| Data license specified where needed | Yes      |

## Licensing

The repository MIT License applies to source code and original documentation.

It does not automatically license:

* research measurements;
* microscopy images;
* segmentation masks;
* generated research tables;
* figures;
* manuscript content.

Any released research data must have an explicit and appropriate data license or usage statement.

Do not assume that data may be redistributed solely because the analysis code is available under the MIT License.

## Current status

| Data component                 | Repository status                      |
| ------------------------------ | -------------------------------------- |
| Synthetic Python test data     | Included within tests where applicable |
| Manual workbook                | Private; pending audit                 |
| Automated workbook             | Private; pending audit                 |
| Python research CSV outputs    | Private; pending audit                 |
| Original Prism input           | Private; pending audit                 |
| Reconstructed Prism input      | Not yet generated                      |
| Workbook schemas               | Not yet documented                     |
| Public research-derived tables | Not yet approved                       |
| Microscopy images and masks    | Maintained outside this repository     |
