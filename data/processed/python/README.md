# Processed Python Outputs

This directory contains processed tabular outputs from the Python preprocessing
branch of the mitochondrial ultrastructure analysis.

These CSV files are retained as primary computational reference outputs. They
are distinct from the curated automated workbook used by the downstream R
analyses.

## Directory contents

```text
data/processed/python/
├── all_cristae_instances.csv
├── cristae_counts_image_summary.csv
├── cristae_counts_per_mito.csv
└── README.md
```

## Data flow

```text
Upstream mitochondrial and cristae segmentation masks
    → scripts/python/count_cristae_per_mito.py
    → processed Python CSV outputs
    → manual transfer of relevant values
    → visual review of mitochondrial segmentation objects
    → data/curated/cristae_automated.xlsx
```

The curated automated workbook is not a direct output of the Python script.

The Python CSV files remain unchanged as computational reference outputs, while
the automated workbook represents the curated analytical input used by the R
workflows.

## File format

The CSV files in this directory:

- use UTF-8 text encoding;
- use semicolons as field separators;
- contain a header row;
- use image and mitochondrial-object identifiers rather than direct personal
  identifiers.

When importing the files, the semicolon separator must be specified explicitly.

Example in Python:

```python
import pandas as pd

data = pd.read_csv(
    "data/processed/python/cristae_counts_per_mito.csv",
    sep=";"
)
```

Example in R:

```r
data <- read.csv2(
  "data/processed/python/cristae_counts_per_mito.csv",
  stringsAsFactors = FALSE
)
```

## `all_cristae_instances.csv`

This file contains one row for each detected crista instance.

Columns:

```text
image_name
crista_visual_id
instance_label_value
decoded_class
area_px
centroid_x
centroid_y
assigned_mito_id
assignment_status
overlap_details
```

The table records:

- the image identifier;
- the original crista instance-label value;
- the decoded crista class;
- instance area and centroid coordinates;
- the mitochondrial object to which the instance was assigned;
- assignment status;
- pixel-overlap information used during assignment.

## `cristae_counts_per_mito.csv`

This file contains one row for each retained mitochondrial object.

Columns:

```text
image_name
mitochondrion_id
centroid_x
centroid_y
area_px
class_2000
class_3000
class_4000
class_5000
class_6000
class_7000
class_8000
class_9000
class_10000
class_11000
class_12000
class_13000
total_cristae
```

The table records:

- the mitochondrial-object identifier;
- mitochondrial centroid coordinates and area;
- the number of assigned crista instances for each decoded class;
- the total number of assigned cristae per mitochondrial object.

A valid mitochondrial object may have a total crista count of zero.

## `cristae_counts_image_summary.csv`

This file contains image-level summaries derived from the
per-mitochondrion results.

Columns:

```text
image_name
mitochondria_count
total_cristae
class_2000
class_3000
class_4000
class_5000
class_6000
class_7000
class_8000
class_9000
class_10000
class_11000
class_12000
class_13000
```

The table records:

- the number of retained mitochondrial objects in each image;
- the total assigned crista count per image;
- image-level totals for each decoded crista class.

## Relationship to the curated automated workbook

Relevant values from the processed Python outputs were transferred into:

```text
data/curated/cristae_automated.xlsx
```

During curation:

- mitochondrial segmentation objects were visually reviewed;
- confirmed mitochondrial segmentation errors were excluded;
- valid mitochondrial profiles with zero detected cristae remained included;
- the workbook structure was aligned with the manual analytical workbook.

The Python CSV files were not modified to reflect the later manual curation
decisions.

Detailed provenance and curation information is provided in:

```text
docs/DATA_PROVENANCE.md
```

## Reproduction

The repository Python implementation is:

```text
scripts/python/count_cristae_per_mito.py
```

Display its command-line options with:

```bash
python scripts/python/count_cristae_per_mito.py --help
```

## Data protection

Before replacing or adding processed outputs, review them for:

- subject or sample identifiers;
- acquisition and image filenames;
- local filesystem paths;
- confidential information;
- publication status;
- consistency with the curated automated workbook and provenance
  documentation.

Raw microscopy images, complete segmentation inputs, and protected
patient-level quality-control material are maintained outside this repository.
