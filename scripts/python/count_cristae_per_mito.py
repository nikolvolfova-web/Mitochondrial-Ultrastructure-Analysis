#!/usr/bin/env python3
"""Count classified cristae instances within segmented mitochondria.

Authorship
----------
Original Python preprocessing script and core computational logic:
    Martin Čapek (LMCF-IMG; https://github.com/LMCF-IMG)

Repository integration, portable command-line adaptation, documentation,
and synthetic tests:
    Nikol Volfová

The repository version is included with Martin Čapek's knowledge and permission.
"""

from __future__ import annotations

import argparse
import colorsys
from datetime import datetime
import logging
import math
from pathlib import Path
import re
import sys

import matplotlib
import numpy as np
import pandas as pd

matplotlib.use("Agg")
import matplotlib.pyplot as plt

from scipy import ndimage as ndi

try:
    import tifffile
except ModuleNotFoundError:  # Allows dependency-free CLI help and core tests.
    tifffile = None

try:
    from skimage.measure import label, regionprops
    from skimage.segmentation import find_boundaries
except ModuleNotFoundError:  # Allows dependency-free CLI help and core tests.
    label = None
    regionprops = None
    find_boundaries = None


# =============================================================================
# PROCESSING DEFAULTS
# =============================================================================

# Preserve the decoded-label range in the supplied research script. Validation
# against the reference CSV outputs is intentionally deferred to the R phase.
VALID_CLASSES = list(range(2000, 13001, 1000))  # 2000, 3000, ..., 13000

# White background in the mitochondrial mask.
MITO_BACKGROUND_VALUE = 255

# Tolerance used when converting floating-point panoptic values to integers.
FLOAT_TO_INT_TOL = 1e-6

# Mitochondrial connectivity: 1 = 4-connectivity, 2 = 8-connectivity.
MITO_CONNECTIVITY = 1

# Connected components below this area are excluded.
MIN_MITO_AREA_PX = 10

# Assign a crista spanning multiple mitochondria to the largest overlap.
ASSIGN_BY_MAX_OVERLAP = True

# Save a relabelled mitochondrial map as TIFF.
SAVE_MITO_LABEL_TIF = True

# Save the label TIFF as uint8 by default.
SAVE_MITO_LABEL_TIF_AS_UINT8 = True

# PNG output resolution.
PNG_DPI = 180

# Identifier label sizes.
MITO_ID_FONT_SIZE = 8
CRISTAE_ID_FONT_SIZE = 6

# Automatic crista-label placement.
CRISTAE_LABEL_COLLISION_MIN_DIST_PX = 26.0
CRISTAE_LABEL_OFFSET_STEP_PX = 10.0
CRISTAE_LABEL_MAX_RING = 8
CRISTAE_LABEL_DRAW_CONNECTOR = True


# =============================================================================
# COMMAND-LINE INTERFACE
# =============================================================================

def positive_int(value: str) -> int:
    parsed = int(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("value must be a positive integer")
    return parsed


def non_negative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("value must be non-negative")
    return parsed


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Pair mitochondrial .tif masks with cristae .tiff panoptic masks, "
            "assign cristae instances to mitochondria, and export CSV and QC files."
        )
    )
    parser.add_argument(
        "--mito-dir",
        required=True,
        type=Path,
        help="Directory containing mitochondrial masks with the .tif extension.",
    )
    parser.add_argument(
        "--cristae-dir",
        required=True,
        type=Path,
        help="Directory containing cristae panoptic masks with the .tiff extension.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        type=Path,
        help="Directory to receive CSV tables, logs, label TIFFs, and QC images.",
    )
    parser.add_argument(
        "--valid-classes",
        nargs="+",
        type=positive_int,
        default=list(VALID_CLASSES),
        metavar="LABEL",
        help=(
            "Allowed decoded class labels. Defaults to 2000 through 13000 in "
            "steps of 1000, preserving the supplied script."
        ),
    )
    parser.add_argument(
        "--mito-background-value",
        type=float,
        default=MITO_BACKGROUND_VALUE,
        help="Background value in mitochondrial masks (default: 255).",
    )
    parser.add_argument(
        "--float-to-int-tol",
        type=non_negative_float,
        default=FLOAT_TO_INT_TOL,
        help="Tolerance before warning about non-integer cristae labels.",
    )
    parser.add_argument(
        "--mito-connectivity",
        type=int,
        choices=(1, 2),
        default=MITO_CONNECTIVITY,
        help="Connected-component connectivity: 1 for 4-neighbour or 2 for 8-neighbour.",
    )
    parser.add_argument(
        "--min-mito-area-px",
        type=positive_int,
        default=MIN_MITO_AREA_PX,
        help="Minimum mitochondrial connected-component area in pixels.",
    )
    parser.add_argument(
        "--assign-by-max-overlap",
        action=argparse.BooleanOptionalAction,
        default=ASSIGN_BY_MAX_OVERLAP,
        help="Assign multi-overlap cristae to the mitochondrion with the largest overlap.",
    )
    parser.add_argument(
        "--save-mito-label-tif",
        action=argparse.BooleanOptionalAction,
        default=SAVE_MITO_LABEL_TIF,
        help="Save the relabelled mitochondrial map as TIFF.",
    )
    parser.add_argument(
        "--mito-label-dtype",
        choices=("uint8", "uint16"),
        default="uint8" if SAVE_MITO_LABEL_TIF_AS_UINT8 else "uint16",
        help="Data type for the relabelled mitochondrial TIFF.",
    )
    parser.add_argument(
        "--png-dpi",
        type=positive_int,
        default=PNG_DPI,
        help="Resolution of QC PNG files.",
    )
    parser.add_argument(
        "--run-id",
        help=(
            "Optional deterministic suffix for run-level filenames. "
            "Allowed characters: letters, numbers, dot, underscore, and hyphen."
        ),
    )
    parser.add_argument(
        "--fail-on-unpaired",
        action="store_true",
        help="Stop if a mitochondrial or cristae mask has no stem-matched partner.",
    )
    parser.add_argument(
        "--allow-partial",
        action="store_true",
        help="Return success even if one or more paired images fail.",
    )
    return parser.parse_args(argv)


def configure_from_args(args: argparse.Namespace) -> None:
    global VALID_CLASSES
    global MITO_BACKGROUND_VALUE
    global FLOAT_TO_INT_TOL
    global MITO_CONNECTIVITY
    global MIN_MITO_AREA_PX
    global ASSIGN_BY_MAX_OVERLAP
    global SAVE_MITO_LABEL_TIF
    global SAVE_MITO_LABEL_TIF_AS_UINT8
    global PNG_DPI

    classes = list(dict.fromkeys(args.valid_classes))
    if classes != sorted(classes):
        raise ValueError("--valid-classes must be provided in ascending order")
    if any(value % 1000 != 0 for value in classes):
        raise ValueError("--valid-classes values must be positive multiples of 1000")

    if args.run_id and not re.fullmatch(r"[A-Za-z0-9._-]+", args.run_id):
        raise ValueError("--run-id contains unsupported characters")

    VALID_CLASSES = classes
    MITO_BACKGROUND_VALUE = args.mito_background_value
    FLOAT_TO_INT_TOL = args.float_to_int_tol
    MITO_CONNECTIVITY = args.mito_connectivity
    MIN_MITO_AREA_PX = args.min_mito_area_px
    ASSIGN_BY_MAX_OVERLAP = args.assign_by_max_overlap
    SAVE_MITO_LABEL_TIF = args.save_mito_label_tif
    SAVE_MITO_LABEL_TIF_AS_UINT8 = args.mito_label_dtype == "uint8"
    PNG_DPI = args.png_dpi


def require_runtime_dependencies() -> None:
    missing = []
    if tifffile is None:
        missing.append("tifffile")
    if label is None or regionprops is None or find_boundaries is None:
        missing.append("scikit-image")
    if missing:
        raise ModuleNotFoundError(
            "Missing Python runtime dependencies: "
            + ", ".join(missing)
            + ". Install them with: python -m pip install -r requirements-python.txt"
        )


# =============================================================================
# LOGGING
# =============================================================================

def setup_logging(log_file: Path) -> logging.Logger:
    log_file.parent.mkdir(parents=True, exist_ok=True)

    logger = logging.getLogger("cristae_counter")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()

    fmt = logging.Formatter(
        "%(asctime)s | %(levelname)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    fh = logging.FileHandler(log_file, mode="w", encoding="utf-8")
    fh.setLevel(logging.INFO)
    fh.setFormatter(fmt)
    logger.addHandler(fh)

    sh = logging.StreamHandler(sys.stdout)
    sh.setLevel(logging.INFO)
    sh.setFormatter(fmt)
    logger.addHandler(sh)

    return logger


# =============================================================================
# INPUT/OUTPUT AND VALIDATION
# =============================================================================

def read_single_image(path: Path) -> np.ndarray:
    arr = tifffile.imread(path)
    arr = np.asarray(arr)
    arr = np.squeeze(arr)

    if arr.ndim != 2:
        raise ValueError(f"Expected a 2D image: {path} | shape={arr.shape}")

    return arr


def collect_pairs(
    mito_dir: Path,
    cristae_dir: Path,
    logger: logging.Logger,
    *,
    fail_on_unpaired: bool = False,
) -> list[tuple[str, Path, Path]]:
    mito_files = sorted(mito_dir.glob("*.tif"))
    cristae_files = sorted(cristae_dir.glob("*.tiff"))

    mito_map = {p.stem: p for p in mito_files}
    cristae_map = {p.stem: p for p in cristae_files}

    mito_keys = set(mito_map.keys())
    cristae_keys = set(cristae_map.keys())

    common = sorted(mito_keys & cristae_keys)
    only_mito = sorted(mito_keys - cristae_keys)
    only_cristae = sorted(cristae_keys - mito_keys)

    logger.info(f"Mitochondrial .tif files found: {len(mito_files)}")
    logger.info(f"Cristae .tiff files found: {len(cristae_files)}")
    logger.info(f"Stem-matched image pairs found: {len(common)}")

    if only_mito:
        logger.warning(
            f"Unpaired mitochondrial .tif files: {len(only_mito)}"
        )
        for k in only_mito[:20]:
            logger.warning(f"  missing cristae .tiff for: {k}")
        if len(only_mito) > 20:
            logger.warning("  ... additional unpaired .tif files omitted")

    if only_cristae:
        logger.warning(
            f"Unpaired cristae .tiff files: {len(only_cristae)}"
        )
        for k in only_cristae[:20]:
            logger.warning(f"  missing mitochondrial .tif for: {k}")
        if len(only_cristae) > 20:
            logger.warning("  ... additional unpaired .tiff files omitted")

    if fail_on_unpaired and (only_mito or only_cristae):
        raise ValueError(
            "Unpaired inputs detected while --fail-on-unpaired is enabled: "
            f"mitochondrial_only={len(only_mito)}, cristae_only={len(only_cristae)}"
        )

    return [(stem, mito_map[stem], cristae_map[stem]) for stem in common]


# =============================================================================
# MITOCHONDRIA
# =============================================================================

def make_mito_binary_mask(mito_img: np.ndarray) -> np.ndarray:
    if mito_img.dtype.kind not in ("u", "i", "f"):
        raise ValueError(f"Unsupported mitochondrial image dtype: {mito_img.dtype}")

    # Objects are expected below the configured white-background value.
    mask = mito_img < MITO_BACKGROUND_VALUE
    return mask


def fill_holes_in_mito_mask(mito_binary: np.ndarray) -> tuple[np.ndarray, int]:
    filled = ndi.binary_fill_holes(mito_binary)
    added_pixels = int(np.count_nonzero(filled & ~mito_binary))
    return filled.astype(bool), added_pixels


def relabel_mito_left_to_right_then_top_to_bottom(
    mito_binary: np.ndarray,
    logger: logging.Logger,
) -> tuple[np.ndarray, list[dict], dict]:
    raw_labels = label(mito_binary, connectivity=MITO_CONNECTIVITY)
    props = regionprops(raw_labels)

    total_detected = len(props)
    kept_props = [rp for rp in props if int(rp.area) >= MIN_MITO_AREA_PX]
    removed_props = [rp for rp in props if int(rp.area) < MIN_MITO_AREA_PX]

    logger.info(f"Mitochondria detected before the area filter: {total_detected}")
    logger.info(
        f"Mitochondria removed with area < {MIN_MITO_AREA_PX} px: {len(removed_props)}"
    )
    logger.info(f"Mitochondria retained after the area filter: {len(kept_props)}")

    if removed_props:
        removed_areas = [int(rp.area) for rp in removed_props]
        logger.info(
            "Removed mitochondrial components - area min/max: "
            f"{min(removed_areas)}/{max(removed_areas)} px"
        )

    # Sort primarily by x and secondarily by y.
    props_sorted = sorted(kept_props, key=lambda r: (r.centroid[1], r.centroid[0]))

    relabeled = np.zeros_like(raw_labels, dtype=np.int32)
    mito_info: list[dict] = []

    for new_id, rp in enumerate(props_sorted, start=1):
        relabeled[raw_labels == rp.label] = new_id
        mito_info.append(
            {
                "mitochondrion_id": new_id,
                "old_label": rp.label,
                "centroid_y": float(rp.centroid[0]),
                "centroid_x": float(rp.centroid[1]),
                "area_px": int(rp.area),
                "bbox_min_row": int(rp.bbox[0]),
                "bbox_min_col": int(rp.bbox[1]),
                "bbox_max_row": int(rp.bbox[2]),
                "bbox_max_col": int(rp.bbox[3]),
            }
        )

    stats = {
        "total_detected_before_filter": total_detected,
        "removed_small_mitos": len(removed_props),
        "kept_after_filter": len(kept_props),
    }

    return relabeled, mito_info, stats


# =============================================================================
# CRISTAE
# =============================================================================

def convert_cristae_to_int_labels(cristae_img: np.ndarray, logger: logging.Logger) -> np.ndarray:
    if cristae_img.dtype.kind not in ("u", "i", "f"):
        raise ValueError(f"Unsupported cristae image dtype: {cristae_img.dtype}")

    rounded = np.rint(cristae_img)
    diff = np.abs(cristae_img - rounded)

    max_diff = float(np.max(diff))
    if max_diff > FLOAT_TO_INT_TOL:
        logger.warning(
            "The cristae image contains values that differ from integer labels. "
            f"max_diff={max_diff:.6g}. Values will be rounded."
        )

    return rounded.astype(np.int64)


def decode_class_from_instance_label(instance_value: int) -> int:
    return (instance_value // 1000) * 1000


def analyze_cristae_instances(
    cristae_labels: np.ndarray,
    mito_labels: np.ndarray,
    image_name: str,
    logger: logging.Logger,
) -> tuple[list[dict], dict]:
    if cristae_labels.shape != mito_labels.shape:
        raise ValueError(
            f"Image dimensions do not match for {image_name}: "
            f"cristae={cristae_labels.shape}, mito={mito_labels.shape}"
        )

    positive_mask = cristae_labels > 0
    unique_instance_values = np.unique(cristae_labels[positive_mask])

    logger.info(
        f"Unique non-zero cristae instance labels in the image: {len(unique_instance_values)}"
    )

    instance_rows: list[dict] = []

    skipped_invalid_class = 0
    assigned_instances = 0
    multi_overlap_instances = 0
    zero_overlap_instances = 0

    for visual_id, inst_val in enumerate(unique_instance_values, start=1):
        inst_val = int(inst_val)
        cls = decode_class_from_instance_label(inst_val)

        inst_mask = cristae_labels == inst_val
        area_px = int(inst_mask.sum())

        coords = np.argwhere(inst_mask)
        centroid_y = float(coords[:, 0].mean())
        centroid_x = float(coords[:, 1].mean())

        row = {
            "image_name": image_name,
            "crista_visual_id": visual_id,
            "instance_label_value": inst_val,
            "decoded_class": cls,
            "area_px": area_px,
            "centroid_x": round(centroid_x, 3),
            "centroid_y": round(centroid_y, 3),
            "assigned_mito_id": 0,
            "assignment_status": "",
            "overlap_details": "",
        }

        if cls not in VALID_CLASSES:
            skipped_invalid_class += 1
            row["assignment_status"] = "invalid_class"
            instance_rows.append(row)
            logger.warning(
                f"{image_name}: instance label {inst_val} decodes to class {cls}, "
                "which is not in VALID_CLASSES. The instance will be skipped."
            )
            continue

        overlapping_mito = mito_labels[inst_mask]
        overlapping_mito = overlapping_mito[overlapping_mito > 0]

        if overlapping_mito.size == 0:
            zero_overlap_instances += 1
            row["assignment_status"] = "zero_overlap"
            instance_rows.append(row)
            logger.warning(
                f"{image_name}: instance label {inst_val} (class {cls}) "
                "does not overlap a retained mitochondrion."
            )
            continue

        mito_vals, mito_counts = np.unique(overlapping_mito, return_counts=True)
        overlap_details = ", ".join(
            f"{int(mito_id)}[{int(pixel_count)} px]"
            for mito_id, pixel_count in zip(mito_vals, mito_counts)
        )
        row["overlap_details"] = overlap_details

        if len(mito_vals) > 1:
            multi_overlap_instances += 1
            msg = (
                f"{image_name}: instance label {inst_val} (class {cls}) "
                "overlaps multiple mitochondria: "
                + overlap_details
            )
            if ASSIGN_BY_MAX_OVERLAP:
                chosen_mito = int(mito_vals[np.argmax(mito_counts)])
                row["assigned_mito_id"] = chosen_mito
                row["assignment_status"] = "assigned_max_overlap"
                logger.warning(msg + " | assigned by maximum overlap.")
            else:
                row["assignment_status"] = "skipped_multi_overlap"
                instance_rows.append(row)
                logger.warning(msg + " | instance skipped.")
                continue
        else:
            chosen_mito = int(mito_vals[0])
            row["assigned_mito_id"] = chosen_mito
            row["assignment_status"] = "assigned"
            logger.info(
                f"{image_name}: crista #{visual_id} | label={inst_val} | "
                f"class={cls} | mito={chosen_mito} | area={area_px}"
            )

        assigned_instances += 1
        instance_rows.append(row)

    stats = {
        "unique_instance_values": int(len(unique_instance_values)),
        "assigned_instances": int(assigned_instances),
        "skipped_invalid_class": int(skipped_invalid_class),
        "multi_overlap_instances": int(multi_overlap_instances),
        "zero_overlap_instances": int(zero_overlap_instances),
    }

    return instance_rows, stats


def build_mito_count_rows(
    mito_info: list[dict],
    instance_rows: list[dict],
    image_name: str,
) -> list[dict]:
    mito_ids = [m["mitochondrion_id"] for m in mito_info]
    counts = {mito_id: {cls: 0 for cls in VALID_CLASSES} for mito_id in mito_ids}

    for row in instance_rows:
        if row["assignment_status"] not in {"assigned", "assigned_max_overlap"}:
            continue
        mito_id = int(row["assigned_mito_id"])
        cls = int(row["decoded_class"])
        if mito_id in counts and cls in counts[mito_id]:
            counts[mito_id][cls] += 1

    rows = []
    for m in mito_info:
        mito_id = m["mitochondrion_id"]
        out = {
            "image_name": image_name,
            "mitochondrion_id": mito_id,
            "centroid_x": round(m["centroid_x"], 3),
            "centroid_y": round(m["centroid_y"], 3),
            "area_px": m["area_px"],
        }

        total = 0
        for cls in VALID_CLASSES:
            value = counts[mito_id][cls]
            out[f"class_{cls}"] = value
            total += value

        out["total_cristae"] = total
        rows.append(out)

    return rows


# =============================================================================
# LOOKUP TABLE AND LABEL-TIFF OUTPUT
# =============================================================================

def make_glasbey_on_dark_like_colormap_8bit() -> np.ndarray:
    """
    Return a TIFF colormap with shape (3, 256) and dtype uint16.

    Index 0 is a black background. Remaining indices are contrasting colours.
    """
    cmap = np.zeros((3, 256), dtype=np.uint16)
    cmap[:, 0] = 0

    golden_ratio = 0.618033988749895
    h = 0.0

    for i in range(1, 256):
        h = (h + golden_ratio) % 1.0
        s = 0.75 if (i % 2 == 0) else 0.95
        v = 1.0 if (i % 3 != 0) else 0.85
        r, g, b = colorsys.hsv_to_rgb(h, s, v)
        cmap[0, i] = np.uint16(round(r * 65535))
        cmap[1, i] = np.uint16(round(g * 65535))
        cmap[2, i] = np.uint16(round(b * 65535))

    return cmap


def save_mito_label_tif(path: Path, mito_labels: np.ndarray, logger: logging.Logger) -> None:
    max_label = int(mito_labels.max())

    if SAVE_MITO_LABEL_TIF_AS_UINT8:
        if max_label > 255:
            raise ValueError(
                f"The mitochondrial count ({max_label}) exceeds an 8-bit label TIFF. "
                "Use --mito-label-dtype uint16."
            )
        out = mito_labels.astype(np.uint8)
        colormap = make_glasbey_on_dark_like_colormap_8bit()
        tifffile.imwrite(path, out, photometric="palette", colormap=colormap)
    else:
        out = mito_labels.astype(np.uint16)
        tifffile.imwrite(path, out)

    logger.info(f"Saved label TIFF: {path} | dtype={out.dtype} | max_label={max_label}")


# =============================================================================
# VISUALIZATION
# =============================================================================

def save_mito_id_png(
    path: Path,
    mito_binary: np.ndarray,
    mito_labels: np.ndarray,
    mito_info: list[dict],
    image_name: str,
) -> None:
    boundaries = find_boundaries(mito_labels, mode="outer")

    fig, ax = plt.subplots(figsize=(10, 10))
    ax.imshow(mito_binary, cmap="gray")
    ax.imshow(np.ma.masked_where(~boundaries, boundaries), alpha=0.8)

    for m in mito_info:
        ax.text(
            m["centroid_x"],
            m["centroid_y"],
            str(m["mitochondrion_id"]),
            color="yellow",
            fontsize=MITO_ID_FONT_SIZE,
            ha="center",
            va="center",
            bbox=dict(boxstyle="round,pad=0.15", fc="black", ec="none", alpha=0.6),
        )

    ax.set_title(f"{image_name} | mitochondria IDs")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=PNG_DPI, bbox_inches="tight")
    plt.close(fig)


def save_cristae_overlay_png(
    path: Path,
    mito_binary: np.ndarray,
    mito_labels: np.ndarray,
    mito_info: list[dict],
    cristae_labels: np.ndarray,
    image_name: str,
) -> None:
    mito_boundaries = find_boundaries(mito_labels, mode="outer")
    cristae_positive = cristae_labels > 0
    cristae_boundaries = find_boundaries(cristae_positive.astype(np.uint8), mode="outer")

    fig, ax = plt.subplots(figsize=(10, 10))
    ax.imshow(mito_binary, cmap="gray", alpha=1.0)
    ax.imshow(np.ma.masked_where(~mito_boundaries, mito_boundaries), alpha=0.8)

    class_map = np.zeros_like(cristae_labels, dtype=np.int32)
    pos_vals = np.unique(cristae_labels[cristae_labels > 0])

    for v in pos_vals:
        v = int(v)
        cls = decode_class_from_instance_label(v)
        if cls in VALID_CLASSES:
            class_map[cristae_labels == v] = cls

    masked_class_map = np.ma.masked_where(class_map == 0, class_map)
    ax.imshow(masked_class_map, alpha=0.45, cmap="nipy_spectral")
    ax.imshow(np.ma.masked_where(~cristae_boundaries, cristae_boundaries), alpha=0.9)

    for m in mito_info:
        ax.text(
            m["centroid_x"],
            m["centroid_y"],
            str(m["mitochondrion_id"]),
            color="white",
            fontsize=MITO_ID_FONT_SIZE,
            ha="center",
            va="center",
            bbox=dict(boxstyle="round,pad=0.15", fc="black", ec="none", alpha=0.65),
        )

    ax.set_title(f"{image_name} | cristae overlay")
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=PNG_DPI, bbox_inches="tight")
    plt.close(fig)


def save_cristae_class_map_png(
    path: Path,
    cristae_labels: np.ndarray,
    image_name: str,
) -> None:
    class_map = np.zeros_like(cristae_labels, dtype=np.int32)

    pos_vals = np.unique(cristae_labels[cristae_labels > 0])
    for v in pos_vals:
        v = int(v)
        cls = decode_class_from_instance_label(v)
        if cls in VALID_CLASSES:
            class_map[cristae_labels == v] = cls

    masked = np.ma.masked_where(class_map == 0, class_map)

    fig, ax = plt.subplots(figsize=(10, 10))
    im = ax.imshow(masked, cmap="nipy_spectral")
    ax.set_title(f"{image_name} | cristae class map")
    ax.axis("off")
    cbar = fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label("Cristae class")
    fig.tight_layout()
    fig.savefig(path, dpi=PNG_DPI, bbox_inches="tight")
    plt.close(fig)


def format_crista_text_multiline(row: dict) -> str:
    crista_id = int(row["crista_visual_id"])
    cls = int(row["decoded_class"])
    mito = int(row["assigned_mito_id"])
    return f"ID:{crista_id}\nC:{cls}\nM:{mito}"


def generate_candidate_offsets(step_px: float, max_ring: int) -> list[tuple[float, float]]:
    candidates: list[tuple[float, float]] = [(0.0, 0.0)]
    for ring in range(1, max_ring + 1):
        r = ring * step_px
        dirs = [
            (0.0, -r),
            (r, 0.0),
            (0.0, r),
            (-r, 0.0),
            (0.7071 * r, -0.7071 * r),
            (0.7071 * r, 0.7071 * r),
            (-0.7071 * r, 0.7071 * r),
            (-0.7071 * r, -0.7071 * r),
            (0.5 * r, -0.8660 * r),
            (0.8660 * r, -0.5 * r),
            (0.8660 * r, 0.5 * r),
            (0.5 * r, 0.8660 * r),
            (-0.5 * r, 0.8660 * r),
            (-0.8660 * r, 0.5 * r),
            (-0.8660 * r, -0.5 * r),
            (-0.5 * r, -0.8660 * r),
        ]
        candidates.extend(dirs)
    return candidates


def plan_crista_label_positions(
    instance_rows: list[dict],
    image_shape: tuple[int, int],
    min_dist_px: float,
    step_px: float,
    max_ring: int,
) -> list[dict]:
    """
    Place labels greedily to reduce overlap.

    Start at each centroid and choose the nearest available candidate offset.
    """
    h, w = image_shape
    margin = 6.0
    candidates = generate_candidate_offsets(step_px=step_px, max_ring=max_ring)

    rows_sorted = sorted(
        instance_rows,
        key=lambda r: (r["centroid_y"], r["centroid_x"])
    )

    placed: list[tuple[float, float]] = []
    planned_rows: list[dict] = []

    for row in rows_sorted:
        base_x = float(row["centroid_x"])
        base_y = float(row["centroid_y"])

        best_x = base_x
        best_y = base_y
        best_score = float("inf")

        for dx, dy in candidates:
            tx = base_x + dx
            ty = base_y + dy

            tx = min(max(tx, margin), w - 1 - margin)
            ty = min(max(ty, margin), h - 1 - margin)

            if placed:
                dists = [math.hypot(tx - px, ty - py) for px, py in placed]
                min_d = min(dists)
            else:
                min_d = float("inf")

            penalty = 0.0 if min_d >= min_dist_px else (min_dist_px - min_d) * 1000.0
            move_cost = math.hypot(tx - base_x, ty - base_y)

            score = penalty + move_cost

            if score < best_score:
                best_score = score
                best_x = tx
                best_y = ty

            if penalty == 0.0 and move_cost == 0.0:
                break

        new_row = dict(row)
        new_row["label_x"] = round(best_x, 3)
        new_row["label_y"] = round(best_y, 3)
        new_row["label_dx"] = round(best_x - base_x, 3)
        new_row["label_dy"] = round(best_y - base_y, 3)
        planned_rows.append(new_row)
        placed.append((best_x, best_y))

    return planned_rows


def save_cristae_ids_png(
    path: Path,
    mito_binary: np.ndarray,
    mito_labels: np.ndarray,
    instance_rows: list[dict],
    cristae_labels: np.ndarray,
    image_name: str,
) -> None:
    mito_boundaries = find_boundaries(mito_labels, mode="outer")

    class_map = np.zeros_like(cristae_labels, dtype=np.int32)
    pos_vals = np.unique(cristae_labels[cristae_labels > 0])
    for v in pos_vals:
        v = int(v)
        cls = decode_class_from_instance_label(v)
        if cls in VALID_CLASSES:
            class_map[cristae_labels == v] = cls

    masked_class_map = np.ma.masked_where(class_map == 0, class_map)

    planned_rows = plan_crista_label_positions(
        instance_rows=instance_rows,
        image_shape=cristae_labels.shape,
        min_dist_px=CRISTAE_LABEL_COLLISION_MIN_DIST_PX,
        step_px=CRISTAE_LABEL_OFFSET_STEP_PX,
        max_ring=CRISTAE_LABEL_MAX_RING,
    )

    fig, ax = plt.subplots(figsize=(12, 12))
    ax.imshow(mito_binary, cmap="gray", alpha=1.0)
    ax.imshow(np.ma.masked_where(~mito_boundaries, mito_boundaries), alpha=0.8)
    ax.imshow(masked_class_map, alpha=0.5, cmap="nipy_spectral")

    for row in planned_rows:
        status = row["assignment_status"]
        x0 = float(row["centroid_x"])
        y0 = float(row["centroid_y"])
        x = float(row["label_x"])
        y = float(row["label_y"])

        if status in {"assigned", "assigned_max_overlap"}:
            txt = format_crista_text_multiline(row)
            color = "white"
        elif status == "invalid_class":
            txt = format_crista_text_multiline(row) + "\n!"
            color = "red"
        elif status == "zero_overlap":
            txt = format_crista_text_multiline(row) + "\n?"
            color = "cyan"
        else:
            txt = format_crista_text_multiline(row) + "\nx"
            color = "magenta"

        if CRISTAE_LABEL_DRAW_CONNECTOR and (abs(x - x0) > 1.0 or abs(y - y0) > 1.0):
            ax.plot([x0, x], [y0, y], color=color, linewidth=0.6, alpha=0.85)

        ax.text(
            x,
            y,
            txt,
            color=color,
            fontsize=CRISTAE_ID_FONT_SIZE,
            ha="center",
            va="center",
            linespacing=0.9,
            bbox=dict(boxstyle="round,pad=0.14", fc="black", ec="none", alpha=0.80),
        )

    assigned_n = sum(
        row["assignment_status"] in {"assigned", "assigned_max_overlap"}
        for row in instance_rows
    )

    ax.set_title(
        f"{image_name} | cristae IDs (multiline, auto-offset) | counted={assigned_n} | "
        f"white=counted, red=invalid class, cyan=no mito, magenta=other"
    )
    ax.axis("off")
    fig.tight_layout()
    fig.savefig(path, dpi=PNG_DPI, bbox_inches="tight")
    plt.close(fig)


# =============================================================================
# CSV
# =============================================================================

def build_output_dataframe(all_rows: list[dict]) -> pd.DataFrame:
    ordered_cols = (
        ["image_name", "mitochondrion_id", "centroid_x", "centroid_y", "area_px"]
        + [f"class_{cls}" for cls in VALID_CLASSES]
        + ["total_cristae"]
    )

    df = pd.DataFrame(all_rows)

    for col in ordered_cols:
        if col not in df.columns:
            numeric_defaults = {
                "mitochondrion_id",
                "area_px",
                "total_cristae",
            }
            df[col] = 0 if col.startswith("class_") or col in numeric_defaults else ""

    df = df[ordered_cols]
    df.sort_values(
        by=["image_name", "mitochondrion_id"],
        ascending=[True, True],
        inplace=True,
        ignore_index=True,
    )
    return df


def build_instance_dataframe(instance_rows: list[dict]) -> pd.DataFrame:
    ordered_cols = [
        "image_name",
        "crista_visual_id",
        "instance_label_value",
        "decoded_class",
        "area_px",
        "centroid_x",
        "centroid_y",
        "assigned_mito_id",
        "assignment_status",
        "overlap_details",
    ]
    df = pd.DataFrame(instance_rows)
    for col in ordered_cols:
        if col not in df.columns:
            df[col] = ""
    return df[ordered_cols].sort_values(
        by=["crista_visual_id"], ascending=[True], ignore_index=True
    )


# =============================================================================
# MAIN PROCESSING
# =============================================================================

def process_one_pair(
    stem: str,
    mito_path: Path,
    cristae_path: Path,
    output_dir: Path,
    logger: logging.Logger,
) -> tuple[list[dict], list[dict]]:
    logger.info("=" * 100)
    logger.info(f"PROCESSING: {stem}")
    logger.info(f"MITO    : {mito_path}")
    logger.info(f"CRISTAE : {cristae_path}")

    image_out_dir = output_dir / stem
    image_out_dir.mkdir(parents=True, exist_ok=True)

    mito_img = read_single_image(mito_path)
    cristae_img = read_single_image(cristae_path)

    logger.info(f"Mitochondrial image: shape={mito_img.shape}, dtype={mito_img.dtype}")
    logger.info(f"Cristae image       : shape={cristae_img.shape}, dtype={cristae_img.dtype}")

    if mito_img.shape != cristae_img.shape:
        raise ValueError(
            "Paired image dimensions do not match: "
            f"mito={mito_img.shape}, cristae={cristae_img.shape}"
        )

    mito_binary_raw = make_mito_binary_mask(mito_img)
    mito_pixel_count_raw = int(mito_binary_raw.sum())
    logger.info(f"Mitochondrial pixels in the original mask: {mito_pixel_count_raw}")

    mito_binary_filled, added_hole_pixels = fill_holes_in_mito_mask(mito_binary_raw)
    mito_pixel_count_filled = int(mito_binary_filled.sum())

    logger.info(f"Pixels added by hole filling: {added_hole_pixels}")
    logger.info(f"Mitochondrial pixels after hole filling: {mito_pixel_count_filled}")

    mito_labels, mito_info, mito_filter_stats = relabel_mito_left_to_right_then_top_to_bottom(
        mito_binary_filled, logger
    )

    if len(mito_info) == 0:
        logger.warning(
            f"{stem}: no mitochondria remained after the area filter "
            f"(MIN_MITO_AREA_PX={MIN_MITO_AREA_PX})."
        )
    else:
        logger.info(f"{stem}: relabelled mitochondrial IDs: 1..{len(mito_info)}")

    cristae_labels = convert_cristae_to_int_labels(cristae_img, logger)
    positive_cristae_px = int(np.sum(cristae_labels > 0))
    logger.info(f"Non-zero cristae pixels: {positive_cristae_px}")

    instance_rows, stats = analyze_cristae_instances(
        cristae_labels=cristae_labels,
        mito_labels=mito_labels,
        image_name=stem,
        logger=logger,
    )

    mito_count_rows = build_mito_count_rows(
        mito_info=mito_info,
        instance_rows=instance_rows,
        image_name=stem,
    )

    logger.info(
        "Mitochondrial statistics | "
        f"detected_before_filter={mito_filter_stats['total_detected_before_filter']} | "
        f"removed_small={mito_filter_stats['removed_small_mitos']} | "
        f"kept_after_filter={mito_filter_stats['kept_after_filter']}"
    )

    logger.info(
        f"Instance statistics | unique={stats['unique_instance_values']} | "
        f"assigned={stats['assigned_instances']} | "
        f"invalid_class={stats['skipped_invalid_class']} | "
        f"multi_overlap={stats['multi_overlap_instances']} | "
        f"zero_overlap={stats['zero_overlap_instances']}"
    )

    total_cristae_image = sum(r["total_cristae"] for r in mito_count_rows)
    logger.info(f"Total counted cristae in the image: {total_cristae_image}")

    instance_df = build_instance_dataframe(instance_rows)
    instance_csv_path = image_out_dir / f"{stem}__cristae_instance_table.csv"
    instance_df.to_csv(instance_csv_path, index=False, header=True, encoding="utf-8")
    logger.info(f"Saved instance table: {instance_csv_path}")

    if SAVE_MITO_LABEL_TIF:
        save_mito_label_tif(
            image_out_dir / f"{stem}__mitochondria_labels.tif",
            mito_labels,
            logger,
        )

    save_mito_id_png(
        image_out_dir / f"{stem}__mitochondria_ids.png",
        mito_binary_filled,
        mito_labels,
        mito_info,
        stem,
    )

    save_cristae_overlay_png(
        image_out_dir / f"{stem}__cristae_overlay.png",
        mito_binary_filled,
        mito_labels,
        mito_info,
        cristae_labels,
        stem,
    )

    save_cristae_class_map_png(
        image_out_dir / f"{stem}__cristae_class_map.png",
        cristae_labels,
        stem,
    )

    save_cristae_ids_png(
        image_out_dir / f"{stem}__cristae_ids.png",
        mito_binary_filled,
        mito_labels,
        instance_rows,
        cristae_labels,
        stem,
    )

    logger.info(f"Saved image-level QC outputs to: {image_out_dir}")
    return mito_count_rows, instance_rows


def main(argv: list[str] | None = None) -> None:
    args = parse_args(argv)
    configure_from_args(args)
    require_runtime_dependencies()

    mito_dir = args.mito_dir
    cristae_dir = args.cristae_dir
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    run_id = args.run_id or datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = output_dir / f"run_log_{run_id}.txt"
    logger = setup_logging(log_file)

    logger.info("START")
    logger.info(f"MITO_DIR    = {mito_dir}")
    logger.info(f"CRISTAE_DIR = {cristae_dir}")
    logger.info(f"OUTPUT_DIR  = {output_dir}")
    logger.info(f"RUN_ID = {run_id}")
    logger.info(f"VALID_CLASSES = {VALID_CLASSES}")
    logger.info(f"MIN_MITO_AREA_PX = {MIN_MITO_AREA_PX}")
    logger.info(f"SAVE_MITO_LABEL_TIF_AS_UINT8 = {SAVE_MITO_LABEL_TIF_AS_UINT8}")
    logger.info(f"CRISTAE_LABEL_COLLISION_MIN_DIST_PX = {CRISTAE_LABEL_COLLISION_MIN_DIST_PX}")
    logger.info(f"CRISTAE_LABEL_OFFSET_STEP_PX = {CRISTAE_LABEL_OFFSET_STEP_PX}")
    logger.info(f"CRISTAE_LABEL_MAX_RING = {CRISTAE_LABEL_MAX_RING}")
    logger.info(f"CRISTAE_LABEL_DRAW_CONNECTOR = {CRISTAE_LABEL_DRAW_CONNECTOR}")

    if not mito_dir.is_dir():
        raise FileNotFoundError(f"Mitochondrial mask directory does not exist: {mito_dir}")
    if not cristae_dir.is_dir():
        raise FileNotFoundError(f"Cristae mask directory does not exist: {cristae_dir}")

    pairs = collect_pairs(
        mito_dir,
        cristae_dir,
        logger,
        fail_on_unpaired=args.fail_on_unpaired,
    )

    if not pairs:
        raise ValueError("No stem-matched .tif/.tiff image pairs were found.")

    all_rows: list[dict] = []
    all_instance_rows: list[dict] = []
    failed_pairs: list[dict] = []

    for idx, (stem, mito_path, cristae_path) in enumerate(pairs, start=1):
        logger.info("")
        logger.info(f"[{idx}/{len(pairs)}] {stem}")

        try:
            mito_rows, instance_rows = process_one_pair(
                stem,
                mito_path,
                cristae_path,
                output_dir,
                logger,
            )
            all_rows.extend(mito_rows)
            all_instance_rows.extend(instance_rows)
        except Exception as e:
            logger.exception(f"Failed to process pair {stem}: {e}")
            failed_pairs.append(
                {
                    "image_name": stem,
                    "mito_file": mito_path.name,
                    "cristae_file": cristae_path.name,
                    "error": str(e),
                }
            )

    if all_rows:
        df = build_output_dataframe(all_rows)

        csv_path = output_dir / f"cristae_counts_per_mito_{run_id}.csv"
        df.to_csv(csv_path, index=False, header=True, encoding="utf-8")
        logger.info(f"Saved main mitochondrial CSV: {csv_path}")
        logger.info(f"Rows in main CSV: {len(df)}")
        logger.info(f"Main CSV columns: {list(df.columns)}")
    else:
        logger.warning(
            "The main mitochondrial CSV was not created because no mitochondria "
            "remained after filtering."
        )

    if all_rows:
        df = build_output_dataframe(all_rows)
        summary_agg = {
            "mitochondria_count": ("mitochondrion_id", "count"),
            "total_cristae": ("total_cristae", "sum"),
        }
        for cls in VALID_CLASSES:
            summary_agg[f"class_{cls}"] = (f"class_{cls}", "sum")

        summary = df.groupby("image_name", as_index=False).agg(**summary_agg)
        summary_path = output_dir / f"cristae_counts_image_summary_{run_id}.csv"
        summary.to_csv(summary_path, index=False, header=True, encoding="utf-8")
        logger.info(f"Saved image-level summary: {summary_path}")
        logger.info(f"Summary CSV columns: {list(summary.columns)}")

    if all_instance_rows:
        all_instance_df = build_instance_dataframe(all_instance_rows)
        all_instances_csv = output_dir / f"all_cristae_instances_{run_id}.csv"
        all_instance_df.to_csv(all_instances_csv, index=False, header=True, encoding="utf-8")
        logger.info(f"Saved global cristae-instance table: {all_instances_csv}")

    if failed_pairs:
        failed_df = pd.DataFrame(failed_pairs)
        failed_csv = output_dir / f"failed_pairs_{run_id}.csv"
        failed_df.to_csv(failed_csv, index=False, header=True, encoding="utf-8")
        logger.warning(f"Failed image pairs: {len(failed_pairs)}")
        logger.warning(f"Saved failed-pair table: {failed_csv}")
    else:
        logger.info("All paired images completed without a fatal error.")

    logger.info("END")

    if failed_pairs and not args.allow_partial:
        raise RuntimeError(
            f"{len(failed_pairs)} image pair(s) failed; see {failed_csv}. "
            "Use --allow-partial only when partial completion is intentional."
        )


if __name__ == "__main__":
    main()
