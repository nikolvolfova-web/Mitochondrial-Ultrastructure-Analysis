# Mitochondrial Ultrastructure Analysis

Pre-release repository for computational preprocessing, quality control, and statistical analysis of mitochondrial ultrastructure and cristae morphology data.

> **Project status:** The Python preprocessing workflow and all four R analysis workflows are implemented and have passed their GitHub Actions checks. The repository has not yet been formally released, archived in Zenodo, or assigned a DOI.

## Project scope

The repository supports two related analytical branches:

1. **Manual measurements** recorded directly in a curated Excel workbook.
2. **Automated measurements** derived from Empanada segmentation outputs using Python preprocessing and subsequently transferred into a curated Excel workbook with the same analytical structure as the manual workbook.

The Python preprocessing step applies only to the automated branch. Both curated workbooks are then used by the downstream R workflows.

## Related image-analysis project

The automated segmentation outputs processed by the Python workflow originate from the associated repository:

[Analysis of Mitochondrial Ultrastructure and Morphology](https://github.com/LMCF-IMG/Analysis_Mitochondrial_Ultrastructure_and_Morphology)

Raw microscopy images and upstream segmentation inputs are maintained outside this repository and are not duplicated here.

## Authors and contributions

- **Nikol Volfová** — manual data evaluation, R-based statistical analyses, repository integration, documentation, testing, and maintenance.
- **Martin Čapek** ([LMCF-IMG](https://github.com/LMCF-IMG)) — original author of the Python preprocessing script and its core computational logic.

The repository version of the Python script was adapted for portable command-line use, documented, and covered by synthetic tests with Martin Čapek's knowledge and permission.

This software contribution statement does not determine authorship of the associated research article.

## Analysis overview

```mermaid
flowchart TD
    M1["Manual cristae evaluation"] --> M2["data/curated/cristae_manual.xlsx"]

    E1["Empanada segmentation outputs"] --> P["scripts/python/count_cristae_per_mito.py"]
    P --> C["Python CSV outputs"]
    C --> A["data/curated/cristae_automated.xlsx"]

    M2 --> PI["scripts/R/prepare_prism_input.R"]
    A --> PI
    PI --> PT["results/derived/Prism_input.xlsx"]

    PT --> T["scripts/R/analyze-total-cristae.R"]
    PT --> H["scripts/R/Heterogeneity_subjects.R"]

    M2 --> LMM["scripts/R/Cristae_LMM.R"]
    A --> LMM

    T --> O1["Total-cristae tables and diagnostics"]
    H --> O2["Subject-level heterogeneity outputs"]
    LMM --> O3["LMM tables, plots, summaries, and diagnostics"]
```

## Data provenance and quality control

### Manual branch

Cristae were evaluated manually and recorded directly in:

```text
data/curated/cristae_manual.xlsx
```

This workbook is the curated tabular record used for the manual branch of the downstream analyses.

### Automated branch

Empanada segmentation outputs were processed using:

```text
scripts/python/count_cristae_per_mito.py
```

The Python workflow generates per-image and summary CSV outputs together with quality-control information. Relevant values were then transferred into:

```text
data/curated/cristae_automated.xlsx
```

The automated workbook follows the analytical structure of the manual workbook and is the curated input used by the downstream R analyses.

### Quality control of mitochondrial segmentation objects

The automated workflow was designed to quantify cristae, not to independently benchmark mitochondrial segmentation.

Mitochondrial labels were used to define compartments to which detected cristae were assigned. Before statistical analysis, the labels were visually reviewed to identify clear segmentation errors.

Labels that did not correspond to real mitochondrial profiles in the source image were excluded because they did not represent valid compartments for cristae quantification. The exclusion criterion was not based on the number of detected cristae. Valid mitochondrial profiles with zero detected cristae remained included.

The original Python CSV outputs were retained unchanged as the primary computational output. The automated Excel workbook represents the curated analytical dataset used for downstream cristae analyses.

## Repository structure

```text
.
├── .github/
│   ├── ISSUE_TEMPLATE/
│   └── workflows/
│       ├── python-tests.yml
│       ├── r-prepare-prism.yml
│       ├── r-total-cristae.yml
│       ├── r-heterogeneity.yml
│       └── r-cristae-lmm.yml
├── data/
│   └── curated/
│       ├── cristae_manual.xlsx
│       └── cristae_automated.xlsx
├── metadata/
│   └── CITATION.cff.template
├── scripts/
│   ├── R/
│   │   ├── prepare_prism_input.R
│   │   ├── analyze-total-cristae.R
│   │   ├── Heterogeneity_subjects.R
│   │   └── Cristae_LMM.R
│   ├── python/
│   │   └── count_cristae_per_mito.py
│   └── README.md
├── tests/
│   └── python/
│       └── test_count_cristae_per_mito.py
├── .gitignore
├── CODE_OF_CONDUCT.md
├── LICENSE
├── README.md
├── SECURITY.md
└── requirements-python.txt
```

Generated analytical outputs are written under `results/derived/` during local or GitHub Actions runs. They are uploaded as workflow artifacts and are not committed to the repository unless explicitly stated otherwise.

## Python environment

Python 3.12 is used for the documented preprocessing workflow.

### Linux and macOS

```bash
python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements-python.txt
```

### Windows PowerShell

```powershell
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements-python.txt
```

## Running the Python preprocessing workflow

Provide directories containing matching mitochondrial and cristae segmentation masks and a protected output directory:

```bash
python scripts/python/count_cristae_per_mito.py \
  --mito-dir <PATH_TO_MITOCHONDRIAL_MASKS> \
  --cristae-dir <PATH_TO_CRISTAE_MASKS> \
  --output-dir <PROTECTED_OUTPUT_DIRECTORY> \
  --run-id <RUN_IDENTIFIER> \
  --fail-on-unpaired
```

On Windows PowerShell, the same command can be written on one line:

```powershell
python scripts/python/count_cristae_per_mito.py --mito-dir <PATH_TO_MITOCHONDRIAL_MASKS> --cristae-dir <PATH_TO_CRISTAE_MASKS> --output-dir <PROTECTED_OUTPUT_DIRECTORY> --run-id <RUN_IDENTIFIER> --fail-on-unpaired
```

Display all supported options with:

```bash
python scripts/python/count_cristae_per_mito.py --help
```

Generated outputs should remain under a protected path until identifiers, filenames, local paths, and embedded metadata have passed the release audit.

## R analysis workflows

The R workflows should be run from the repository root.

### 1. Prepare the combined Prism input

```bash
Rscript scripts/R/prepare_prism_input.R
```

This workflow:

- reads the manual and automated curated workbooks;
- standardizes their analytical structure;
- combines the measurement methods;
- creates the shared Prism input table;
- records relevant validation information.

Primary generated file:

```text
results/derived/Prism_input.xlsx
```

### 2. Analyse total cristae counts

```bash
Rscript scripts/R/analyze-total-cristae.R
```

This workflow reads the combined Prism input and generates the total-cristae statistical analysis, model summaries, contrasts, diagnostics, and derived result tables.

### 3. Analyse between-subject heterogeneity

```bash
Rscript scripts/R/Heterogeneity_subjects.R
```

This workflow reads the combined Prism input and generates subject-level summaries used to evaluate heterogeneity across controls and patient groups for both measurement methods.

### 4. Run the cristae linear mixed-model analysis

```bash
Rscript scripts/R/Cristae_LMM.R
```

This workflow reads the manual and automated workbooks directly and processes them separately.

For each eligible metric, it fits:

```text
y ~ group + (1 | ID_cluster)
```

Planned contrasts compare Controls with patient groups P1-P10. The workflow exports:

- structured Excel workbooks;
- quality-control and conversion audits;
- descriptive statistics;
- model-estimated means;
- planned contrasts and multiple-testing corrections;
- significant-result and review-required tables;
- individual publication-style plots;
- summary heatmaps and contrast overviews;
- residual-versus-fitted and Q-Q diagnostic plots.

Primary output root:

```text
results/derived/cristae_lmm_safe/
```

## GitHub Actions

The repository contains five automated workflows:

| Workflow file | Purpose |
| --- | --- |
| `.github/workflows/python-tests.yml` | Runs the synthetic Python test suite. |
| `.github/workflows/r-prepare-prism.yml` | Runs Prism input preparation and verifies the generated workbook. |
| `.github/workflows/r-total-cristae.yml` | Runs the total-cristae analysis and verifies its outputs. |
| `.github/workflows/r-heterogeneity.yml` | Runs the subject-heterogeneity analysis and verifies its outputs. |
| `.github/workflows/r-cristae-lmm.yml` | Runs the manual and automated LMM analyses and verifies tables, plots, summaries, and diagnostics. |

At the time of this pre-release revision, all five workflows passed successfully.

The R workflows are integration checks that execute the complete repository analysis scripts against the curated repository inputs and verify that the expected outputs are created. They complement, but are not equivalent to, isolated unit tests.

## Local testing and validation

### Python synthetic tests

Run locally with:

```bash
python -m unittest discover -s tests/python -p "test_*.py" -v
```

The same suite runs automatically through GitHub Actions.

### R workflow validation

Run the four R scripts from the repository root in this order:

```bash
Rscript scripts/R/prepare_prism_input.R
Rscript scripts/R/analyze-total-cristae.R
Rscript scripts/R/Heterogeneity_subjects.R
Rscript scripts/R/Cristae_LMM.R
```

The first script creates the shared Prism input required by the total-cristae and heterogeneity workflows. The LMM workflow reads the two curated workbooks directly and does not depend on the Prism input.

For automated validation, use the corresponding GitHub Actions workflows and review their uploaded artifacts.

## Reproducibility status

| Component | Status |
| --- | --- |
| Python command-line adaptation | Complete |
| Python dependency record | Complete |
| Python synthetic test suite | Passed |
| Python GitHub Actions workflow | Passed |
| Curated manual workbook included | Complete |
| Curated automated workbook included | Complete |
| Prism input preparation workflow | Implemented and passed |
| Total-cristae analysis workflow | Implemented and passed |
| Subject-heterogeneity workflow | Implemented and passed |
| Cristae LMM workflow | Implemented and passed |
| Verification of expected R output files in GitHub Actions | Passed |
| Documentation of analysis order and input dependencies | Complete |
| Final comparison with the submitted manuscript tables and figures | Pending final publication audit |
| Formal versioned release | Pending |
| Zenodo archive and DOI | Pending |
| R dependency lock with `renv` | Not currently implemented |

The computational workflows contained in this repository are executable and covered by automated checks. Full end-to-end reproduction from raw microscopy images is outside the scope of this repository because raw images and upstream segmentation inputs are maintained separately.

## Data availability and confidentiality

The curated analytical workbooks are included in:

```text
data/curated/
```

The following materials are not distributed through this repository:

- raw microscopy images;
- upstream segmentation masks;
- confidential or unpublished figures;
- manuscript files;
- protected source metadata;
- workflow artifacts containing results that have not been approved for public release.

Generated outputs should be reviewed before publication for:

- subject and sample identifiers;
- filenames and local paths;
- embedded metadata;
- unpublished results;
- confidential or personal information;
- consistency with the associated research article.

## Citation

The associated research article is intended to be the preferred scientific citation once its bibliographic metadata are final.

The repository currently contains:

```text
metadata/CITATION.cff.template
```

A root-level `CITATION.cff` will be created only after the following metadata have been verified:

- final software title;
- author list and author order;
- ORCID identifiers;
- affiliations;
- release version;
- release date;
- repository URL;
- software license;
- article citation;
- article DOI;
- Zenodo version DOI and concept DOI, when available.

No DOI is currently claimed.

## License

The source code and original documentation in this repository are available under the [MIT License](LICENSE).

Copyright (c) 2026 Nikol Volfová  
Copyright (c) 2026 Martin Čapek

Research data, generated research tables, figures, microscopy files, segmentation outputs, and manuscript content are not automatically covered by the MIT License unless a separate license or explicit statement says otherwise.

## Security and responsible disclosure

Please follow the instructions in [SECURITY.md](SECURITY.md) when reporting a security issue or accidental exposure of confidential information.
