from __future__ import annotations

import csv
import json
import os
import traceback
from pathlib import Path
from typing import Iterable

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
import cv2
import numpy as np


def env_int(name: str, default: int) -> int:
    return int(os.environ.get(name, str(default)), 0)


def env_float(name: str, default: float) -> float:
    return float(os.environ.get(name, str(default)))


def env_bool(name: str, default: bool = False) -> bool:
    value = os.environ.get(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def autocontrast_shift(max_abs_score: int) -> int:
    """Match vga_debug_mux.max_to_shift(): keep the frame maximum near 255."""
    max_abs_score = int(max(0, max_abs_score))
    if max_abs_score == 0:
        return 0
    msb = max_abs_score.bit_length() - 1
    return max(0, msb - 7)


def scale3_sat(value: int) -> int:
    return int(min(max(0, value) * 3, 255))


def signed_heat_rgb(score: int, *, display_shift: int) -> tuple[int, int, int]:
    """Mirror vga_debug_mux.signed_heat_to_rgb() plus score scaling."""
    score = int(score)
    neg = score < 0
    mag = min(abs(score) >> int(display_shift), 255)
    if mag == 0:
        return 0, 0, 0

    if not neg:
        # Positive match: black -> red -> yellow -> white.
        if mag < 85:
            return scale3_sat(mag), 0, 0
        if mag < 170:
            return 255, scale3_sat(mag - 85), 0
        return 255, 255, scale3_sat(mag - 170)

    # Negative anti-match: black -> blue -> cyan -> white.
    if mag < 85:
        return 0, 0, scale3_sat(mag)
    if mag < 170:
        return 0, scale3_sat(mag - 85), 255
    return scale3_sat(mag - 170), 255, 255


def make_signed_score_map(width: int, height: int) -> np.ndarray:
    """Create deterministic positive and negative score regions for display verification."""
    yy, xx = np.indices((height, width))
    pos_x = int(round(width * 0.68))
    pos_y = int(round(height * 0.45))
    neg_x = int(round(width * 0.30))
    neg_y = int(round(height * 0.60))

    pos_sigma = max(2.0, min(width, height) / 7.0)
    neg_sigma = max(2.0, min(width, height) / 8.0)
    pos = 260000.0 * np.exp(-((xx - pos_x) ** 2 + (yy - pos_y) ** 2) / (2.0 * pos_sigma * pos_sigma))
    neg = 190000.0 * np.exp(-((xx - neg_x) ** 2 + (yy - neg_y) ** 2) / (2.0 * neg_sigma * neg_sigma))

    texture = 18000.0 * np.sin(xx * 0.33) + 11000.0 * np.cos(yy * 0.41)
    score = pos - neg + texture

    # A few exact points make the CSV/debug assertions obvious.
    score[pos_y, pos_x] = 261120
    score[neg_y, neg_x] = -196608
    score[0, 0] = 0
    return np.rint(score).astype(np.int64)


def flatten_score_stream(score_map: np.ndarray) -> list[tuple[int, int, int]]:
    h, w = score_map.shape
    return [(x, y, int(score_map[y, x])) for y in range(h) for x in range(w)]


def render_expected(score_map: np.ndarray, vga_width: int, vga_height: int, *, display_shift: int) -> np.ndarray:
    ds_h, ds_w = score_map.shape
    img = np.zeros((vga_height, vga_width, 3), dtype=np.uint8)
    for y in range(vga_height):
        sy = min((y * ds_h) // vga_height, ds_h - 1)
        for x in range(vga_width):
            sx = min((x * ds_w) // vga_width, ds_w - 1)
            img[y, x, :] = signed_heat_rgb(int(score_map[sy, sx]), display_shift=display_shift)
    return img


def write_rgb_png(path: Path, img_rgb: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), cv2.cvtColor(img_rgb, cv2.COLOR_RGB2BGR))


def image_stats(img_rgb: np.ndarray) -> dict[str, int | float | list[int]]:
    flat = img_rgb.reshape(-1, 3)
    unique = np.unique(flat, axis=0)
    return {
        "width": int(img_rgb.shape[1]),
        "height": int(img_rgb.shape[0]),
        "unique_rgb_colors": int(unique.shape[0]),
        "mean_r": float(img_rgb[:, :, 0].mean()),
        "mean_g": float(img_rgb[:, :, 1].mean()),
        "mean_b": float(img_rgb[:, :, 2].mean()),
        "min_rgb": [int(v) for v in flat.min(axis=0)],
        "max_rgb": [int(v) for v in flat.max(axis=0)],
    }


def diff_stats(expected: np.ndarray, observed: np.ndarray) -> dict[str, int | float]:
    diff = np.abs(expected.astype(np.int16) - observed.astype(np.int16))
    changed = np.any(diff != 0, axis=2)
    return {
        "changed_pixels": int(changed.sum()),
        "total_pixels": int(changed.size),
        "changed_pixel_ratio": float(changed.mean()),
        "max_channel_absdiff": int(diff.max()),
        "mean_channel_absdiff": float(diff.mean()),
    }


def logic_value_to_int(value, *, signed: bool = False) -> int | None:
    try:
        is_resolvable = getattr(value, "is_resolvable", None)
        if is_resolvable is not None:
            resolvable = is_resolvable() if callable(is_resolvable) else bool(is_resolvable)
            if not resolvable:
                return None
        if signed:
            if hasattr(value, "to_signed"):
                return int(value.to_signed())
            if hasattr(value, "signed_integer"):
                return int(value.signed_integer)
        else:
            if hasattr(value, "to_unsigned"):
                return int(value.to_unsigned())
            if hasattr(value, "integer"):
                return int(value.integer)
        return int(value)
    except Exception:
        return None


def read_optional_int(dut, name: str, *, signed: bool = False) -> int | None:
    try:
        return logic_value_to_int(getattr(dut, name).value, signed=signed)
    except Exception:
        return None


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.mode.value = 2
    dut.overlay_en.value = 0
    dut.gray_view.value = 0
    dut.cam_r.value = 0
    dut.cam_g.value = 0
    dut.cam_b.value = 0
    dut.gray.value = 0
    dut.gray_valid.value = 0
    dut.edge_mag.value = 0
    dut.edge_valid.value = 0
    dut.score.value = 0
    dut.score_valid.value = 0
    dut.score_x.value = 0
    dut.score_y.value = 0
    dut.threshold.value = 0
    dut.found.value = 0
    dut.det_x_ds.value = 0
    dut.det_y_ds.value = 0
    dut.pixel_x.value = 0
    dut.pixel_y.value = 0
    dut.blank_n.value = 0
    dut.frame_sync.value = 1
    for _ in range(8):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def pulse_frame_sync(dut) -> None:
    """vga_debug_mux treats a falling edge on frame_sync/VGA_VS as frame start."""
    dut.frame_sync.value = 1
    await RisingEdge(dut.clk)
    dut.frame_sync.value = 0
    await RisingEdge(dut.clk)
    dut.frame_sync.value = 0
    await RisingEdge(dut.clk)
    dut.frame_sync.value = 1
    await RisingEdge(dut.clk)


async def preload_scores(dut, scores: Iterable[tuple[int, int, int]]) -> None:
    dut.blank_n.value = 0
    dut.score_valid.value = 0
    await RisingEdge(dut.clk)
    for x, y, score in scores:
        dut.score_x.value = int(x)
        dut.score_y.value = int(y)
        dut.score.value = int(score)
        dut.score_valid.value = 1
        await RisingEdge(dut.clk)
    dut.score_valid.value = 0
    await RisingEdge(dut.clk)


async def capture_vga_frame(dut, *, vga_width: int, vga_height: int) -> tuple[np.ndarray, list[dict[str, int | None]]]:
    img = np.zeros((vga_height, vga_width, 3), dtype=np.uint8)
    probes: list[dict[str, int | None]] = []
    sample_points = {
        (0, 0),
        (vga_width // 3, vga_height // 2),
        ((2 * vga_width) // 3, vga_height // 2),
        (vga_width - 1, vga_height - 1),
    }

    # Prime the synchronous RAM read so the first active pixel uses address (0,0).
    dut.mode.value = 2
    dut.overlay_en.value = 0
    dut.found.value = 0
    dut.score_valid.value = 0
    dut.blank_n.value = 0
    dut.pixel_x.value = vga_width - 1
    dut.pixel_y.value = vga_height - 1
    await RisingEdge(dut.clk)

    cycle = 0
    for y in range(vga_height):
        for x in range(vga_width):
            dut.mode.value = 2
            dut.blank_n.value = 1
            dut.pixel_x.value = x
            dut.pixel_y.value = y
            await RisingEdge(dut.clk)
            r = read_optional_int(dut, "vga_r")
            g = read_optional_int(dut, "vga_g")
            b = read_optional_int(dut, "vga_b")
            img[y, x, :] = (r or 0, g or 0, b or 0)
            if (x, y) in sample_points:
                probes.append(
                    {
                        "cycle": cycle,
                        "pixel_x": x,
                        "pixel_y": y,
                        "display_shift_internal": read_optional_int(dut, "display_shift"),
                        "last_frame_abs_max_internal": read_optional_int(dut, "last_frame_abs_max"),
                        "heat_mag_internal": read_optional_int(dut, "heat_mag"),
                        "heat_neg_internal": read_optional_int(dut, "heat_neg"),
                        "vga_r": r,
                        "vga_g": g,
                        "vga_b": b,
                    }
                )
            cycle += 1
    dut.blank_n.value = 0
    await RisingEdge(dut.clk)
    return img, probes


def write_probe_csv(path: Path, rows: list[dict[str, int | None]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("no_probe_rows\n")
        return
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


@cocotb.test()
async def vga_signed_heatmap_autocontrast_test(dut):
    output_dir = Path(os.environ.get("OUTPUT_DIR", "output/heatmap_signed"))
    output_dir.mkdir(parents=True, exist_ok=True)

    vga_width = env_int("VGA_WIDTH", 64)
    vga_height = env_int("VGA_HEIGHT", 48)
    ds_width = env_int("DS_WIDTH", max(1, vga_width // 2))
    ds_height = env_int("DS_HEIGHT", max(1, vga_height // 2))
    fail_on_mismatch = env_bool("FAIL_ON_MISMATCH", True)
    fail_ratio = env_float("FAIL_MISMATCH_RATIO", 0.03)

    try:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        await reset_dut(dut)

        score_map = make_signed_score_map(ds_width, ds_height)
        score_stream = flatten_score_stream(score_map)
        expected_shift = autocontrast_shift(int(np.abs(score_map).max()))

        # First score frame measures the raw max using the reset/default shift.
        await preload_scores(dut, score_stream)
        await pulse_frame_sync(dut)

        observed_shift_after_first = read_optional_int(dut, "display_shift")
        assert observed_shift_after_first == expected_shift, (
            f"expected display_shift {expected_shift}, got {observed_shift_after_first}"
        )

        # Second score frame writes the score RAM using the new adaptive shift.
        await preload_scores(dut, score_stream)
        expected = render_expected(score_map, vga_width, vga_height, display_shift=expected_shift)
        observed, probes = await capture_vga_frame(dut, vga_width=vga_width, vga_height=vga_height)

        diff = np.abs(expected.astype(np.int16) - observed.astype(np.int16)).astype(np.uint8)
        write_rgb_png(output_dir / "signed_heatmap_expected.png", expected)
        write_rgb_png(output_dir / "signed_heatmap_dut.png", observed)
        write_rgb_png(output_dir / "signed_heatmap_absdiff.png", diff)
        write_probe_csv(output_dir / "llm_signed_heatmap_probe_samples.csv", probes)

        stats = diff_stats(expected, observed)
        pos_count = int((score_map > 0).sum())
        neg_count = int((score_map < 0).sum())
        summary = {
            "bench": "test_vga_signed_heatmap_autocontrast.py::vga_signed_heatmap_autocontrast_test",
            "purpose": "Verify vga_debug_mux mode 2 signed score heatmap and frame-level adaptive shift auto-contrast.",
            "configuration": {
                "vga_width": vga_width,
                "vga_height": vga_height,
                "ds_width": ds_width,
                "ds_height": ds_height,
                "fail_on_mismatch": fail_on_mismatch,
                "fail_mismatch_ratio": fail_ratio,
            },
            "score_map_stats": {
                "min_score": int(score_map.min()),
                "max_score": int(score_map.max()),
                "max_abs_score": int(np.abs(score_map).max()),
                "positive_score_cells": pos_count,
                "negative_score_cells": neg_count,
                "expected_display_shift": expected_shift,
                "observed_display_shift_after_first_frame": observed_shift_after_first,
            },
            "expected_image_stats": image_stats(expected),
            "dut_image_stats": image_stats(observed),
            "dut_vs_expected": stats,
            "color_contract": {
                "zero": "black",
                "positive_scores": "black to red to yellow to white",
                "negative_scores": "black to blue to cyan to white",
            },
            "implementation_note": (
                "The RTL stores {threshold_mask, sign, 8-bit magnitude} per score cell. "
                "Auto-contrast uses the previous frame's max absolute score to choose a power-of-two display shift; "
                "the next frame's score writes use that shift. No divider is used."
            ),
        }
        (output_dir / "llm_signed_heatmap_debug_summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        dut._log.info("expected display_shift=%d", expected_shift)
        dut._log.info("changed_pixel_ratio=%.5f", stats["changed_pixel_ratio"])
        dut._log.info("wrote signed heatmap debug artifacts to %s", output_dir)

        if fail_on_mismatch:
            assert stats["changed_pixel_ratio"] <= fail_ratio, (
                "Signed heatmap output does not match the expected spatial/autocontrast image; "
                "see sim/output/heatmap_signed/llm_signed_heatmap_debug_summary.json"
            )
    except Exception:
        (output_dir / "test_exception.txt").write_text(traceback.format_exc())
        raise
