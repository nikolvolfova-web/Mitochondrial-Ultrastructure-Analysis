# Validation and Release-Readiness Record

This document records the validation and release-readiness status of the
Mitochondrial Ultrastructure Analysis repository.

Validation described here applies to the repository state prepared for public
release on 2026-08-10.

The repository is a downstream analysis and publication companion project.
It does not reproduce the complete workflow from raw microscopy images. Raw
images and the complete upstream segmentation dataset are maintained outside
this repository.

## Validation objectives

The validation was designed to confirm that:

1. repository analytical inputs have documented provenance;
2. the Python preprocessing implementation and all R analysis workflows execute
   successfully;
3. processed Python outputs are internally consistent;
4. the curated automated workbook is traceable to the Python outputs and
   documented visual curation;
5. generated analytical outputs are produced successfully from the repository
   inputs;
6. representative quality-control material accurately documents the curation
   procedure;
7. publicly distributed research-derived materials have been reviewed for
   release;
8. software, data licensing, citation metadata, and repository documentation
   are suitable for public distribution.

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

## 1. Python preprocessing validation

The synthetic Python test suite is located in:

```text
tests/python/
```

and is executed by:

```text
.github/workflows/python-tests.yml
```

The tests validate the documented command-line implementation using controlled
synthetic segmentation inputs.

The Python test suite passed during repository validation.

Status:

```text
PASSED
```

This test validates the repository implementation. It does not reproduce the
complete research workflow from raw microscopy images.

## 2. Internal consistency of processed Python outputs

The three included Python-generated CSV files were checked for internal
aggregation consistency.

The relationship tested was:

```text
all_cristae_instances.csv
        ↓
cristae_counts_per_mito.csv
        ↓
cristae_counts_image_summary.csv
```

The per-crista records aggregated consistently to the per-mitochondrion table,
and the per-mitochondrion table aggregated consistently to the image-level
summary.

The processed dataset contains 100 image-level records.

No aggregation discrepancy was identified.

The `class_13000` field is retained by the Python output schema but has no
observations in the included research dataset.

Status:

```text
PASSED
```

## 3. Curated workbook structural audit

The following workbooks were reviewed:

```text
data/curated/cristae_manual.xlsx
data/curated/cristae_automated.xlsx
```

The review included workbook structure, worksheets, hidden content, formulas,
comments, external workbook links, and metadata relevant to public release.

Both workbooks contain the expected control and patient-group worksheets.

No hidden worksheets, hidden rows, hidden columns, formulas, comments, or
external workbook links requiring remediation were identified during the
release audit.

The workbooks are successfully consumed by the downstream R workflows.

Status:

```text
PASSED
```

## 4. Automated workbook traceability

The curated automated workbook was compared with:

```text
data/processed/python/all_cristae_instances.csv
data/processed/python/cristae_counts_per_mito.csv
data/processed/python/cristae_counts_image_summary.csv
```

All 100 image blocks in the curated automated workbook could be matched to the
processed Python outputs.

For all 100 images, the image-level totals corresponding to `Label 2` through
`Label 12` were consistent with the Python-generated values.

Differences in the number of retained mitochondrial profiles between the raw
Python outputs and the curated automated workbook are expected where
mitochondrial segmentation artefacts were removed during documented visual
quality control.

The original Python CSV files remain unchanged. Curation is represented in the
curated automated workbook rather than by modification of the primary Python
outputs.

Status:

```text
PASSED
```

## 5. Mitochondrial numbering correction

During the release audit, eight rows in:

```text
data/curated/cristae_automated.xlsx
```

contained `1` instead of `10` in the `Number of mito` field within otherwise
ascending mitochondrial numbering sequences.

These identifiers were corrected before public release.

The correction does not change the number of mitochondrial observations or the
cristae measurements associated with those rows.

The downstream analysis code was reviewed for analytical dependence on this
field.

In `prepare_prism_input.R`, mitochondrial counts are determined from the number
of valid mitochondrial rows rather than from the numeric value of
`Number of mito`.

`Cristae_LMM.R` explicitly excludes `Number of mito` from the analysed
variables.

The agreement workflow likewise does not use the mitochondrial identifier as a
numeric denominator or analytical measurement.

Therefore, the numbering correction is a curated-data identifier correction
and does not alter the analytical results.

Status:

```text
CORRECTED — NO ANALYTICAL IMPACT
```

## 6. Representative mitochondrial-segmentation QC

The representative QC example is located in:

```text
docs/qc_examples/C2_002_30000x/
```

The example documents visual review of mitochondrial segmentation before
preparation of the curated automated dataset.

For image `C2_002_30000x`:

```text
mitochondrial label 1 → retained
mitochondrial label 2 → excluded as segmentation artefact
mitochondrial label 3 → excluded as segmentation artefact
mitochondrial label 4 → retained
```

The exclusion criterion was based on whether the segmentation corresponded to
a valid visible mitochondrial profile.

It was not based on the number of detected cristae.

Valid mitochondrial profiles with zero detected cristae remained eligible for
inclusion.

The QC directory contains derived segmentation and visualization files. The
original source image is intentionally not duplicated in this companion
repository.

The local `README.md` and `qc_manifest.csv` were updated during the final audit
to match the files actually distributed in the directory.

Status:

```text
PASSED
```

## 7. Prism input preparation

Workflow:

```text
.github/workflows/r-prepare-prism.yml
```

Script:

```text
scripts/R/prepare_prism_input.R
```

Inputs:

```text
data/curated/cristae_manual.xlsx
data/curated/cristae_automated.xlsx
```

Primary generated output:

```text
results/derived/Prism_input.xlsx
```

The workflow successfully generated and verified the expected output during the
final reproducibility run.

Status:

```text
PASSED
```

## 8. Total cristae-count analysis

Workflow:

```text
.github/workflows/r-total-cristae.yml
```

Script:

```text
scripts/R/analyze-total-cristae.R
```

The workflow executed successfully against the generated Prism input and
verified the expected analytical outputs.

Status:

```text
PASSED
```

## 9. Between-subject heterogeneity analysis

Workflow:

```text
.github/workflows/r-heterogeneity.yml
```

Script:

```text
scripts/R/Heterogeneity_subjects.R
```

The workflow executed successfully and verified its expected analytical
outputs.

Status:

```text
PASSED
```

## 10. Cristae linear mixed-model analysis

Workflow:

```text
.github/workflows/r-cristae-lmm.yml
```

Script:

```text
scripts/R/Cristae_LMM.R
```

The workflow analyses the manual and automated workbooks separately.

The implemented model is:

```text
y ~ group + (1 | ID_cluster)
```

The following workbook fields are excluded from the LMM outcome variables:

```text
Number of mito
ER connections
length of contact
average length of contact
```

The workflow dependency list explicitly includes the required `emmeans`
package.

The workflow successfully generated and verified the expected Excel results,
plots, summaries, and diagnostic outputs during the final reproducibility run.

Status:

```text
PASSED
```

## 11. Global cristae class-profile analysis

Workflow:

```text
.github/workflows/r-global-class-profile.yml
```

Script:

```text
scripts/R/Global_class_profile_across_cristae_labels.R
```

Primary outputs include:

```text
results/derived/global_class_profile/global_class_profile_data.xlsx
results/derived/global_class_profile/global_class_profile_dumbbell_colored.png
results/derived/global_class_profile/global_class_profile_dumbbell_colored.pdf
```

The workflow successfully generated and verified its expected table and figure
outputs during the final reproducibility run.

Status:

```text
PASSED
```

## 12. Manual-versus-automated agreement analysis

Workflow:

```text
.github/workflows/r-cristae-bland-altman.yml
```

Script:

```text
scripts/R/cristae_Bland_Altman.R
```

Primary output root:

```text
results/derived/cristae_bland_altman/
```

The workflow verifies the statistical workbook, analysis summary, R session
information, Bland-Altman figures, scatter figures, and combined figure panels.

The difference is defined as:

```text
automated - manual
```

Pearson correlation is reported separately from agreement.

The workflow successfully generated and verified its expected outputs during
the final reproducibility run.

Status:

```text
PASSED
```

## 13. Final reproducibility run

Immediately before public-release preparation, all seven GitHub Actions
workflows were executed against the current repository state.

The final run covered:

```text
python-tests.yml
r-prepare-prism.yml
r-total-cristae.yml
r-heterogeneity.yml
r-cristae-lmm.yml
r-global-class-profile.yml
r-cristae-bland-altman.yml
```

All workflows completed successfully.

Generated workflow artifacts from the final R analyses were downloaded and
retained as release-validation records.

Status:

```text
7 / 7 WORKFLOWS PASSED
```

## 14. Software environment and dependencies

### Python

The Python dependency record is provided in:

```text
requirements-python.txt
```

The documented workflow uses Python 3.12.

Synthetic tests pass in the GitHub Actions environment.

### R

Required R packages are installed explicitly by the individual GitHub Actions
workflows.

The LMM workflow includes all packages required by the current script,
including:

```text
emmeans
```

The repository does not currently provide a verified `renv.lock`.

This limitation is documented rather than concealed.

Session/environment information is retained by analytical outputs where
implemented, including the Bland-Altman `R_session_info.txt` output.

A formal claim of a fully locked R package environment is therefore not made.

## 15. Public-release and confidentiality review

The research-derived files currently distributed in this repository have been
reviewed and approved for public release.

The approval applies to the materials actually included in the repository.

The repository does not distribute the complete raw microscopy dataset,
complete upstream segmentation dataset, complete patient-level QC material, or
a lookup table connecting pseudonymous identifiers to real persons.

The representative QC example is derived from a control image.

The release audit also reviewed the repository for accidental disclosure of
local paths, credentials, obvious secrets, or protected material.

No Blocking confidentiality issue was identified in the release candidate.

Status:

```text
APPROVED FOR INCLUDED MATERIALS
```

## 16. Licensing

Software, scripts, workflows, tests, and original software documentation are
distributed under:

```text
MIT
```

as specified in:

```text
LICENSE
```

Research-derived data and QC materials distributed under:

```text
data/curated/
data/processed/python/
docs/qc_examples/
```

are distributed under:

```text
Creative Commons Attribution 4.0 International
CC BY 4.0
```

as specified in:

```text
LICENSE-DATA.md
```

Materials maintained outside this repository are not relicensed by
`LICENSE-DATA.md`.

Status:

```text
DOCUMENTED
```

## 17. Citation metadata

Repository citation metadata are provided in:

```text
CITATION.cff
```

The file contains the verified author names and ORCID identifiers currently
available for the repository.

The repository DOI, release version, release date, and final bibliographic
metadata of the associated article are not yet included because they have not
yet been formally established for this release.

They must be added only after verification.

Status:

```text
CURRENT PRE-RELEASE METADATA COMPLETE
```

## 18. Documentation consistency

The final release audit includes consistency checks across:

```text
README.md
scripts/README.md
data/README.md
docs/DATA_PROVENANCE.md
docs/VALIDATION_PLAN.md
docs/qc_examples/C2_002_30000x/README.md
docs/qc_examples/C2_002_30000x/qc_manifest.csv
CITATION.cff
LICENSE
LICENSE-DATA.md
CONTRIBUTING.md
CODE_OF_CONDUCT.md
SECURITY.md
```

The public-release documentation distinguishes:

```text
upstream image-analysis project
        ↓
processed segmentation outputs
        ↓
this downstream publication companion repository
        ↓
curated analyses and publication outputs
```

The repository documentation also distinguishes the MIT software license from
the CC BY 4.0 data and QC license.

GitHub Release and Zenodo metadata do not yet exist and therefore remain outside
the completed pre-release documentation audit.

## Discrepancy classification

Validation findings are classified as:

- **Blocking** — prevents reliable validation or public release.
- **High priority** — affects analytical correctness or reported results.
- **Medium priority** — affects reproducibility or essential documentation.
- **Low priority** — affects clarity or maintainability.
- **Optional** — improvement without an effect on analytical correctness.

No unresolved Blocking or High-priority analytical discrepancy was identified
during the final repository validation.

## Release criteria

The repository is considered ready to proceed to public-release preparation
when:

- the curated analytical inputs are documented;
- Python processed outputs have passed internal-consistency checks;
- the automated workbook has been traced to the Python outputs and documented
  curation procedure;
- the representative QC example accurately documents the segmentation QC;
- all seven GitHub Actions workflows pass against the release candidate;
- expected analytical outputs are generated successfully;
- public-release approval applies to the research-derived files included in the
  repository;
- software and data licensing are documented;
- citation metadata contain only verified information;
- no unresolved Blocking or High-priority validation finding remains.

These criteria have been met for the current release candidate.

Formal versioning and archival metadata are handled after public release.

## Current validation status

| Validation item | Status |
| --- | --- |
| Python preprocessing script | Included |
| Python dependency record | Included |
| Synthetic Python tests | Passed |
| Python GitHub Actions workflow | Passed |
| Processed Python CSV internal consistency | Passed |
| Curated manual workbook | Reviewed and included |
| Curated automated workbook | Reviewed and included |
| Mitochondrial numbering correction | Completed; no analytical impact |
| Python CSV-to-workbook traceability | Passed |
| Representative QC example | Passed |
| QC manifest | Corrected and verified |
| Prism input preparation workflow | Passed |
| Total cristae-count workflow | Passed |
| Subject-heterogeneity workflow | Passed |
| Cristae LMM workflow | Passed |
| Global class-profile workflow | Passed |
| Bland-Altman workflow | Passed |
| Final reproducibility run | 7/7 workflows passed |
| Final R workflow artifacts | Generated and retained |
| Public release approval for included data | Approved |
| Software license | MIT |
| Data and QC license | CC BY 4.0 |
| Root-level `CITATION.cff` | Included |
| Verified author ORCID metadata | Included |
| Verified `renv.lock` | Not implemented |
| Formal version number | Pending formal release |
| Release date | Pending formal release |
| GitHub Release | Pending |
| Zenodo archive | Pending |
| Zenodo DOI | Pending |
| Associated article DOI | Pending verified bibliographic metadata |

## Final pre-publication step

Before changing repository visibility from private to public, perform one final
repository-level audit for:

```text
Pending
pre-release
TODO
FIXME
<<<<<<<
=======
>>>>>>>
```

and verify that:

```text
all internal Markdown links resolve
all seven Actions workflows are green
the repository root displays the expected README
LICENSE and LICENSE-DATA.md are both present
CITATION.cff parses correctly
no confidential file has been added since the validation run
```

If that final repository-level check is clean, the repository may proceed to
public visibility.

After public release, the next steps are:

```text
create the formal version tag
create the corresponding GitHub Release
archive the release through Zenodo
obtain and verify the Zenodo DOI
update README.md and CITATION.cff with verified release metadata
```
