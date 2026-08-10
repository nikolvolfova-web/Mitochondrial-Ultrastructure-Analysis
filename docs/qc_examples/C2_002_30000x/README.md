# Representative QC example: C2_002_30000x

This directory contains a representative set of image-analysis outputs from
a non-patient control image.

The example illustrates the role of mitochondrial segmentation in the
automated cristae-quantification workflow. Mitochondrial segmentation was used
to define compartments for cristae assignment and was not treated as an
independent analytical endpoint.

## Included outputs

The directory contains representative derived outputs generated or used during
the automated workflow, including:

* the mitochondrial segmentation mask;
* the mitochondrial object-ID visualization;
* the cristae overlay;
* an additional workflow output associated with the same image.

The source image is not duplicated in this QC example. Source-data provenance
and the upstream image-analysis workflow are associated with the
`Analysis_Mitochondrial_Ultrastructure_and_Morphology` project.

## Quality-control decision

The raw computational output for image `C2_002_30000x` contained mitochondrial
labels 1, 2, 3, and 4.

Visual inspection confirmed that labels 1 and 4 corresponded to real
mitochondrial profiles. Labels 2 and 3 did not correspond to valid visible
mitochondrial objects and were therefore classified as mitochondrial
segmentation artefacts.

Accordingly:

* labels 1 and 4 were retained in the curated analytical dataset;
* labels 2 and 3 were excluded as confirmed segmentation artefacts.

The exclusion criterion was not based on the number of detected cristae.
Valid mitochondrial profiles with zero detected cristae remained included.

The original computational outputs were retained unchanged. The exclusion was
applied only when preparing the curated analytical dataset used for downstream
cristae analyses.

## Data protection

This example originates from a control image and is provided only as a
representative illustration of the workflow and its quality-control procedure.

Patient-level source images and complete patient-level QC materials are not
included in the public repository because they belong to a protected research
dataset.

This example does not constitute a complete biological or technical validation
of the segmentation method.
