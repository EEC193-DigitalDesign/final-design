#!/usr/bin/env python3
"""
make_templates.py
=================

Donut-only template generator for the current Sobel matched-filter design.

This script intentionally does one job:

    objects/donut.png  ->  rtl/object_detection/templates/donut_edge_template_32.vh

It matches the active hardware in this cleaned project:

    D8M camera -> grayscale downsample -> sobel3x3_stream ->
    sparse_template_matcher -> detection_logic -> VGA overlay

Current fixed design assumptions:
    TEMPLATE_SIZE = 32
    NUM_TAPS      = 64
    ROW_W/COL_W   = 5
    WEIGHT_W      = 8

Run from the project root:

    python3 make_templates.py

Optional tuning knobs are limited to the things that matter for the donut Sobel
matched filter right now: Sobel edge threshold, dilation, negative guard gap,
and random seed for deterministic guard-tap placement.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import math
import random
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable, List, Tuple

import numpy as np
from PIL import Image, ImageDraw

# Keep these aligned with DE1_SOC_D8M_LB_RTL.v and sparse_template_matcher.v.
TEMPLATE_SIZE = 32
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
    """Find the Quartus project root without depending on the current shell."""
    candidates: List[Path] = []
    if user_root:
        candidates.append(Path(user_root).expanduser())
    candidates.extend([Path.cwd(), Path(__file__).resolve().parent])

    for base in candidates:
        base = base.resolve()
        if (base / "rtl" / "object_detection" / "sparse_template_matcher.v").is_file():
            return base

    # Fall back to cwd so the error message points at the expected layout.
    return Path.cwd().resolve()


def composite_rgba_on_white(img: Image.Image) -> Image.Image:
    """Avoid false Sobel edges from transparent pixels becoming black."""
    if img.mode == "RGBA":
        white = Image.new("RGBA", img.size, (255, 255, 255, 255))
        img = Image.alpha_composite(white, img)
    return img.convert("RGB")


def load_donut_square(path: Path, size: int = TEMPLATE_SIZE) -> np.ndarray:
    """Load the donut, center-crop to square, resize to the template grid."""
    img = composite_rgba_on_white(Image.open(path))
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    img = img.resize((size, size), Image.Resampling.LANCZOS)
    return np.asarray(img, dtype=np.uint8)


def to_grayscale(rgb: np.ndarray) -> np.ndarray:
    """Integer BT.601 luma: same form usually used in FPGA RGB->Y blocks."""
    r = rgb[..., 0].astype(np.int32)
    g = rgb[..., 1].astype(np.int32)
    b = rgb[..., 2].astype(np.int32)
    y = (77 * r + 150 * g + 29 * b) >> 8
    return np.clip(y, 0, 255).astype(np.uint8)


def sobel_magnitude(gray: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """3x3 Sobel with |Gx|+|Gy| magnitude, matching sobel3x3_stream.v."""
    g = gray.astype(np.int32)
    p = np.pad(g, 1, mode="edge")
    gx = (
        -1 * p[:-2, :-2] + 1 * p[:-2, 2:]
        - 2 * p[1:-1, :-2] + 2 * p[1:-1, 2:]
        - 1 * p[2:, :-2] + 1 * p[2:, 2:]
    )
    gy = (
        -1 * p[:-2, :-2] - 2 * p[:-2, 1:-1] - 1 * p[:-2, 2:]
        + 1 * p[2:, :-2] + 2 * p[2:, 1:-1] + 1 * p[2:, 2:]
    )
    mag = np.abs(gx) + np.abs(gy)
    return gx, gy, np.clip(mag, 0, 255).astype(np.uint8)


def dilate(mask: np.ndarray, radius: int) -> np.ndarray:
    """Small 4-neighbor binary dilation used only for robust tap/guard spacing."""
    out = mask.astype(bool).copy()
    for _ in range(max(0, radius)):
        shifted = np.zeros_like(out)
        shifted[1:, :] |= out[:-1, :]
        shifted[:-1, :] |= out[1:, :]
        shifted[:, 1:] |= out[:, :-1]
        shifted[:, :-1] |= out[:, 1:]
        out |= shifted
    return out


def distance_from_mask(mask: np.ndarray) -> np.ndarray:
    """Cheap Manhattan distance to the nearest True pixel."""
    inf = mask.shape[0] + mask.shape[1]
    d = np.where(mask, 0, inf).astype(np.int32)
    h, w = d.shape

    for y in range(h):
        for x in range(w):
            if y > 0:
                d[y, x] = min(d[y, x], d[y - 1, x] + 1)
            if x > 0:
                d[y, x] = min(d[y, x], d[y, x - 1] + 1)

    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if y < h - 1:
                d[y, x] = min(d[y, x], d[y + 1, x] + 1)
            if x < w - 1:
                d[y, x] = min(d[y, x], d[y, x + 1] + 1)
    return d


def find_radial_split(edge_mask: np.ndarray) -> Tuple[float, float, float]:
    """
    Estimate inner/outer donut edge radii from edge pixels.

    The donut is centered in a 64x64 crop, so a radial split is more useful than
    the old generic object selector. It keeps taps distributed across both the
    outside contour and the hole contour.
    """
    cy = cx = (TEMPLATE_SIZE - 1) / 2.0
    ys, xs = np.where(edge_mask)
    if len(ys) == 0:
        return 11.0, 20.0, 28.0
    radii = np.sqrt((ys - cy) ** 2 + (xs - cx) ** 2)
    inner = float(np.percentile(radii, 28))
    split = float(np.percentile(radii, 55))
    outer = float(np.percentile(radii, 82))
    return inner, split, outer


def pick_by_angle(
    mag: np.ndarray,
    edge_mask: np.ndarray,
    want: int,
    radius_min: float,
    radius_max: float,
    already: Iterable[Tuple[int, int]],
) -> List[Tuple[int, int, int]]:
    """Pick strong edge pixels, evenly spread around the donut by angle."""
    cy = cx = (TEMPLATE_SIZE - 1) / 2.0
    yy, xx = np.indices(mag.shape)
    radii = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)
    angles = (np.arctan2(yy - cy, xx - cx) + 2.0 * np.pi) % (2.0 * np.pi)

    used = set(already)
    picked: List[Tuple[int, int, int]] = []
    min_sep = 2.0

    for bin_idx in range(want):
        a0 = (2.0 * np.pi * bin_idx) / want
        a1 = (2.0 * np.pi * (bin_idx + 1)) / want
        in_bin = edge_mask & (radii >= radius_min) & (radii <= radius_max) & (angles >= a0) & (angles < a1)
        ys, xs = np.where(in_bin)
        if len(ys) == 0:
            continue

        order = np.argsort(-mag[ys, xs].astype(np.int32))
        for idx in order:
            y, x = int(ys[idx]), int(xs[idx])
            if (y, x) in used:
                continue
            if any((y - py) ** 2 + (x - px) ** 2 < min_sep ** 2 for py, px, _ in picked):
                continue
            picked.append((y, x, int(mag[y, x])))
            used.add((y, x))
            break

    return picked


def top_up_positive_taps(
    mag: np.ndarray,
    edge_mask: np.ndarray,
    picked: List[Tuple[int, int, int]],
    want: int,
) -> List[Tuple[int, int, int]]:
    """Fill any empty angular bins with strongest remaining edge pixels."""
    used = {(y, x) for y, x, _ in picked}
    ys, xs = np.where(edge_mask)
    order = np.argsort(-mag[ys, xs].astype(np.int32))
    for idx in order:
        if len(picked) >= want:
            break
        y, x = int(ys[idx]), int(xs[idx])
        if (y, x) in used:
            continue
        if any((y - py) ** 2 + (x - px) ** 2 < 4 for py, px, _ in picked):
            continue
        picked.append((y, x, int(mag[y, x])))
        used.add((y, x))
    return picked[:want]


def select_positive_taps(mag: np.ndarray, edge_mask: np.ndarray) -> List[Tap]:
    inner_r, split_r, outer_r = find_radial_split(edge_mask)

    # Put a little more weight on the outside contour, but always keep the hole.
    inner_count = 15
    outer_count = POSITIVE_TAPS - inner_count

    picked: List[Tuple[int, int, int]] = []
    picked += pick_by_angle(
        mag,
        edge_mask,
        want=outer_count,
        radius_min=split_r,
        radius_max=TEMPLATE_SIZE,
        already=[],
    )
    picked += pick_by_angle(
        mag,
        edge_mask,
        want=inner_count,
        radius_min=0.0,
        radius_max=max(split_r, inner_r + 2.0),
        already=[(y, x) for y, x, _ in picked],
    )
    picked = top_up_positive_taps(mag, edge_mask, picked, POSITIVE_TAPS)

    return [Tap(row=y, col=x, weight=POSITIVE_WEIGHT, kind="pos") for y, x, _ in picked]


def pick_quiet_points_by_angle(
    quiet: np.ndarray,
    radii: np.ndarray,
    quota: int,
    target_radius: float,
    rng: random.Random,
    already: List[Tuple[int, int]],
    start_phase: float = 0.0,
) -> List[Tuple[int, int]]:
    """Pick quiet guard points with angular spread around the donut center."""
    if quota <= 0:
        return []

    cy = cx = (TEMPLATE_SIZE - 1) / 2.0
    yy, xx = np.indices(quiet.shape)
    angles = (np.arctan2(yy - cy, xx - cx) + 2.0 * np.pi + start_phase) % (2.0 * np.pi)
    chosen: List[Tuple[int, int]] = []
    used = set(already)

    for bin_idx in range(quota):
        a0 = (2.0 * np.pi * bin_idx) / quota
        a1 = (2.0 * np.pi * (bin_idx + 1)) / quota
        region = quiet & (angles >= a0) & (angles < a1)
        ys, xs = np.where(region)
        if len(ys) == 0:
            continue

        # Prefer the requested radius, with deterministic random tie-breaking.
        jitter = np.array([rng.random() for _ in range(len(ys))]) * 0.01
        score = np.abs(radii[ys, xs] - target_radius) + jitter
        for idx in np.argsort(score):
            y, x = int(ys[idx]), int(xs[idx])
            if (y, x) in used:
                continue
            if any((y - py) ** 2 + (x - px) ** 2 < 25 for py, px in already + chosen):
                continue
            chosen.append((y, x))
            used.add((y, x))
            break

    return chosen


def select_negative_taps(
    mag: np.ndarray,
    edge_mask: np.ndarray,
    pos_taps: List[Tap],
    neg_gap: int,
    rng: random.Random,
) -> List[Tap]:
    """
    Donut-specific negative guard taps.

    Guards are placed on quiet pixels away from Sobel edges: half inside the
    donut hole and half outside the donut. They penalize accidental background
    edges without overwhelming the positive Sobel-edge match.
    """
    inner_r, split_r, outer_r = find_radial_split(edge_mask)
    cy = cx = (TEMPLATE_SIZE - 1) / 2.0
    yy, xx = np.indices(mag.shape)
    radii = np.sqrt((yy - cy) ** 2 + (xx - cx) ** 2)

    pos_mask = np.zeros_like(edge_mask, dtype=bool)
    for tap in pos_taps:
        pos_mask[tap.row, tap.col] = True

    forbidden = dilate(edge_mask, neg_gap) | dilate(pos_mask, neg_gap)
    quiet = (~forbidden) & (mag <= max(8, int(mag.max()) // 8))

    hole_quota = NEGATIVE_TAPS // 2
    outside_quota = NEGATIVE_TAPS - hole_quota

    hole_region = quiet & (radii <= max(2.0, split_r - neg_gap))
    outside_region = quiet & (radii >= min(float(TEMPLATE_SIZE), outer_r + neg_gap))

    chosen: List[Tuple[int, int]] = []
    chosen += pick_quiet_points_by_angle(
        hole_region,
        radii,
        quota=hole_quota,
        target_radius=max(1.0, split_r * 0.35),
        rng=rng,
        already=chosen,
        start_phase=0.0,
    )
    chosen += pick_quiet_points_by_angle(
        outside_region,
        radii,
        quota=outside_quota,
        target_radius=min(float(TEMPLATE_SIZE), outer_r + neg_gap + 2.0),
        rng=rng,
        already=chosen,
        start_phase=np.pi / max(1, outside_quota),
    )

    # Fallback: nearest quiet pixels to any donut edge, still enforcing spread.
    if len(chosen) < NEGATIVE_TAPS:
        dist = distance_from_mask(edge_mask)
        ys, xs = np.where(quiet)
        order = np.lexsort((np.array([rng.random() for _ in range(len(ys))]), dist[ys, xs]))
        for idx in order:
            if len(chosen) >= NEGATIVE_TAPS:
                break
            y, x = int(ys[idx]), int(xs[idx])
            if (y, x) in chosen:
                continue
            if any((y - py) ** 2 + (x - px) ** 2 < 25 for py, px in chosen):
                continue
            chosen.append((y, x))

    while len(chosen) < NEGATIVE_TAPS:
        chosen.append((0, 0))

    return [Tap(row=y, col=x, weight=NEGATIVE_WEIGHT, kind="neg") for y, x in chosen[:NEGATIVE_TAPS]]



def display_path(path: Path, project_root: Path | None = None) -> str:
    """Use portable project-relative paths in generated comments when possible."""
    path = path.resolve()
    if project_root is not None:
        try:
            return path.relative_to(project_root.resolve()).as_posix()
        except ValueError:
            pass
    return path.as_posix()


def emit_template_vh(taps: List[Tap], image_path: Path, out_path: Path, project_root: Path | None = None) -> None:
    """Emit the exact include format expected by systolic_sparse_matcher.v."""
    image_hash = hashlib.sha256(image_path.read_bytes()).hexdigest()[:16]
    now = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")

    lines: List[str] = [
        "// Auto-generated donut sparse edge template for rtl/object_detection/score_tree.v",
        f"// Source image: {display_path(image_path, project_root)}",
        f"// Source SHA256: {image_hash}",
        f"// Generated: {now}",
        f"// Object: donut | Template: {TEMPLATE_SIZE}x{TEMPLATE_SIZE} | Num taps: {NUM_TAPS} | Tap format: {{row[{ROW_W-1}:0], col[{COL_W-1}:0], signed weight[7:0]}}",
        "// Located in rtl/object_detection/ and included by score_tree.v",
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

    def emit_case_function(name: str, return_decl: str, values: List[str]) -> None:
        lines.extend(["", f"function {return_decl} {name};", "    input integer idx;", "    begin", "        case (idx)"])
        for i, value in enumerate(values):
            lines.append(f"            {i:3d}: {name} = {value};")
        if return_decl.startswith("["):
            width = return_decl.strip()[1:].split(":", 1)[0]
            default_value = f"{int(width) + 1}'d0"
        else:
            default_value = "8'sd0"
        lines.append(f"            default: {name} = {default_value};")
        lines.extend(["        endcase", "    end", "endfunction"])

    emit_case_function("donut_tap_row", f"[{ROW_W-1}:0]", [f"{ROW_W}'d{tap.row}" for tap in taps])
    emit_case_function("donut_tap_col", f"[{ROW_W-1}:0]", [f"{COL_W}'d{tap.col}" for tap in taps])

    weight_values = []
    for tap in taps:
        if tap.weight < 0:
            weight_values.append(f"-{WEIGHT_W}'sd{abs(tap.weight)}")
        else:
            weight_values.append(f"{WEIGHT_W}'sd{tap.weight}")
    emit_case_function("donut_tap_weight", f"signed [{WEIGHT_W-1}:0]", weight_values)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text("\n".join(lines) + "\n")


def save_gray(arr: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).save(path)


def save_overlay(gray: np.ndarray, taps: List[Tap], path: Path) -> None:
    img = Image.fromarray(gray).convert("RGB")
    draw = ImageDraw.Draw(img)
    for tap in taps:
        fill = (0, 255, 0) if tap.kind == "pos" else (255, 40, 40)
        draw.point((tap.col, tap.row), fill=fill)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((gray.shape[1] * 8, gray.shape[0] * 8), Image.Resampling.NEAREST).save(path)


def write_meta(path: Path, image_path: Path, taps: List[Tap], edge_threshold: int, dilate_radius: int, neg_gap: int, seed: int, project_root: Path | None = None) -> None:
    meta = {
        "mode": "donut_sobel_sparse_matcher_only",
        "image": display_path(image_path, project_root),
        "image_sha256": hashlib.sha256(image_path.read_bytes()).hexdigest(),
        "template_size": TEMPLATE_SIZE,
        "num_taps": NUM_TAPS,
        "positive_taps": POSITIVE_TAPS,
        "negative_taps": NEGATIVE_TAPS,
        "positive_weight": POSITIVE_WEIGHT,
        "negative_weight": NEGATIVE_WEIGHT,
        "edge_threshold": edge_threshold,
        "dilate": dilate_radius,
        "neg_gap": neg_gap,
        "seed": seed,
        "taps": [asdict(tap) for tap in taps],
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(meta, indent=2) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the current 32x32/64-tap Sobel matched-filter donut template.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--project-root", default=None, help="Quartus project root. Auto-detected when omitted.")
    parser.add_argument("--image", default=None, help="Donut PNG. Defaults to <project-root>/objects/donut/donut.png.")
    parser.add_argument(
        "--template-out",
        default=None,
        help="Output .vh. Defaults to <project-root>/rtl/object_detection/templates/donut_edge_template_32.vh.",
    )
    parser.add_argument("--edge-threshold", type=int, default=40, help="Sobel magnitude threshold for candidate edges.")
    parser.add_argument("--dilate", type=int, default=1, help="Candidate edge dilation radius.")
    parser.add_argument("--neg-gap", type=int, default=4, help="Minimum guard-tap distance from positive taps/edges.")
    parser.add_argument("--seed", type=int, default=42, help="Deterministic seed for guard-tap tie breaks.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    project_root = resolve_project_root(args.project_root)
    image_path = Path(args.image).expanduser().resolve() if args.image else (project_root / "objects" / "donut" / "donut.png")
    template_path = Path(args.template_out).expanduser().resolve() if args.template_out else (
        project_root / "rtl" / "object_detection" / "templates" / "donut_edge_template_32.vh"
    )

    if not image_path.is_file():
        raise SystemExit(f"error: donut image not found: {image_path}")

    rng = random.Random(args.seed)
    rgb = load_donut_square(image_path, TEMPLATE_SIZE)
    gray = to_grayscale(rgb)
    _gx, _gy, mag = sobel_magnitude(gray)
    edge_mask = dilate(mag >= args.edge_threshold, args.dilate)

    pos_taps = select_positive_taps(mag, edge_mask)
    neg_taps = select_negative_taps(mag, edge_mask, pos_taps, args.neg_gap, rng)
    taps = pos_taps + neg_taps

    if len(taps) != NUM_TAPS:
        raise RuntimeError(f"internal error: expected {NUM_TAPS} taps, got {len(taps)}")

    emit_template_vh(taps, image_path, template_path, project_root)

    # Dynamic folder naming keeps your project root organized by size/tap count
    docs_dir = project_root / "objects" / f"donut_{TEMPLATE_SIZE}_{NUM_TAPS}tap"
    
    # 1. Parameterize debug image filenames using TEMPLATE_SIZE
    save_gray(gray, docs_dir / f"donut_dbg_01_gray_{TEMPLATE_SIZE}.png")
    save_gray(mag, docs_dir / f"donut_dbg_02_sobel_mag_{TEMPLATE_SIZE}.png")
    save_gray((edge_mask * 255).astype(np.uint8), docs_dir / f"donut_dbg_03_edge_mask_{TEMPLATE_SIZE}.png")
    
    # 2. Parameterize overlay and metadata using NUM_TAPS
    save_overlay(gray, taps, docs_dir / f"donut_{NUM_TAPS}tap_debug_overlay.png")
    write_meta(
        docs_dir / f"donut_{NUM_TAPS}tap_template_meta.json", 
        image_path, taps, args.edge_threshold, args.dilate, args.neg_gap, args.seed, project_root
    )

    # 3. Dynamic reporting
    print(f"wrote {template_path}")
    print(f"wrote {docs_dir / f'donut_{NUM_TAPS}tap_debug_overlay.png'}")
    print(f"wrote {docs_dir / f'donut_{NUM_TAPS}tap_template_meta.json'}")
    print(f"done: current design remains TEMPLATE_SIZE={TEMPLATE_SIZE}, MF_NUM_TAPS={NUM_TAPS}, ROW_W={ROW_W}, COL_W={COL_W}")


if __name__ == "__main__":
    main()
