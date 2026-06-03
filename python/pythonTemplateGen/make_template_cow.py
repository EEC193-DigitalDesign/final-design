#!/usr/bin/env python3
"""
make_template_cow.py
====================

OpenCV-based cow template generator for the Sobel matched-filter design.

Default flow:
    objects/cow/cowSide.jpg
        -> rtl/object_detection/templates/cow_edge_template_64.vh
        -> objects/cow_64_64tap/debug images + metadata

Run from the project root:
    python3 make_template_cow.py

Common tuning:
    python3 make_template_cow.py --edge-threshold 55 --crop-mode foreground

Notes:
- Uses OpenCV for crop/resize/grayscale/Sobel/dilation.
- Positive taps are selected from Sobel edge pixels, spread over the cow's
  bounding box so the template is not dominated by one high-contrast region.
- Negative taps are quiet guard pixels outside the edge band, useful for
  rejecting background clutter.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import random
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import List, Tuple

import cv2
import numpy as np

# Keep these aligned with DE1_SOC_D8M_LB_RTL.v and sparse_template_matcher.v.
TEMPLATE_SIZE = 64
NUM_TAPS = 64
NEGATIVE_TAPS = round(NUM_TAPS * 0.19)
POSITIVE_TAPS = NUM_TAPS - NEGATIVE_TAPS
ROW_W = math.ceil(math.log2(TEMPLATE_SIZE))
COL_W = math.ceil(math.log2(TEMPLATE_SIZE))
WEIGHT_W = 8
POSITIVE_WEIGHT = 7
NEGATIVE_WEIGHT = -2


@dataclass(frozen=True)
class Tap:
    row: int
    col: int
    weight: int
    kind: str  # "pos" or "neg"


def resolve_project_root(user_root: str | None) -> Path:
    candidates: List[Path] = []
    if user_root:
        candidates.append(Path(user_root).expanduser())
    candidates.extend([Path.cwd(), Path(__file__).resolve().parent])

    for base in candidates:
        base = base.resolve()
        if (base / "rtl" / "object_detection" / "sparse_template_matcher.v").is_file():
            return base
    return Path.cwd().resolve()


def display_path(path: Path, project_root: Path | None = None) -> str:
    path = path.resolve()
    if project_root is not None:
        try:
            return path.relative_to(project_root.resolve()).as_posix()
        except ValueError:
            pass
    return path.as_posix()


def read_image_bgr(path: Path) -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if img is None:
        raise SystemExit(f"error: image not found or unreadable: {path}")
    return img


def square_crop(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    side = min(h, w)
    y0 = (h - side) // 2
    x0 = (w - side) // 2
    return img[y0:y0 + side, x0:x0 + side]


def foreground_crop(img: np.ndarray, pad_frac: float = 0.12) -> np.ndarray:
    """
    Crop around the cow using simple OpenCV foreground segmentation.

    This is intentionally lightweight: it finds pixels that differ from the
    border/background estimate, then crops to their bounding box with padding.
    It works well for the uploaded cow photo because the cow is on a plain wall.
    """
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    border = np.concatenate([
        gray[: max(1, h // 20), :].reshape(-1),
        gray[-max(1, h // 20):, :].reshape(-1),
        gray[:, : max(1, w // 20)].reshape(-1),
        gray[:, -max(1, w // 20):].reshape(-1),
    ])
    bg = int(np.median(border))
    diff = cv2.absdiff(gray, np.full_like(gray, bg))

    # Otsu usually catches the hand + cow. Morph close/open removes speckles.
    _thr, mask = cv2.threshold(diff, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel = np.ones((7, 7), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)

    num_labels, labels, stats, _centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if num_labels <= 1:
        return square_crop(img)

    # Keep large non-background components. This may include the hand, but the
    # following square crop plus edge tap spreading still centers the cow well.
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = np.where(areas >= max(200, 0.01 * h * w))[0] + 1
    if len(keep) == 0:
        keep = [int(np.argmax(areas)) + 1]

    ys, xs = np.where(np.isin(labels, keep))
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1

    pad = int(max(y1 - y0, x1 - x0) * pad_frac)
    y0 = max(0, y0 - pad)
    y1 = min(h, y1 + pad)
    x0 = max(0, x0 - pad)
    x1 = min(w, x1 + pad)

    # Expand to square around the crop center so resizing does not distort cow shape.
    cy = (y0 + y1) // 2
    cx = (x0 + x1) // 2
    side = max(y1 - y0, x1 - x0)
    half = side // 2
    y0 = max(0, cy - half)
    x0 = max(0, cx - half)
    y1 = min(h, y0 + side)
    x1 = min(w, x0 + side)
    y0 = max(0, y1 - side)
    x0 = max(0, x1 - side)
    return img[y0:y1, x0:x1]


def load_cow_gray(path: Path, size: int, crop_mode: str) -> np.ndarray:
    img = read_image_bgr(path)
    crop = foreground_crop(img) if crop_mode == "foreground" else square_crop(img)
    crop = cv2.resize(crop, (size, size), interpolation=cv2.INTER_AREA)
    return cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)


def sobel_magnitude(gray: np.ndarray) -> np.ndarray:
    """
    3x3 Sobel magnitude using |Gx| + |Gy|, scaled to 8-bit.
    Matches the hardware idea without hard-clamping raw Sobel to 255.
    """
    gx = cv2.Sobel(
        gray,
        cv2.CV_16S,
        1,
        0,
        ksize=3,
        borderType=cv2.BORDER_REPLICATE,
    )

    gy = cv2.Sobel(
        gray,
        cv2.CV_16S,
        0,
        1,
        ksize=3,
        borderType=cv2.BORDER_REPLICATE,
    )

    mag_raw = np.abs(gx).astype(np.int32) + np.abs(gy).astype(np.int32)

    # Approximate divide by 6:
    # 1/6 ~= 43/256 ~= 1/8 + 1/32 + 1/128 + 1/256
    mag_scaled = (
        (mag_raw >> 3) +
        (mag_raw >> 5) +
        (mag_raw >> 7) +
        (mag_raw >> 8)
    )

    mag = np.clip(mag_scaled, 0, 255).astype(np.uint8)
    return mag


def make_edge_mask(mag: np.ndarray, threshold: int, dilate_radius: int) -> np.ndarray:
    mask = (mag >= threshold).astype(np.uint8)
    if dilate_radius > 0:
        k = cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))
        mask = cv2.dilate(mask, k, iterations=dilate_radius)
    return mask.astype(bool)


def spread_pick(mask: np.ndarray, score: np.ndarray, want: int, min_sep: float) -> List[Tuple[int, int]]:
    """Pick high-score pixels while encouraging coverage across the template."""
    ys, xs = np.where(mask)
    if len(ys) == 0:
        return []

    center_y = float(np.mean(ys))
    center_x = float(np.mean(xs))
    angles = (np.arctan2(ys - center_y, xs - center_x) + 2.0 * np.pi) % (2.0 * np.pi)
    bins = max(want, 1)

    picked: List[Tuple[int, int]] = []
    used = set()

    # First pass: at most one strong pixel per angular bin.
    for b in range(bins):
        a0 = 2.0 * np.pi * b / bins
        a1 = 2.0 * np.pi * (b + 1) / bins
        idxs = np.where((angles >= a0) & (angles < a1))[0]
        if len(idxs) == 0:
            continue
        idxs = idxs[np.argsort(-score[ys[idxs], xs[idxs]].astype(np.int32))]
        for idx in idxs:
            y, x = int(ys[idx]), int(xs[idx])
            if (y, x) in used:
                continue
            if any((y - py) ** 2 + (x - px) ** 2 < min_sep ** 2 for py, px in picked):
                continue
            picked.append((y, x))
            used.add((y, x))
            break

    # Top up with remaining strongest pixels.
    order = np.argsort(-score[ys, xs].astype(np.int32))
    for idx in order:
        if len(picked) >= want:
            break
        y, x = int(ys[idx]), int(xs[idx])
        if (y, x) in used:
            continue
        if any((y - py) ** 2 + (x - px) ** 2 < min_sep ** 2 for py, px in picked):
            continue
        picked.append((y, x))
        used.add((y, x))

    return picked[:want]


def select_positive_taps(mag: np.ndarray, edge_mask: np.ndarray) -> List[Tap]:
    # Slight erosion removes thick blobs caused by dilation but keeps strong contours.
    candidates = edge_mask.copy()
    picked = spread_pick(candidates, mag, POSITIVE_TAPS, min_sep=2.0)
    return [Tap(row=y, col=x, weight=POSITIVE_WEIGHT, kind="pos") for y, x in picked]


def select_negative_taps(
    mag: np.ndarray,
    edge_mask: np.ndarray,
    pos_taps: List[Tap],
    neg_gap: int,
    rng: random.Random,
) -> List[Tap]:
    pos_mask = np.zeros_like(edge_mask, dtype=np.uint8)
    for tap in pos_taps:
        pos_mask[tap.row, tap.col] = 1

    k = cv2.getStructuringElement(cv2.MORPH_CROSS, (3, 3))
    forbidden = edge_mask.astype(np.uint8)
    if neg_gap > 0:
        forbidden = cv2.dilate(forbidden, k, iterations=neg_gap)
        pos_forbid = cv2.dilate(pos_mask, k, iterations=neg_gap)
        forbidden = np.maximum(forbidden, pos_forbid)

    quiet_level = max(8, int(mag.max()) // 8)
    quiet = (forbidden == 0) & (mag <= quiet_level)

    # Prefer quiet pixels near the cow crop but away from edges.
    edge_u8 = edge_mask.astype(np.uint8)
    if np.any(edge_u8):
        x, y, w, h = cv2.boundingRect(edge_u8)
        pad = max(2, neg_gap)
        roi = np.zeros_like(quiet, dtype=bool)
        roi[max(0, y - pad):min(TEMPLATE_SIZE, y + h + pad), max(0, x - pad):min(TEMPLATE_SIZE, x + w + pad)] = True
        quiet = quiet & roi

    ys, xs = np.where(quiet)
    chosen: List[Tuple[int, int]] = []
    if len(ys) > 0:
        jitter = np.array([rng.random() for _ in range(len(ys))])
        # prefer lower magnitude first; jitter makes deterministic tie-breaks
        order = np.lexsort((jitter, mag[ys, xs]))
        for idx in order:
            if len(chosen) >= NEGATIVE_TAPS:
                break
            yy, xx = int(ys[idx]), int(xs[idx])
            if any((yy - py) ** 2 + (xx - px) ** 2 < 25 for py, px in chosen):
                continue
            chosen.append((yy, xx))

    while len(chosen) < NEGATIVE_TAPS:
        chosen.append((0, 0))

    return [Tap(row=y, col=x, weight=NEGATIVE_WEIGHT, kind="neg") for y, x in chosen[:NEGATIVE_TAPS]]


def emit_template_vh(taps: List[Tap], image_path: Path, out_path: Path, project_root: Path | None = None) -> None:
    image_hash = hashlib.sha256(image_path.read_bytes()).hexdigest()[:16]
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    lines: List[str] = [
        "// Auto-generated cow sparse edge template for rtl/object_detection/score_tree.v",
        f"// Source image: {display_path(image_path, project_root)}",
        f"// Source SHA256: {image_hash}",
        f"// Generated: {now}",
        f"// Object: cow | Template: {TEMPLATE_SIZE}x{TEMPLATE_SIZE} | Num taps: {NUM_TAPS} | Tap format: {{row[{ROW_W-1}:0], col[{COL_W-1}:0], signed weight[7:0]}}",
        "// Located in rtl/object_detection/templates/ and included by score_tree.v",
        "",
    ]

    for i, tap in enumerate(taps):
        weight_hex = tap.weight & ((1 << WEIGHT_W) - 1)
        sign = "+" if tap.weight >= 0 else "-"
        lines.append(
            f"assign tap_data[{i:2d}] = "
            f"{{{ROW_W}'d{tap.row:<2d}, {COL_W}'d{tap.col:<2d}, {WEIGHT_W}'h{weight_hex:02X}}}; "
            f"// row={tap.row}, col={tap.col}, w={sign}{abs(tap.weight)} ({tap.kind})"
        )

    def emit_case_function(name: str, return_decl: str, values: List[str], default_value: str) -> None:
        lines.extend(["", f"function {return_decl} {name};", "    input integer idx;", "    begin", "        case (idx)"])
        for i, value in enumerate(values):
            lines.append(f"            {i:3d}: {name} = {value};")
        lines.append(f"            default: {name} = {default_value};")
        lines.extend(["        endcase", "    end", "endfunction"])

    emit_case_function("cow_tap_row", f"[{ROW_W-1}:0]", [f"{ROW_W}'d{tap.row}" for tap in taps], f"{ROW_W}'d0")
    emit_case_function("cow_tap_col", f"[{COL_W-1}:0]", [f"{COL_W}'d{tap.col}" for tap in taps], f"{COL_W}'d0")

    weight_values = []
    for tap in taps:
        weight_values.append(f"-{WEIGHT_W}'sd{abs(tap.weight)}" if tap.weight < 0 else f"{WEIGHT_W}'sd{tap.weight}")
    emit_case_function("cow_tap_weight", f"signed [{WEIGHT_W-1}:0]", weight_values, f"{WEIGHT_W}'sd0")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n")


def save_gray(arr: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), np.clip(arr, 0, 255).astype(np.uint8))


def save_overlay(gray: np.ndarray, taps: List[Tap], path: Path) -> None:
    img = cv2.cvtColor(gray, cv2.COLOR_GRAY2BGR)
    for tap in taps:
        color = (0, 255, 0) if tap.kind == "pos" else (0, 0, 255)
        cv2.circle(img, (tap.col, tap.row), 1, color, thickness=-1)
    img = cv2.resize(img, (gray.shape[1] * 8, gray.shape[0] * 8), interpolation=cv2.INTER_NEAREST)
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), img)


def write_meta(path: Path, image_path: Path, taps: List[Tap], args: argparse.Namespace, project_root: Path | None = None) -> None:
    meta = {
        "mode": "cow_opencv_sobel_sparse_matcher",
        "image": display_path(image_path, project_root),
        "image_sha256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
        "template_size": TEMPLATE_SIZE,
        "num_taps": NUM_TAPS,
        "positive_taps": POSITIVE_TAPS,
        "negative_taps": NEGATIVE_TAPS,
        "positive_weight": POSITIVE_WEIGHT,
        "negative_weight": NEGATIVE_WEIGHT,
        "edge_threshold": args.edge_threshold,
        "dilate": args.dilate,
        "neg_gap": args.neg_gap,
        "seed": args.seed,
        "crop_mode": args.crop_mode,
        "taps": [asdict(tap) for tap in taps],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(meta, indent=2) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a 64x64/64-tap OpenCV Sobel matched-filter cow template.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--project-root", default=None, help="Quartus project root. Auto-detected when omitted.")
    parser.add_argument("--image", default=None, help="Cow image. Defaults to <project-root>/objects/cow/cowSide.jpg.")
    parser.add_argument(
        "--template-out",
        default=None,
        help="Output .vh. Defaults to <project-root>/rtl/object_detection/templates/cow_edge_template_64.vh.",
    )
    parser.add_argument("--crop-mode", choices=["foreground", "center"], default="foreground", help="How to crop the cow image before resizing.")
    parser.add_argument("--edge-threshold", type=int, default=55, help="Sobel magnitude threshold for candidate edges.")
    parser.add_argument("--dilate", type=int, default=1, help="Candidate edge dilation radius.")
    parser.add_argument("--neg-gap", type=int, default=3, help="Minimum guard-tap distance from positive taps/edges.")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic seed for guard-tap tie breaks.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root = resolve_project_root(args.project_root)
    image_path = Path(args.image).expanduser().resolve() if args.image else (project_root / "objects" / "cow" / "cowSide.jpg")
    template_path = Path(args.template_out).expanduser().resolve() if args.template_out else (
        project_root / "rtl" / "object_detection" / "templates" / "cow_edge_template_64.vh"
    )

    rng = random.Random(args.seed)
    gray = load_cow_gray(image_path, TEMPLATE_SIZE, args.crop_mode)
    mag = sobel_magnitude(gray)
    edge_mask = make_edge_mask(mag, args.edge_threshold, args.dilate)

    pos_taps = select_positive_taps(mag, edge_mask)
    neg_taps = select_negative_taps(mag, edge_mask, pos_taps, args.neg_gap, rng)
    taps = pos_taps + neg_taps

    if len(taps) != NUM_TAPS:
        raise RuntimeError(f"internal error: expected {NUM_TAPS} taps, got {len(taps)}")

    emit_template_vh(taps, image_path, template_path, project_root)

    docs_dir = project_root / "objects" / f"cow_{TEMPLATE_SIZE}_{NUM_TAPS}tap"
    save_gray(gray, docs_dir / f"cow_dbg_01_gray_{TEMPLATE_SIZE}.png")
    save_gray(mag, docs_dir / f"cow_dbg_02_sobel_mag_{TEMPLATE_SIZE}.png")
    save_gray((edge_mask * 255).astype(np.uint8), docs_dir / f"cow_dbg_03_edge_mask_{TEMPLATE_SIZE}.png")
    save_overlay(gray, taps, docs_dir / f"cow_{NUM_TAPS}tap_debug_overlay.png")
    write_meta(docs_dir / f"cow_{NUM_TAPS}tap_template_meta.json", image_path, taps, args, project_root)

    print(f"wrote {template_path}")
    print(f"wrote {docs_dir / f'cow_{NUM_TAPS}tap_debug_overlay.png'}")
    print(f"wrote {docs_dir / f'cow_{NUM_TAPS}tap_template_meta.json'}")
    print(f"done: TEMPLATE_SIZE={TEMPLATE_SIZE}, MF_NUM_TAPS={NUM_TAPS}, ROW_W={ROW_W}, COL_W={COL_W}")


if __name__ == "__main__":
    main()
