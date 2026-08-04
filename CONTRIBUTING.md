# Contributing

Thank you for your interest in improving the Mitochondrial Ultrastructure
Analysis repository.

This project contains research-oriented Python and R workflows, curated
analytical inputs, automated validation, and publication-related documentation.
Contributions should preserve reproducibility, confidentiality, and traceable
analytical logic.

## Before contributing

Please open an issue before making a substantial change, especially when the
proposal affects:

- statistical models or contrasts;
- data-cleaning rules;
- inclusion or exclusion criteria;
- input workbook structure;
- output file names or locations;
- command-line interfaces;
- dependency versions;
- GitHub Actions workflows;
- citation, authorship, or licensing metadata.

Small documentation corrections and clearly isolated bug fixes may be submitted
directly as pull requests.

## Types of contributions

Appropriate contributions include:

- documentation corrections;
- reproducibility improvements;
- additional validation checks;
- synthetic tests;
- workflow maintenance;
- portability fixes;
- clearer error messages;
- dependency documentation;
- issue templates;
- release and citation metadata updates.

Changes to the scientific analysis must be clearly justified and must not be
presented as equivalent to the validated workflow unless the results have been
independently reviewed.

## Repository layout

```text
scripts/R/        R analysis workflows
scripts/python/   Python preprocessing workflow
tests/python/     Synthetic Python tests
data/curated/     Curated analytical input workbooks
.github/workflows/ Automated validation workflows
results/derived/  Generated outputs; not committed by default
```

## Development workflow

1. Create a branch from the latest `main`.
2. Use a short descriptive branch name, for example:

   ```text
   docs/update-readme
   fix/python-input-validation
   ci/update-r-workflow
   ```

3. Keep each pull request focused on one coherent change.
4. Use clear commit messages written in the imperative style, for example:

   ```text
   docs: clarify LMM input requirements
   fix: preserve image identifiers during preprocessing
   test: add unpaired-mask regression case
   ci: verify generated Excel outputs
   ```

5. Open a pull request and describe:
   - what changed;
   - why it changed;
   - which files were modified;
   - how the result was validated;
   - whether outputs or scientific conclusions changed.

## Python changes

Python code is located in:

```text
scripts/python/
```

Install the documented environment:

```bash
python -m pip install -r requirements-python.txt
```

Run the synthetic test suite:

```bash
python -m unittest discover -s tests/python -p "test_*.py" -v
```

Python pull requests should pass:

```text
.github/workflows/python-tests.yml
```

## R changes

R scripts are located in:

```text
scripts/R/
```

Run workflows from the repository root.

Recommended order:

```bash
Rscript scripts/R/prepare_prism_input.R
Rscript scripts/R/analyze-total-cristae.R
Rscript scripts/R/Heterogeneity_subjects.R
Rscript scripts/R/Cristae_LMM.R
```

The corresponding GitHub Actions workflows are:

```text
.github/workflows/r-prepare-prism.yml
.github/workflows/r-total-cristae.yml
.github/workflows/r-heterogeneity.yml
.github/workflows/r-cristae-lmm.yml
```

A change to an R script should include validation of the workflow that uses it.
Changes affecting shared inputs or output paths may require running more than
one workflow.

## Scientific-analysis changes

Do not change statistical logic silently.

A pull request that modifies an analysis must document:

- the original model or calculation;
- the proposed model or calculation;
- the reason for the change;
- affected inputs and outputs;
- expected effect on results;
- validation against previous outputs, when available;
- any new assumptions or limitations.

Changes that alter numerical results should be reviewed separately from purely
documentary or structural changes.

## Data and confidentiality

Never commit:

- passwords, access tokens, API keys, or credentials;
- private SSH keys;
- personal or subject identifiers;
- confidential metadata;
- protected local filesystem paths;
- raw microscopy images unless release has been explicitly approved;
- unpublished manuscript files;
- unapproved analytical outputs;
- temporary workflow artifacts.

Curated analytical inputs belong under:

```text
data/curated/
```

Generated outputs belong under:

```text
results/derived/
```

Generated outputs are uploaded as GitHub Actions artifacts and are not committed
by default.

If a secret or confidential file is committed accidentally:

1. revoke or replace the exposed credential immediately;
2. remove the file from the repository;
3. clean the Git history when necessary;
4. document the incident privately;
5. follow the reporting instructions in `SECURITY.md`.

## Documentation

Documentation should:

- use the actual repository paths and file names;
- distinguish validated workflows from planned work;
- avoid claiming unavailable test results or DOI values;
- identify unknown values with `TODO` or explicit placeholders;
- remain consistent with `README.md`, `scripts/README.md`, `CITATION.cff`,
  release notes, and Zenodo metadata.

## Pull-request checklist

Before requesting review, confirm that:

- [ ] the change is limited to the intended files;
- [ ] no confidential data or credentials are included;
- [ ] file paths and commands are correct;
- [ ] affected tests or workflows pass;
- [ ] generated outputs are not committed unintentionally;
- [ ] documentation has been updated where necessary;
- [ ] analytical changes are explicitly described;
- [ ] citation and licensing information remains consistent.

## Code of conduct

All contributors must follow the project
[Code of Conduct](CODE_OF_CONDUCT.md).

## License

By contributing to this repository, you agree that your contribution may be
distributed under the repository's [MIT License](LICENSE), unless a different
written agreement is made before the contribution is accepted.
