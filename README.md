# Mitochondrial Ultrastructure Analysis

Pre-release repository for computational workflows associated with the analysis of mitochondrial ultrastructure and cristae morphology.

> **Development status:** The repository is currently being reconstructed and validated against the original analysis files. The Python preprocessing component is included in the current version. The R analysis workflows and their input-data contracts will be added after validation.

## Current scope

The current repository version contains:

* Python preprocessing of automated segmentation outputs;
* synthetic tests for the Python workflow;
* an automated Python test workflow for GitHub Actions;
* project licensing, security, and citation templates.

The Python preprocessing script originates from work by Martin Čapek and has been adapted for portable command-line use with his knowledge and permission.

The manual-measurement workflow and the downstream R analyses are not yet included in this reconstructed repository version.

## Related project

The automated segmentation outputs processed by the Python workflow originate from the associated image-analysis project:

[Analysis of Mitochondrial Ultrastructure and Morphology](https://github.com/LMCF-IMG/Analysis_Mitochondrial_Ultrastructure_and_Morphology)

## Development and release status

This repository has not yet been formally released, archived, or assigned a DOI. Reproducibility claims will be updated only after the complete workflow has been validated.

## License

The source code and original documentation are available under the [MIT License](LICENSE).
