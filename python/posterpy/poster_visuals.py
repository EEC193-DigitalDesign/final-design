#!/usr/bin/env python3
"""
poster_visuals.py

UHD poster visual exporter for the Sobel + sparse matched-filter donut detector.

This script is a Python/OpenCV mock of the display/debug path. It writes each
poster visual as its own 3840x2160 PNG instead of making one combined panel.

Default input files in the current folder:
  - fullframe.jpg   camera/frame photo
  - donut.png       donut source/template image

Default output folder:
  - poster_visuals_uhd/

Run:
  python poster_visuals.py

Useful options:
  python poster_visuals.py --fullframe fullframe.jpg --template donut.png
  python poster_visuals.py --output-dir poster_visuals_uhd
  python poster_visuals.py --tap-file donut_edge_template_32.vh
  python poster_visuals.py --no-card

Dependencies:
  pip install opencv-python numpy
"""

from __future__ import annotations

import argparse
import re
import zipfile
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Sequence, Tuple

import cv2
import numpy as np


# Display and detector geometry.
VGA_W = 640
VGA_H = 480
DS_W = 320
DS_H = 240
TEMPLATE_SIZE = 32

# UHD output geometry.
UHD_W = 3840
UHD_H = 2160

# Current 32x32 sparse template defaults: 32 taps, 26 positive, 6 negative.
# These match the posterpy 32x32 tap include generated for the current design.
POSITIVE_WEIGHT = 7
NEGATIVE_WEIGHT = -2
EMBEDDED_TAPS_32: Tuple[Tuple[int, int, int], ...] = (
    (16, 29, +7), (21, 28, +7), (25, 25, +7), (29, 16, +7),
    (28, 11, +7), (25,  6, +7), (21,  3, +7), (16,  1, +7),
    (10,  2, +7), ( 6,  5, +7), ( 4,  8, +7), ( 2, 11, +7),
    ( 1, 16, +7), ( 3, 22, +7), ( 5, 26, +7), (10, 29, +7),
    (16, 19, +7), (19, 17, +7), (19, 15, +7), (18, 13, +7),
    (16, 11, +7), (12,  6, +7), ( 9,  8, +7), (12, 15, +7),
    (13, 18, +7), (14, 20, +7),
    ( 0, 25, -2), (29,  3, -2), ( 5,  1, -2),
    ( 0,  6, -2), (26,  0, -2), (30, 27, -2),
)


@dataclass(frozen=True)
class Tap:
    row: int
    col: int
    weight: int

    @property
    def kind(self) -> str:
        return "pos" if self.weight >= 0 else "neg"


# ----------------------------- image utilities -----------------------------

def require_image(path: Path, flags: int = cv2.IMREAD_COLOR) -> np.ndarray:
    img = cv2.imread(str(path), flags)
    if img is None:
        raise FileNotFoundError(f"Could not read image: {path.resolve()}")
    return img


def composite_bgra_on_white(img: np.ndarray) -> np.ndarray:
    """Composite transparent PNGs on white so alpha does not create false edges."""
    if img.ndim == 3 and img.shape[2] == 4:
        bgr = img[:, :, :3].astype(np.float32)
        alpha = img[:, :, 3:4].astype(np.float32) / 255.0
        white = np.full_like(bgr, 255.0)
        out = bgr * alpha + white * (1.0 - alpha)
        return np.clip(out, 0, 255).astype(np.uint8)
    if img.ndim == 2:
        return cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    return img[:, :, :3].copy()


def center_crop_square(img_bgr: np.ndarray) -> np.ndarray:
    h, w = img_bgr.shape[:2]
    side = min(w, h)
    x0 = (w - side) // 2
    y0 = (h - side) // 2
    return img_bgr[y0:y0 + side, x0:x0 + side]


def fit_to_vga(img_bgr: np.ndarray) -> np.ndarray:
    return cv2.resize(img_bgr, (VGA_W, VGA_H), interpolation=cv2.INTER_AREA)


def make_template32(template_path: Path) -> np.ndarray:
    raw = require_image(template_path, cv2.IMREAD_UNCHANGED)
    bgr = composite_bgra_on_white(raw)
    square = center_crop_square(bgr)
    return cv2.resize(square, (TEMPLATE_SIZE, TEMPLATE_SIZE), interpolation=cv2.INTER_AREA)


def to_gray_bt601_bgr(img_bgr: np.ndarray) -> np.ndarray:
    """Integer BT.601 luma, matching common FPGA RGB-to-gray blocks."""
    b = img_bgr[:, :, 0].astype(np.int32)
    g = img_bgr[:, :, 1].astype(np.int32)
    r = img_bgr[:, :, 2].astype(np.int32)
    y = (77 * r + 150 * g + 29 * b) >> 8
    return np.clip(y, 0, 255).astype(np.uint8)


def sobel_magnitude_l1(gray: np.ndarray) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """3x3 Sobel with |Gx| + |Gy| magnitude, saturated to 8-bit."""
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


def to_bgr(img: np.ndarray) -> np.ndarray:
    if img.ndim == 2:
        return cv2.cvtColor(np.clip(img, 0, 255).astype(np.uint8), cv2.COLOR_GRAY2BGR)
    if img.shape[2] == 4:
        return composite_bgra_on_white(img)
    return img[:, :, :3].copy()


# ----------------------------- tap handling --------------------------------

def embedded_taps() -> List[Tap]:
    return [Tap(row=r, col=c, weight=w) for (r, c, w) in EMBEDDED_TAPS_32]


def parse_taps_from_vh(path: Path) -> List[Tap]:
    """Parse rows/cols/weights from a donut_edge_template_32.vh style include."""
    text = path.read_text(errors="ignore")
    taps: List[Tap] = []
    pattern = re.compile(
        r"assign\s+tap_data\[\s*\d+\s*\]\s*=\s*\{\s*\d+'d(\d+)\s*,\s*\d+'d(\d+)\s*,\s*8'h([0-9A-Fa-f]{2})\s*\}"
    )
    for match in pattern.finditer(text):
        row = int(match.group(1))
        col = int(match.group(2))
        raw = int(match.group(3), 16)
        weight = raw - 256 if raw >= 128 else raw
        taps.append(Tap(row=row, col=col, weight=weight))

    if not taps:
        raise ValueError(f"No tap_data assignments found in {path}")
    if any(t.row >= TEMPLATE_SIZE or t.col >= TEMPLATE_SIZE for t in taps):
        raise ValueError(
            f"{path} contains taps outside a {TEMPLATE_SIZE}x{TEMPLATE_SIZE} template. "
            "Use a 32x32 tap include, or omit --tap-file to use embedded taps."
        )
    return taps


def load_taps(tap_file: Optional[Path]) -> List[Tap]:
    if tap_file is not None and tap_file.exists():
        taps = parse_taps_from_vh(tap_file)
    else:
        taps = embedded_taps()
    if len(taps) != 32:
        print(f"Warning: expected 32 taps, got {len(taps)}")
    return taps


# ------------------------ matched-filter visualization ----------------------

def sparse_matched_filter_score_map(ds_sobel: np.ndarray, taps: Sequence[Tap]) -> Tuple[np.ndarray, Tuple[int, int], int]:
    """
    Sparse matched filter in downsampled coordinates.

    The score map is stored at the top-left template coordinate, matching the
    coordinate-indexed score RAM concept used by the current heatmap debug mode.
    """
    valid_h = DS_H - TEMPLATE_SIZE + 1
    valid_w = DS_W - TEMPLATE_SIZE + 1
    if ds_sobel.shape != (DS_H, DS_W):
        raise ValueError(f"Expected Sobel shape {(DS_H, DS_W)}, got {ds_sobel.shape}")

    src = ds_sobel.astype(np.int32)
    valid_scores = np.zeros((valid_h, valid_w), dtype=np.int32)
    for tap in taps:
        patch = src[tap.row:tap.row + valid_h, tap.col:tap.col + valid_w]
        valid_scores += patch * int(tap.weight)

    max_flat = int(np.argmax(valid_scores))
    best_y, best_x = np.unravel_index(max_flat, valid_scores.shape)
    best_score = int(valid_scores[best_y, best_x])

    full_scores = np.zeros((DS_H, DS_W), dtype=np.int32)
    full_scores[:valid_h, :valid_w] = valid_scores
    return full_scores, (int(best_x), int(best_y)), best_score


def max_to_shift(max_abs: int) -> int:
    """RTL-style auto-contrast shift: put the largest magnitude near 8 bits."""
    if max_abs <= 0:
        return 0
    bit_idx = int(max_abs).bit_length() - 1
    return max(0, bit_idx - 7)


def score_to_signed_heat(score_map: np.ndarray, score_shift: Optional[int]) -> Tuple[np.ndarray, np.ndarray, int]:
    """Return sign bit, 8-bit magnitude, and the display shift used."""
    score64 = score_map.astype(np.int64)
    abs_score = np.abs(score64)
    shift = max_to_shift(int(abs_score.max())) if score_shift is None else int(score_shift)
    mag = np.clip(abs_score >> shift, 0, 255).astype(np.uint8)
    neg = score64 < 0
    return neg, mag, shift


def scale3_sat_u16(value: np.ndarray) -> np.ndarray:
    scaled = value.astype(np.uint16) * 3
    return np.clip(scaled, 0, 255).astype(np.uint8)


def signed_heat_to_bgr(neg: np.ndarray, mag: np.ndarray) -> np.ndarray:
    """
    Match vga_debug_mux signed_heat_to_rgb colors:
      positive: black -> red -> yellow -> white
      negative: black -> blue -> cyan -> white
    """
    h = mag.astype(np.uint8)
    b = np.zeros_like(h, dtype=np.uint8)
    g = np.zeros_like(h, dtype=np.uint8)
    r = np.zeros_like(h, dtype=np.uint8)

    nonzero = h != 0
    pos = (~neg) & nonzero
    neg_mask = neg & nonzero

    low = h < 85
    mid = (h >= 85) & (h < 170)
    high = h >= 170

    m = pos & low
    r[m] = scale3_sat_u16(h[m])

    m = pos & mid
    r[m] = 255
    g[m] = scale3_sat_u16(h[m] - 85)

    m = pos & high
    r[m] = 255
    g[m] = 255
    b[m] = scale3_sat_u16(h[m] - 170)

    m = neg_mask & low
    b[m] = scale3_sat_u16(h[m])

    m = neg_mask & mid
    b[m] = 255
    g[m] = scale3_sat_u16(h[m] - 85)

    m = neg_mask & high
    b[m] = 255
    g[m] = 255
    r[m] = scale3_sat_u16(h[m] - 170)

    return cv2.merge([b, g, r])


def draw_detection_overlay(frame_bgr: np.ndarray, best_xy_ds: Tuple[int, int], box_thick: int = 3) -> np.ndarray:
    """VGA overlay style: green box and red cross, scaled from DS to VGA."""
    out = frame_bgr.copy()
    x0 = int(best_xy_ds[0] * 2)
    y0 = int(best_xy_ds[1] * 2)
    box_size = TEMPLATE_SIZE * 2
    x1 = min(out.shape[1] - 1, x0 + box_size - 1)
    y1 = min(out.shape[0] - 1, y0 + box_size - 1)
    x0 = max(0, x0)
    y0 = max(0, y0)

    cv2.rectangle(out, (x0, y0), (x1, y1), (0, 255, 0), max(1, box_thick))
    cx = x0 + box_size // 2
    cy = y0 + box_size // 2
    if 0 <= cy < out.shape[0]:
        cv2.line(out, (x0, cy), (x1, cy), (0, 0, 255), 1)
    if 0 <= cx < out.shape[1]:
        cv2.line(out, (cx, y0), (cx, y1), (0, 0, 255), 1)
    return out


def sparse_tap_visual(template_sobel: np.ndarray, taps: Sequence[Tap]) -> np.ndarray:
    """Draw positive and negative taps as exactly one source pixel per tap."""
    base = cv2.cvtColor(template_sobel, cv2.COLOR_GRAY2BGR)
    for tap in taps:
        # BGR: green for positive taps, red for negative guard taps.
        # Do not draw crosses/circles here: one tap = one 32x32 source pixel.
        color = (0, 255, 0) if tap.weight >= 0 else (0, 0, 255)
        row = int(np.clip(tap.row, 0, TEMPLATE_SIZE - 1))
        col = int(np.clip(tap.col, 0, TEMPLATE_SIZE - 1))
        base[row, col] = color
    return base


# ------------------------------ UHD card style ------------------------------

def draw_text(
    img: np.ndarray,
    text: str,
    org: Tuple[int, int],
    scale: float,
    color: Tuple[int, int, int],
    thickness: int,
) -> None:
    cv2.putText(img, text, org, cv2.FONT_HERSHEY_SIMPLEX, scale, color, thickness, cv2.LINE_AA)


def fit_image_to_box(img_bgr: np.ndarray, box_w: int, box_h: int, pixel_art: bool) -> np.ndarray:
    h, w = img_bgr.shape[:2]
    scale = min(box_w / float(w), box_h / float(h))
    new_w = max(1, int(round(w * scale)))
    new_h = max(1, int(round(h * scale)))
    interp = cv2.INTER_NEAREST if pixel_art else cv2.INTER_AREA
    return cv2.resize(img_bgr, (new_w, new_h), interpolation=interp)


def make_uhd_card(
    img: np.ndarray,
    title: str,
    subtitle: str,
    out_size: Tuple[int, int],
    pixel_art: bool = False,
    no_card: bool = False,
) -> np.ndarray:
    """Create a 3840x2160 poster-ready PNG with consistent title/subtitle."""
    bgr = to_bgr(img)
    out_w, out_h = out_size

    if no_card:
        return cv2.resize(bgr, (out_w, out_h), interpolation=cv2.INTER_NEAREST if pixel_art else cv2.INTER_AREA)

    canvas = np.full((out_h, out_w, 3), 248, dtype=np.uint8)

    # Subtle header and content card.
    header_h = 285
    cv2.rectangle(canvas, (0, 0), (out_w, header_h), (242, 242, 242), -1)
    cv2.line(canvas, (0, header_h), (out_w, header_h), (220, 220, 220), 4)

    left = 190
    draw_text(canvas, title, (left, 126), 2.75, (18, 18, 18), 6)
    draw_text(canvas, subtitle, (left, 205), 1.15, (82, 82, 82), 3)

    margin_x = 260
    margin_bottom = 135
    content_x0 = margin_x
    content_y0 = header_h + 95
    content_w = out_w - 2 * margin_x
    content_h = out_h - content_y0 - margin_bottom

    # Image area shadow/card.
    shadow_offset = 16
    cv2.rectangle(
        canvas,
        (content_x0 + shadow_offset, content_y0 + shadow_offset),
        (content_x0 + content_w + shadow_offset, content_y0 + content_h + shadow_offset),
        (225, 225, 225),
        -1,
    )
    cv2.rectangle(canvas, (content_x0, content_y0), (content_x0 + content_w, content_y0 + content_h), (255, 255, 255), -1)

    fitted = fit_image_to_box(bgr, content_w, content_h, pixel_art=pixel_art)
    fh, fw = fitted.shape[:2]
    x = content_x0 + (content_w - fw) // 2
    y = content_y0 + (content_h - fh) // 2
    canvas[y:y + fh, x:x + fw] = fitted

    cv2.rectangle(canvas, (x, y), (x + fw - 1, y + fh - 1), (30, 30, 30), 3)
    return canvas


def write_png(path: Path, img: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not cv2.imwrite(str(path), img):
        raise RuntimeError(f"Could not write {path.resolve()}")


# -------------------------------- main flow --------------------------------

def build_visuals(args: argparse.Namespace) -> Tuple[List[Path], dict]:
    out_dir = Path(args.output_dir)
    out_size = (int(args.uhd_width), int(args.uhd_height))

    frame_raw = require_image(Path(args.fullframe), cv2.IMREAD_COLOR)
    frame_vga = fit_to_vga(frame_raw)
    ds_bgr = cv2.resize(frame_vga, (DS_W, DS_H), interpolation=cv2.INTER_AREA)

    ds_gray = to_gray_bt601_bgr(ds_bgr)
    _gx, _gy, sobel_ds = sobel_magnitude_l1(ds_gray)

    template32 = make_template32(Path(args.template))
    template_gray = to_gray_bt601_bgr(template32)
    _tgx, _tgy, template_sobel = sobel_magnitude_l1(template_gray)

    taps = load_taps(Path(args.tap_file) if args.tap_file else None)
    pos_taps = sum(1 for t in taps if t.weight >= 0)
    neg_taps = len(taps) - pos_taps

    score_ds, best_xy_ds, best_score = sparse_matched_filter_score_map(sobel_ds, taps)
    heat_neg, heat_mag, shift_used = score_to_signed_heat(score_ds, args.score_shift)
    heat_bgr_ds = signed_heat_to_bgr(heat_neg, heat_mag)
    heat_bgr_vga = cv2.resize(heat_bgr_ds, (VGA_W, VGA_H), interpolation=cv2.INTER_NEAREST)

    detected_bgr = draw_detection_overlay(frame_vga, best_xy_ds, box_thick=3)
    sparse_vis = sparse_tap_visual(template_sobel, taps)

    # Display versions. Downsampled/Sobel/heatmap are intentionally pixel-nearest
    # so the poster shows the actual processing grid.
    visuals = [
        (
            "01_original_camera_input.png",
            frame_vga,
            "Original Camera Input",
            "640x480 Raw RGB",
            False,
        ),
        (
            "02_downsampled_image.png",
            ds_bgr,
            "Downsampled Image",
            "320x240 Processing Image",
            True,
        ),
        (
            "03_sobel_edge_filter.png",
            sobel_ds,
            "Sobel Edge Filter",
            "320x240 Sobel magnitude |Gx| + |Gy|",
            True,
        ),
        (
            "04_original_donut_image.png",
            template32,
            "Original Donut Image",
            "32x32 PNG",
            True,
        ),
        (
            "05_dense_template.png",
            template_sobel,
            "Dense Template",
            "32x32 Sobel edge magnitude",
            True,
        ),
        (
            "06_sparse_tap_template.png",
            sparse_vis,
            "Sparse Tap Template",
            "32 taps - 81% positive + 19% negative taps",
            True,
        ),
        (
            "07_signed_score_heatmap.png",
            heat_bgr_vga,
            "Signed Match Score Heatmap",
            "320x240 score RAM -> 640x480 VGA | red=match, blue=anti-match",
            True,
        ),
        (
            "08_detected_object.png",
            detected_bgr,
            "Detected Object",
            "Raw RGB + box overlay | max score selects top-left coordinate",
            False,
        ),
    ]

    written: List[Path] = []
    for filename, img, title, subtitle, pixel_art in visuals:
        card = make_uhd_card(
            img=img,
            title=title,
            subtitle=subtitle,
            out_size=out_size,
            pixel_art=pixel_art,
            no_card=bool(args.no_card),
        )
        path = out_dir / filename
        write_png(path, card)
        written.append(path)

    metadata = {
        "fullframe": str(Path(args.fullframe)),
        "template": str(Path(args.template)),
        "output_dir": str(out_dir),
        "uhd_size": [int(args.uhd_width), int(args.uhd_height)],
        "vga_size": [VGA_W, VGA_H],
        "processing_size": [DS_W, DS_H],
        "template_size": [TEMPLATE_SIZE, TEMPLATE_SIZE],
        "tap_count": len(taps),
        "positive_taps": pos_taps,
        "negative_taps": neg_taps,
        "positive_fraction_percent": round(100.0 * pos_taps / max(1, len(taps)), 1),
        "negative_fraction_percent": round(100.0 * neg_taps / max(1, len(taps)), 1),
        "score_shift": shift_used,
        "score_shift_mode": "auto" if args.score_shift is None else "manual",
        "best_match_top_left_ds": [int(best_xy_ds[0]), int(best_xy_ds[1])],
        "best_match_top_left_vga": [int(best_xy_ds[0] * 2), int(best_xy_ds[1] * 2)],
        "best_score": int(best_score),
        "files": [str(p) for p in written],
    }
    return written, metadata


def write_metadata(path: Path, metadata: dict) -> None:
    import json

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(metadata, indent=2) + "\n")


def zip_outputs(zip_path: Path, files: Sequence[Path], script_path: Path, meta_path: Path) -> None:
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for f in files:
            zf.write(f, arcname=f.name)
        zf.write(script_path, arcname="poster_visuals.py")
        if meta_path.exists():
            zf.write(meta_path, arcname=meta_path.name)


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Export each Sobel matched-filter poster visual as a UHD PNG.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--fullframe", default="fullframe.jpg", help="Input camera/full-frame image")
    p.add_argument("--template", default="donut.png", help="Input donut/template image")
    p.add_argument("--tap-file", default=None, help="Optional 32x32 donut_edge_template_32.vh tap include")
    p.add_argument("--output-dir", default="poster_visuals_uhd", help="Directory for individual UHD PNGs")
    p.add_argument("--uhd-width", type=int, default=UHD_W, help="Output PNG width")
    p.add_argument("--uhd-height", type=int, default=UHD_H, help="Output PNG height")
    p.add_argument(
        "--score-shift",
        type=int,
        default=None,
        help="Manual heatmap shift. Omit for RTL-style frame auto-contrast shift.",
    )
    p.add_argument("--no-card", action="store_true", help="Only scale the image to UHD; omit title/subtitle card")
    p.add_argument("--zip", default=None, help="Optional zip file path for all outputs plus this script")
    p.add_argument("--meta", default="poster_visuals_uhd/metadata.json", help="Metadata JSON output path")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    files, metadata = build_visuals(args)
    meta_path = Path(args.meta)
    write_metadata(meta_path, metadata)

    print("Wrote UHD poster visuals:")
    for path in files:
        print(f"  {path.resolve()}")
    print(f"Wrote metadata: {meta_path.resolve()}")
    print(
        "Detection: "
        f"DS top-left=({metadata['best_match_top_left_ds'][0]}, {metadata['best_match_top_left_ds'][1]}), "
        f"VGA top-left=({metadata['best_match_top_left_vga'][0]}, {metadata['best_match_top_left_vga'][1]}), "
        f"score={metadata['best_score']}, shift={metadata['score_shift']}"
    )

    if args.zip:
        zip_path = Path(args.zip)
        zip_outputs(zip_path, files, Path(__file__), meta_path)
        print(f"Wrote zip: {zip_path.resolve()}")


if __name__ == "__main__":
    main()
