from __future__ import annotations

import importlib.util
import logging
from pathlib import Path
import tempfile
import unittest

import numpy as np
import pandas as pd


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = REPOSITORY_ROOT / "scripts" / "python" / "count_cristae_per_mito.py"

SPEC = importlib.util.spec_from_file_location("count_cristae_per_mito", SCRIPT_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"Unable to load Python preprocessing script: {SCRIPT_PATH}")

PREPROCESSOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPROCESSOR)


class CristaeCounterTests(unittest.TestCase):
    def setUp(self) -> None:
        PREPROCESSOR.VALID_CLASSES = list(range(2000, 13001, 1000))
        PREPROCESSOR.MITO_BACKGROUND_VALUE = 255
        PREPROCESSOR.FLOAT_TO_INT_TOL = 1e-6
        PREPROCESSOR.MITO_CONNECTIVITY = 1
        PREPROCESSOR.MIN_MITO_AREA_PX = 10
        PREPROCESSOR.ASSIGN_BY_MAX_OVERLAP = True
        PREPROCESSOR.SAVE_MITO_LABEL_TIF = True
        PREPROCESSOR.SAVE_MITO_LABEL_TIF_AS_UINT8 = True
        PREPROCESSOR.PNG_DPI = 40

        self.logger = logging.getLogger(f"cristae_counter_test_{id(self)}")
        self.logger.handlers.clear()
        self.logger.addHandler(logging.NullHandler())

    def test_core_assignment_and_class_13_preservation(self) -> None:
        mito_labels = np.zeros((6, 10), dtype=np.int32)
        mito_labels[1:5, 1:4] = 1
        mito_labels[1:5, 6:9] = 2

        cristae_labels = np.zeros_like(mito_labels, dtype=np.int64)
        cristae_labels[1:3, 1:3] = 2001
        cristae_labels[1:3, 7:9] = 13001
        cristae_labels[3, 3] = 3001
        cristae_labels[3, 6] = 3001
        cristae_labels[0, 0] = 4001
        cristae_labels[5, 9] = 14001

        instance_rows, stats = PREPROCESSOR.analyze_cristae_instances(
            cristae_labels=cristae_labels,
            mito_labels=mito_labels,
            image_name="synthetic_image",
            logger=self.logger,
        )

        self.assertEqual(stats["unique_instance_values"], 5)
        self.assertEqual(stats["assigned_instances"], 3)
        self.assertEqual(stats["skipped_invalid_class"], 1)
        self.assertEqual(stats["multi_overlap_instances"], 1)
        self.assertEqual(stats["zero_overlap_instances"], 1)

        row_by_label = {
            row["instance_label_value"]: row
            for row in instance_rows
        }
        self.assertEqual(row_by_label[3001]["assignment_status"], "assigned_max_overlap")
        self.assertEqual(row_by_label[3001]["assigned_mito_id"], 1)
        self.assertEqual(row_by_label[13001]["decoded_class"], 13000)
        self.assertEqual(row_by_label[14001]["assignment_status"], "invalid_class")
        self.assertEqual(row_by_label[4001]["assignment_status"], "zero_overlap")

        mito_info = [
            {
                "mitochondrion_id": 1,
                "centroid_x": 2.0,
                "centroid_y": 2.5,
                "area_px": 12,
            },
            {
                "mitochondrion_id": 2,
                "centroid_x": 7.0,
                "centroid_y": 2.5,
                "area_px": 12,
            },
        ]
        count_rows = PREPROCESSOR.build_mito_count_rows(
            mito_info=mito_info,
            instance_rows=instance_rows,
            image_name="synthetic_image",
        )

        count_by_mito = {
            row["mitochondrion_id"]: row
            for row in count_rows
        }
        self.assertEqual(count_by_mito[1]["total_cristae"], 2)
        self.assertEqual(count_by_mito[2]["total_cristae"], 1)
        self.assertEqual(count_by_mito[2]["class_13000"], 1)

    def test_output_schema_contains_original_class_range(self) -> None:
        dataframe = PREPROCESSOR.build_output_dataframe(
            [
                {
                    "image_name": "synthetic_image",
                    "mitochondrion_id": 1,
                    "centroid_x": 2.0,
                    "centroid_y": 2.5,
                    "area_px": 12,
                    "class_2000": 1,
                    "class_13000": 1,
                    "total_cristae": 2,
                }
            ]
        )

        self.assertEqual(dataframe.loc[0, "class_2000"], 1)
        self.assertEqual(dataframe.loc[0, "class_13000"], 1)
        self.assertEqual(dataframe.loc[0, "total_cristae"], 2)
        self.assertEqual(
            [column for column in dataframe.columns if column.startswith("class_")],
            [f"class_{value}" for value in range(2000, 13001, 1000)],
        )

    @unittest.skipUnless(
        PREPROCESSOR.tifffile is not None
        and PREPROCESSOR.label is not None
        and PREPROCESSOR.regionprops is not None
        and PREPROCESSOR.find_boundaries is not None,
        "Full TIFF smoke test requires tifffile and scikit-image.",
    )
    def test_end_to_end_with_synthetic_tiffs(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory)
            mito_dir = root / "mitochondria"
            cristae_dir = root / "cristae"
            output_dir = root / "output"
            mito_dir.mkdir()
            cristae_dir.mkdir()

            mito_image = np.full((24, 32), 255, dtype=np.uint8)
            mito_image[2:12, 2:12] = 0
            mito_image[2:12, 18:28] = 0

            cristae_image = np.zeros((24, 32), dtype=np.float32)
            cristae_image[4:6, 4:6] = 2001
            cristae_image[7:9, 7:9] = 3001
            cristae_image[4:6, 20:22] = 13001
            cristae_image[15:17, 14:16] = 14001

            PREPROCESSOR.tifffile.imwrite(mito_dir / "synthetic_image.tif", mito_image)
            PREPROCESSOR.tifffile.imwrite(
                cristae_dir / "synthetic_image.tiff",
                cristae_image,
            )

            PREPROCESSOR.main(
                [
                    "--mito-dir",
                    str(mito_dir),
                    "--cristae-dir",
                    str(cristae_dir),
                    "--output-dir",
                    str(output_dir),
                    "--run-id",
                    "synthetic",
                    "--png-dpi",
                    "40",
                    "--fail-on-unpaired",
                ]
            )

            main_csv = output_dir / "cristae_counts_per_mito_synthetic.csv"
            summary_csv = output_dir / "cristae_counts_image_summary_synthetic.csv"
            instance_csv = output_dir / "all_cristae_instances_synthetic.csv"

            self.assertTrue(main_csv.is_file())
            self.assertTrue(summary_csv.is_file())
            self.assertTrue(instance_csv.is_file())
            self.assertTrue(
                (
                    output_dir
                    / "synthetic_image"
                    / "synthetic_image__mitochondria_labels.tif"
                ).is_file()
            )

            main_table = pd.read_csv(main_csv)
            self.assertEqual(len(main_table), 2)
            self.assertEqual(int(main_table["total_cristae"].sum()), 3)
            self.assertEqual(int(main_table["class_13000"].sum()), 1)


if __name__ == "__main__":
    unittest.main()
