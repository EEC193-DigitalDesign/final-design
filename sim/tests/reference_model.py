from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import os
import re

import cv2
import numpy as np


@dataclass(frozen=True)
class Tap:
    index: int
    row: int
    col: int
    weight: int


def env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)), 0)


def resolve_project_root() -> Path:
    env = os.environ.get("PROJECT_ROOT")
    if env:
        return Path(env).resolve()
    return Path(__file__).resolve().parents[2]


def resolve_template_path() -> Path:
    explicit = os.environ.get("TEMPLATE_VH")
    if explicit:
        p = Path(explicit)
        if p.is_file():
            return p.resolve()

    basename = os.environ.get("TEMPLATE_INCLUDE", "donut_edge_template_32.vh")
    root = resolve_project_root()
    candidates = [
        root / "rtl" / "object_detection" / "templates" / basename,
        root / "rtl" / "object_detection" / basename,  # legacy fallback
        Path(__file__).resolve().parent / "templates" / basename,
        Path(basename),
    ]
    for p in candidates:
        if p.is_file():
            return p.resolve()
    raise FileNotFoundError(f"Could not find template include {basename!r}; tried: {candidates}")


def _signed_from_hex(value: int, bits: int) -> int:
    sign = 1 << (bits - 1)
    mask = (1 << bits) - 1
    value &= mask
    return value - (1 << bits) if value & sign else value


def parse_template_vh(path: str | Path, expected_taps: int | None = None) -> list[Tap]:
    text = Path(path).read_text()
    pattern = re.compile(
        r"assign\s+tap_data\[\s*(\d+)\s*\]\s*=\s*\{\s*"
        r"(\d+)'d\s*(\d+)\s*,\s*"
        r"(\d+)'d\s*(\d+)\s*,\s*"
        r"(\d+)'h\s*([0-9a-fA-F]+)\s*\}\s*;"
    )
    taps: list[Tap] = []
    for m in pattern.finditer(text):
        idx = int(m.group(1))
        row = int(m.group(3))
        col = int(m.group(5))
        weight_bits = int(m.group(6))
        weight = _signed_from_hex(int(m.group(7), 16), weight_bits)
        taps.append(Tap(index=idx, row=row, col=col, weight=weight))

    taps.sort(key=lambda t: t.index)
    if expected_taps is not None and len(taps) != expected_taps:
        raise AssertionError(f"Template {path} has {len(taps)} taps; expected {expected_taps}")
    if [t.index for t in taps] != list(range(len(taps))):
        raise AssertionError(f"Template {path} tap indices are not contiguous from zero")
    return taps


def center_crop_square(img: np.ndarray) -> np.ndarray:
    h, w = img.shape[:2]
    side = min(h, w)
    y0 = (h - side) // 2
    x0 = (w - side) // 2
    return img[y0 : y0 + side, x0 : x0 + side]


def foreground_crop_square(img: np.ndarray, pad_frac: float = 0.12) -> np.ndarray:
    """Simple foreground crop matching make_template_cow1.py well enough for sim."""
    h, w = img.shape[:2]
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    border = np.concatenate(
        [
            gray[: max(1, h // 20), :].reshape(-1),
            gray[-max(1, h // 20) :, :].reshape(-1),
            gray[:, : max(1, w // 20)].reshape(-1),
            gray[:, -max(1, w // 20) :].reshape(-1),
        ]
    )
    bg = int(np.median(border))
    diff = cv2.absdiff(gray, np.full_like(gray, bg))
    _thr, mask = cv2.threshold(diff, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    kernel = np.ones((7, 7), np.uint8)
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)
    mask = cv2.morphologyEx(mask, cv2.MORPH_OPEN, kernel, iterations=1)

    num_labels, labels, stats, _centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if num_labels <= 1:
        return center_crop_square(img)

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


def load_bgr(path: Path, size: int, crop_mode: str = "center") -> np.ndarray:
    img = cv2.imread(str(path), cv2.IMREAD_UNCHANGED)
    if img is None:
        raise FileNotFoundError(f"Could not read template image: {path}")

    if img.ndim == 2:
        bgr = cv2.cvtColor(img, cv2.COLOR_GRAY2BGR)
    elif img.shape[2] == 4:
        raw_bgr = img[:, :, :3].astype(np.float32)
        alpha = img[:, :, 3:4].astype(np.float32) / 255.0
        bgr = np.round(raw_bgr * alpha + 255.0 * (1.0 - alpha)).astype(np.uint8)
    else:
        bgr = img[:, :, :3]

    crop = foreground_crop_square(bgr) if crop_mode == "foreground" else center_crop_square(bgr)
    return cv2.resize(crop, (size, size), interpolation=cv2.INTER_LANCZOS4)


def bgr_to_hardware_gray(bgr: np.ndarray) -> np.ndarray:
    b = bgr[:, :, 0].astype(np.int32)
    g = bgr[:, :, 1].astype(np.int32)
    r = bgr[:, :, 2].astype(np.int32)
    return np.clip((77 * r + 150 * g + 29 * b) >> 8, 0, 255).astype(np.uint8)


def sobel_magnitude(gray: np.ndarray) -> np.ndarray:
    kx = np.array([[-1, 0, 1], [-2, 0, 2], [-1, 0, 1]], dtype=np.int16)
    ky = np.array([[-1, -2, -1], [0, 0, 0], [1, 2, 1]], dtype=np.int16)
    src = gray.astype(np.int16)
    gx = cv2.filter2D(src, cv2.CV_16S, kx, borderType=cv2.BORDER_REPLICATE)
    gy = cv2.filter2D(src, cv2.CV_16S, ky, borderType=cv2.BORDER_REPLICATE)
    return np.clip(np.abs(gx.astype(np.int32)) + np.abs(gy.astype(np.int32)), 0, 255).astype(np.uint8)


def resolve_template_image_path() -> Path | None:
    explicit = os.environ.get("TEMPLATE_IMAGE")
    if explicit:
        p = Path(explicit)
        if p.is_file():
            return p.resolve()

    root = resolve_project_root()
    obj = os.environ.get("OBJECT_NAME", "donut").lower()
    candidates: list[Path] = []
    if obj == "cow":
        candidates.extend(
            [
                root / "objects" / "cow" / "cowSide.jpg",
                root / "objects" / "cow" / "cowSide.png",
            ]
        )
    elif obj == "donut":
        candidates.extend(
            [
                root / "objects" / "donut" / "donut.png",
                root / "objects" / "donut.png",
                root / "python" / "posterpy" / "donut.png",
            ]
        )

    candidates.extend(
        [
            root / "objects" / obj / f"{obj}.png",
            root / "objects" / obj / f"{obj}.jpg",
            root / "objects" / f"{obj}.png",
            root / "objects" / f"{obj}.jpg",
        ]
    )
    for p in candidates:
        if p.is_file():
            return p.resolve()
    return None


def build_template_feature(template_size: int) -> np.ndarray:
    feature_image = os.environ.get("TEMPLATE_FEATURE_IMAGE")
    if feature_image:
        p = Path(feature_image)
        if p.is_file():
            img = cv2.imread(str(p), cv2.IMREAD_GRAYSCALE)
            if img is None:
                raise FileNotFoundError(f"Could not read TEMPLATE_FEATURE_IMAGE: {p}")
            return cv2.resize(img, (template_size, template_size), interpolation=cv2.INTER_NEAREST).astype(np.uint8)

    image = resolve_template_image_path()
    if image is not None:
        crop_mode = os.environ.get("TEMPLATE_CROP_MODE", "center")
        return sobel_magnitude(bgr_to_hardware_gray(load_bgr(image, template_size, crop_mode=crop_mode)))

    # Fallback for isolated sim-folder testing: deterministic ring-like edge image.
    y, x = np.ogrid[:template_size, :template_size]
    c = (template_size - 1) / 2.0
    r = np.sqrt((x - c) ** 2 + (y - c) ** 2)
    ring = ((r > template_size * 0.24) & (r < template_size * 0.39)).astype(np.uint8) * 255
    return ring


def make_feature_frame(width: int, height: int, template_size: int, object_x: int, object_y: int) -> np.ndarray:
    if width < template_size + 1 or height < template_size + 1:
        raise ValueError(f"Frame {width}x{height} is too small for template_size={template_size}")
    if object_x < 0 or object_y < 0 or object_x + template_size > width or object_y + template_size > height:
        raise ValueError(
            f"Object top-left ({object_x},{object_y}) with size {template_size} does not fit in {width}x{height}"
        )

    yy, xx = np.indices((height, width))
    frame = ((3 * xx + 5 * yy) % 7).astype(np.uint8)
    patch = build_template_feature(template_size)
    frame[object_y : object_y + template_size, object_x : object_x + template_size] = patch
    return frame


def score_at_bottom_right(feature: np.ndarray, taps: list[Tap], template_size: int, x_br: int, y_br: int) -> int:
    top = y_br - template_size + 1
    left = x_br - template_size + 1
    acc = 0
    for tap in taps:
        acc += int(feature[top + tap.row, left + tap.col]) * int(tap.weight)
    return int(acc)


def reference_scores(feature: np.ndarray, taps: list[Tap], template_size: int) -> dict[tuple[int, int], int]:
    h, w = feature.shape
    out: dict[tuple[int, int], int] = {}
    for y in range(template_size - 1, h):
        for x in range(template_size - 1, w):
            out[(x, y)] = score_at_bottom_right(feature, taps, template_size, x, y)
    return out


def write_debug_images(output_dir: str | Path, feature: np.ndarray, ref_scores: dict[tuple[int, int], int], observed: dict[tuple[int, int], int]) -> None:
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(out / "feature_frame.png"), feature)

    if ref_scores:
        xs = [x for x, _ in ref_scores.keys()]
        ys = [y for _, y in ref_scores.keys()]
        x0, x1 = min(xs), max(xs)
        y0, y1 = min(ys), max(ys)
        out_w = x1 - x0 + 1
        out_h = y1 - y0 + 1

        ref_img = np.zeros((out_h, out_w), dtype=np.int32)
        dut_img = np.zeros((out_h, out_w), dtype=np.int32)
        for (x, y), score in ref_scores.items():
            ref_img[y - y0, x - x0] = score
        for (x, y), score in observed.items():
            if x0 <= x <= x1 and y0 <= y <= y1:
                dut_img[y - y0, x - x0] = score

        mn = min(int(ref_img.min()), int(dut_img.min()))
        mx = max(int(ref_img.max()), int(dut_img.max()), mn + 1)
        ref_norm = ((ref_img - mn) * 255 // (mx - mn)).astype(np.uint8)
        dut_norm = ((dut_img - mn) * 255 // (mx - mn)).astype(np.uint8)
        cv2.imwrite(str(out / "reference_score_map.png"), ref_norm)
        cv2.imwrite(str(out / "dut_score_map.png"), dut_norm)
        cv2.imwrite(str(out / "score_absdiff.png"), cv2.absdiff(ref_norm, dut_norm))

        (out / "score_map_geometry.txt").write_text(
            "score_map_coordinate_system=valid_output_grid\n"
            f"input_frame_width={feature.shape[1]}\n"
            f"input_frame_height={feature.shape[0]}\n"
            f"score_map_width={out_w}\n"
            f"score_map_height={out_h}\n"
            f"bottom_right_x_min={x0}\n"
            f"bottom_right_y_min={y0}\n"
            "score_map_pixel_x = bottom_right_x - bottom_right_x_min\n"
            "score_map_pixel_y = bottom_right_y - bottom_right_y_min\n"
        )
