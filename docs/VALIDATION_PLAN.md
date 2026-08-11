# Validation and Release-Readiness Record

This document records validation, reproducibility, and release-readiness
information for the **Mitochondrial Ultrastructure Analysis** repository.

The record distinguishes two repository states:

1. **Archived release `v1.0.0`** — publicly released and archived in Zenodo on
   2026-08-10.
2. **Current development extension** — adds subject-level predictive validation
   and a log-transformed predictive sensitivity analysis and is being prepared
   for a subsequent versioned release.

The repository is a downstream analysis and publication companion project. It
does not reproduce the complete workflow from raw microscopy images. Raw
microscopy images and the complete upstream segmentation dataset are maintained
outside this repository.

## Release identifiers

Archived release:

```text
Version: 1.0.0
Release date: 2026-08-10
Version DOI: 10.5281/zenodo.21872764
Concept DOI: 10.5281/zenodo.21872763
```

The archived `v1.0.0` release remains unchanged. Current development changes are
implemented separately and are not retroactively attributed to `v1.0.0`.

---

## Validation objectives

Validation is designed to confirm that:

1. repository analytical inputs have documented provenance;
2. the Python preprocessing implementation and R analysis workflows execute
   successfully;
3. processed Python outputs are internally consistent;
4. the curated automated workbook is traceable to Python outputs and documented
   visual curation;
5. generated analytical outputs are reproducibly produced from repository
   inputs;
6. representative quality-control material accurately documents the curation
   procedure;
7. predictive analyses preserve the biological subject hierarchy and avoid
   subject-level data leakage;
8. model convergence, singularity, pairing, and key input assumptions are
   explicitly checked where relevant;
9. generated research outputs used for validation are retained as workflow
   artifacts or local validation records;
10. public research-derived materials have been reviewed for release;
11. software, data licensing, citation metadata, and repository documentation
    are suitable for public distribution;
12. a new versioned release is created only after the complete release candidate
    passes the required reproducibility checks.

---

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
scripts/R/cristae_prediction_validation.R
scripts/R/cristae_log_sensitivity_analysis.R
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
.github/workflows/r-cristae-prediction-validation.yml
.github/workflows/r-cristae-log-sensitivity.yml
```

The first seven workflows formed the automated validation set for `v1.0.0`.
The final two workflows were added during the current predictive-development
extension.

---

# Part I — Validation inherited from archived v1.0.0

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

The Python test suite passed during `v1.0.0` repository validation.

Status:

```text
PASSED
```

This test validates the repository implementation. It does not reproduce the
complete research workflow from raw microscopy images.

---

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

---

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

---

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

---

## 5. Mitochondrial numbering correction

During the `v1.0.0` release audit, eight rows in:

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

Therefore, the numbering correction was a curated-data identifier correction
and did not alter the analytical results.

Status:

```text
CORRECTED — NO ANALYTICAL IMPACT
```

---

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

The exclusion criterion was based on whether the segmentation corresponded to a
valid visible mitochondrial profile.

It was not based on the number of detected cristae.

Valid mitochondrial profiles with zero detected cristae remained eligible for
inclusion.

The QC directory contains derived segmentation and visualization files. The
original source image is intentionally not duplicated in this companion
repository.

Status:

```text
PASSED
```

---

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

The generated workbook contains the paired image-level `compare_images`
worksheet used by several downstream analyses.

The workflow successfully generated and verified the expected output during the
`v1.0.0` reproducibility run.

Status:

```text
PASSED
```

---

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

---

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

---

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
plots, summaries, and diagnostic outputs during the `v1.0.0` reproducibility
run.

Status:

```text
PASSED
```

---

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
outputs during the `v1.0.0` reproducibility run.

Status:

```text
PASSED
```

---

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
the `v1.0.0` reproducibility run.

Status:

```text
PASSED
```

---

## 13. v1.0.0 final reproducibility run

Immediately before `v1.0.0` public-release preparation, all seven workflows
included in that release were executed against the release-candidate state.

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

The repository was subsequently released publicly as `v1.0.0` and archived in
Zenodo.

---

# Part II — Current predictive-development validation

## 14. Predictive validation scope

The current development extension adds a new analytical question:

> Can automated cristae quantification predict the corresponding manual
> reference measurement in a previously unseen biological subject?

The predictive analyses are intentionally separated from the existing
inferential Ctrl-vs-HD analyses.

Disease status is retained only as metadata for plotting and descriptive
summaries and is not used as a predictor.

The shared input is generated by:

```text
scripts/R/prepare_prism_input.R
        ↓
results/derived/Prism_input.xlsx
        ↓
worksheet: compare_images
```

This design avoids reimplementing independent manual/automated workbook
pairing and image-level aggregation in each predictive script.

---

## 15. Primary subject-level predictive validation

Workflow:

```text
.github/workflows/r-cristae-prediction-validation.yml
```

Script:

```text
scripts/R/cristae_prediction_validation.R
```

Input:

```text
results/derived/Prism_input.xlsx
worksheet: compare_images
```

### Primary endpoint

```text
manual_mean_per_mito ~ auto_mean_per_mito
```

### Secondary endpoint

```text
manual_total ~ auto_total
```

### Model

```text
Manual_ij = beta_0 + beta_1 × Automated_ij + u_i + epsilon_ij
```

where `u_i` is a subject-specific random intercept.

### Validation design

Predictive performance is evaluated using leave-one-subject-out
cross-validation (LOSO-CV).

For every fold:

1. all images from one biological subject are held out;
2. the model is fitted using only the remaining subjects;
3. the held-out subject is predicted with fixed effects only;
4. no random effect estimated from a training subject is transferred to the
   held-out subject.

The critical prediction call uses:

```text
re.form = NA
```

This preserves the subject-level separation required for evaluation in unseen
biological subjects.

### Prediction benchmarks

The calibrated mixed-effects model is compared with:

```text
automated_identity
training_subject_mean
```

Definitions:

```text
automated_identity:
predicted Manual = observed Automated

training_subject_mean:
equal-weight mean of subject-specific Manual means among training subjects
```

### Performance metrics

The workflow reports:

```text
MAE
RMSE
bias_pred_minus_obs
R2_CV_pooled
subject_balanced_MAE
subject_balanced_RMSE
calibration_intercept
calibration_slope
Q2_vs_automated_identity
Q2_vs_training_subject_mean
```

### Uncertainty

Subject-cluster bootstrap 95% confidence intervals are calculated from already
generated LOSO out-of-sample predictions.

Entire biological subjects are resampled, preserving the within-subject image
structure.

The bootstrap quantifies uncertainty in predictive performance across the
evaluated biological subjects. It does not refit the complete LOSO training
procedure inside each bootstrap replicate.

### Model-status checks

The workflow records:

```text
singular_fit
convergence_ok
optimizer_code
convergence_message
```

for LOSO folds and the descriptive full-data calibration models.

Additional safeguards include checks for:

- required input columns;
- duplicate image keys;
- expected group labels;
- expected control image identifiers;
- minimum numbers of subjects;
- predictor variability in training folds;
- paired endpoint availability;
- mitochondrial-count consistency.

### Generated output root

```text
results/derived/cristae_prediction_validation/
```

### Development validation result

The GitHub Actions workflow successfully:

1. regenerated `Prism_input.xlsx` from the curated workbooks;
2. ran the complete LOSO predictive analysis;
3. generated predictive metrics, Q2 comparisons, bootstrap confidence
   intervals, figures, model diagnostics, and session information;
4. verified required output files;
5. uploaded the generated outputs as a GitHub Actions artifact.

The workflow artifact was downloaded and reviewed.

No unresolved Blocking or High-priority implementation issue remained after the
successful run.

Status:

```text
PASSED — CURRENT DEVELOPMENT
```

---

## 16. Log-transformed predictive sensitivity analysis

Workflow:

```text
.github/workflows/r-cristae-log-sensitivity.yml
```

Script:

```text
scripts/R/cristae_log_sensitivity_analysis.R
```

Input:

```text
results/derived/Prism_input.xlsx
worksheet: compare_images
```

### Purpose

This workflow is a sensitivity analysis for the primary predictive model.

It tests whether the primary predictive conclusion remains similar when the
calibration relationship is fitted on the `log1p` scale.

It does not replace the original-scale primary predictive analysis.

### Model

```text
log1p(Manual_ij) =
    beta_0 + beta_1 × log1p(Automated_ij) + u_i + epsilon_ij
```

The same LOSO subject-level validation structure is retained.

Held-out subjects are predicted using fixed effects only.

### Duan smearing retransformation

Predictions are returned to the original measurement scale using a
fold-specific Duan smearing correction.

The smearing factor is estimated only from the training data in the current
fold.

The main back-transformed prediction is:

```text
predicted Manual =
    exp(predicted log1p value) × smearing factor - 1
```

This prevents held-out subject information from entering the retransformation
correction.

### Endpoints, benchmarks, and metrics

The workflow uses the same:

- primary and secondary endpoints;
- `automated_identity` benchmark;
- `training_subject_mean` benchmark;
- MAE and RMSE metrics;
- subject-balanced metrics;
- pooled cross-validated R2;
- calibration metrics;
- pairwise predictive Q2 comparisons;
- subject-cluster bootstrap framework

as the primary predictive validation.

### Additional safeguards

The sensitivity workflow validates:

- repository-relative input paths;
- expected group and image identifiers;
- duplicate image keys;
- non-negative values required by the intended `log1p` analysis;
- minimum subject and observation counts;
- training-fold predictor variability;
- model convergence;
- model singularity;
- validity of the Duan smearing factor;
- occurrence of negative back-transformed predictions.

Negative back-transformed predictions are flagged rather than silently
truncated.

### Generated output root

```text
results/derived/log_sensitivity_prediction/
```

### Development validation result

The GitHub Actions workflow successfully:

1. regenerated `Prism_input.xlsx`;
2. ran the full log-transformed LOSO analysis;
3. calculated Duan-corrected out-of-sample predictions;
4. generated predictive metrics, Q2 values, bootstrap confidence intervals,
   figures, diagnostics, and session information;
5. verified required output files;
6. uploaded the results as a GitHub Actions artifact.

The workflow artifact was downloaded and reviewed.

The final workflow run also included explicit bootstrap audit metadata for the
Q2 bootstrap output.

No unresolved Blocking or High-priority implementation issue remained after the
successful run.

Status:

```text
PASSED — CURRENT DEVELOPMENT
```

---

## 17. Predictive robustness review

The primary original-scale predictive model and the log-transformed sensitivity
model were reviewed together after successful GitHub Actions runs.

The review assessed:

- primary-endpoint out-of-sample error;
- pooled cross-validated R2;
- subject-balanced error metrics;
- calibration intercept and slope;
- pairwise predictive Q2 against both benchmark strategies;
- subject-cluster bootstrap uncertainty;
- LOSO model convergence and singularity;
- full-model diagnostics;
- sensitivity to log transformation and Duan retransformation.

The sensitivity analysis produced a closely similar predictive conclusion for
the primary endpoint and supported robustness of the original-scale predictive
analysis.

The sensitivity analysis is therefore retained as a robustness analysis rather
than substituted for the prespecified primary predictive model.

Detailed numerical results remain in the generated workflow artifacts and
associated research outputs rather than being duplicated as fixed values in
this validation record.

Status:

```text
ROBUSTNESS REVIEW COMPLETED
```

---

# Part III — Environment, release governance, and metadata

## 18. Software environment and dependencies

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

The repository does not currently provide a verified `renv.lock`.

This limitation is documented rather than concealed.

Session/environment information is retained by analytical outputs where
implemented, including the predictive-validation, sensitivity-analysis, and
Bland-Altman session-information records.

A formal claim of a fully locked R package environment is therefore not made.

Status:

```text
DOCUMENTED — NO VERIFIED renv.lock
```

---

## 19. Public-release and confidentiality review

The research-derived files distributed in the archived `v1.0.0` release were
reviewed and approved for public release.

The approval applies to the materials actually included in the repository.

The repository does not distribute:

- the complete raw microscopy dataset;
- the complete upstream segmentation dataset;
- complete patient-level QC material;
- a lookup table connecting pseudonymous identifiers to real persons.

The representative QC example is derived from a control image.

Repository review includes checks for accidental disclosure of:

```text
credentials
access tokens
private SSH keys
local protected paths
confidential files
direct personal identifiers
```

No Blocking confidentiality issue was identified for the archived release.

Any newly added research-derived file must undergo equivalent review before a
subsequent versioned release.

Status:

```text
APPROVED FOR CURRENTLY INCLUDED PUBLIC MATERIALS
```

---

## 20. Licensing

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

---

## 21. Citation and archival metadata

Repository citation metadata are provided in:

```text
CITATION.cff
```

For the archived release, the verified metadata include:

```text
title: Mitochondrial Ultrastructure Analysis
version: 1.0.0
date-released: 2026-08-10
doi: 10.5281/zenodo.21872764
license: MIT
```

The repository is archived in Zenodo.

Identifiers:

```text
v1.0.0 version DOI: 10.5281/zenodo.21872764
concept DOI:         10.5281/zenodo.21872763
```

The version DOI identifies the archived `v1.0.0` release.

The concept DOI identifies the project record across versions.

A subsequent release must receive its own verified version DOI before that DOI
is added to release-specific documentation.

The associated article DOI must be added only after its bibliographic metadata
are verified.

Status:

```text
v1.0.0 ARCHIVAL METADATA VERIFIED
NEXT RELEASE METADATA NOT YET CREATED
```

---

## 22. Documentation consistency

The documentation set includes:

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

The documentation distinguishes:

```text
upstream image-analysis project
        ↓
processed segmentation outputs
        ↓
this downstream publication companion repository
        ↓
curated analyses and publication outputs
```

The documentation also distinguishes:

```text
archived v1.0.0
        ↓
current development extension
        ↓
future versioned release after validation
```

and:

```text
primary original-scale predictive validation
        ↓
log-transformed sensitivity analysis
```

The sensitivity analysis must not be documented as replacing the primary
predictive analysis.

---

## 23. Discrepancy classification

Validation findings are classified as:

- **Blocking** — prevents reliable validation or public release.
- **High priority** — affects analytical correctness or reported results.
- **Medium priority** — affects reproducibility or essential documentation.
- **Low priority** — affects clarity, auditability, or maintainability.
- **Optional** — improvement without an effect on analytical correctness.

During development of the predictive workflows, detected implementation issues
were corrected before acceptance, including:

- figure-export argument handling in the primary predictive script;
- strict group-label validation;
- explicit convergence reporting;
- removal of interactive file selection from the sensitivity workflow;
- fold-level sensitivity-analysis safeguards;
- explicit Q2 bootstrap audit metadata.

The corrected workflows subsequently passed GitHub Actions.

Current unresolved status:

```text
Blocking:     none identified
High priority: none identified
```

A full release-candidate audit is still required before the next versioned
release.

---

## 24. Current validation status

| Validation item | Status |
| --- | --- |
| Python preprocessing script | Included |
| Python dependency record | Included |
| Synthetic Python tests | Passed |
| Python GitHub Actions workflow | Passed for v1.0.0 |
| Processed Python CSV internal consistency | Passed |
| Curated manual workbook | Reviewed and included |
| Curated automated workbook | Reviewed and included |
| Mitochondrial numbering correction | Completed; no analytical impact |
| Python CSV-to-workbook traceability | Passed |
| Representative QC example | Passed |
| Prism input preparation workflow | Passed for v1.0.0 |
| Total cristae-count workflow | Passed for v1.0.0 |
| Subject-heterogeneity workflow | Passed for v1.0.0 |
| Cristae LMM workflow | Passed for v1.0.0 |
| Global class-profile workflow | Passed for v1.0.0 |
| Bland-Altman workflow | Passed for v1.0.0 |
| v1.0.0 final reproducibility run | 7/7 workflows passed |
| v1.0.0 GitHub Release | Completed |
| v1.0.0 Zenodo archive | Completed |
| v1.0.0 version DOI | 10.5281/zenodo.21872764 |
| Concept DOI | 10.5281/zenodo.21872763 |
| Predictive validation script | Implemented |
| Predictive validation GitHub Actions workflow | Passed in current development |
| Predictive-validation artifact | Generated, downloaded, and reviewed |
| Log-sensitivity script | Implemented |
| Log-sensitivity GitHub Actions workflow | Passed in current development |
| Log-sensitivity artifact | Generated, downloaded, and reviewed |
| Predictive robustness review | Completed |
| Software license | MIT |
| Data and QC license | CC BY 4.0 |
| Root-level `CITATION.cff` | Included |
| v1.0.0 citation metadata | Verified |
| Verified `renv.lock` | Not implemented |
| Next release version | Not yet created |
| Next Git tag | Not yet created |
| Next GitHub Release | Not yet created |
| Next Zenodo version DOI | Not yet created |
| Associated article DOI | Pending verified bibliographic metadata |

---

# Part IV — Criteria for the next versioned release

## 25. Release criteria

The current development extension may proceed to a new versioned release when:

- predictive and sensitivity scripts are merged into the release candidate;
- documentation accurately describes all eight R workflows;
- all nine GitHub Actions workflows pass against the same release-candidate
  commit;
- expected analytical outputs are generated successfully;
- predictive and sensitivity artifacts have been reviewed;
- no unresolved Blocking or High-priority analytical finding remains;
- no confidential or unapproved research-derived file has been added;
- internal Markdown links resolve;
- software and data licensing remain correct;
- `CITATION.cff` is updated only when the new release version and release date
  are actually known;
- GitHub Release metadata and Zenodo metadata are mutually consistent;
- the new Zenodo version DOI is verified before being written back into
  release-specific documentation.

The current development state has passed both new predictive workflows, but the
**complete nine-workflow release-candidate run has not yet been recorded in
this document**.

Therefore:

```text
CURRENT DEVELOPMENT: ANALYTICALLY VALIDATED
NEXT VERSIONED RELEASE: NOT YET FINALIZED
```

---

## 26. Final release-candidate reproducibility run

Immediately before the next release, run all nine workflows against the same
release-candidate commit:

```text
python-tests.yml
r-prepare-prism.yml
r-total-cristae.yml
r-heterogeneity.yml
r-cristae-lmm.yml
r-global-class-profile.yml
r-cristae-bland-altman.yml
r-cristae-prediction-validation.yml
r-cristae-log-sensitivity.yml
```

Required release-candidate status:

```text
9 / 9 WORKFLOWS PASSED
```

Generated artifacts from relevant R workflows should be downloaded or otherwise
retained long enough to permit final validation review.

Do not update this record to `9 / 9 WORKFLOWS PASSED` until that complete run
has actually been performed against the final release-candidate state.

---

## 27. Final repository audit before release

Before creating the next version tag, search the release candidate for:

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
all nine Actions workflows are green
the repository root displays the expected README
scripts/README.md matches the implemented scripts
docs/VALIDATION_PLAN.md matches the release candidate
LICENSE and LICENSE-DATA.md are present
CITATION.cff parses correctly
no secret or credential is present
no confidential file has been added
no generated analytical artifact is accidentally committed unless approved
```

Any newly distributed research-derived file must be reviewed for public-release
eligibility before release.

---

## 28. Versioning and Zenodo sequence

After the release candidate passes the complete validation:

```text
merge validated development into main
        ↓
verify main
        ↓
create new semantic-version tag
        ↓
create corresponding GitHub Release
        ↓
Zenodo archives the new GitHub Release
        ↓
verify new version DOI
        ↓
verify concept DOI remains associated with the project
        ↓
update README.md / CITATION.cff only with verified release metadata
```

The archived `v1.0.0` release and its DOI remain immutable historical records.

The next version number must be chosen according to the actual scope of the
released changes and must not be written into archival metadata before the
release is created.

---

## 29. Next recommended validation step

The next repository-level validation step is:

```text
1. complete documentation updates on feature/cristae-prediction
2. review the branch diff
3. merge only after the documentation and code are clean
4. run all nine workflows against the final release-candidate commit
5. record the 9/9 result here
6. perform the final repository audit
7. create the next versioned GitHub Release
8. archive the release through Zenodo
9. verify and propagate the new version DOI
```

Until the complete nine-workflow release-candidate run is performed, the
predictive extension should be treated as validated development rather than a
completed new release.
