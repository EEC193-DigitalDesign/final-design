from __future__ import annotations

import csv
import json
import math
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


def score_to_heat_rgb(score: int, *, score_shift: int = 10) -> tuple[int, int, int]:
    """Mirror vga_debug_mux heatmap color logic for a single signed score."""
    score_pos = max(0, int(score))
    heat_val = min(score_pos >> score_shift, 255)
    if heat_val < 85:
        return int(heat_val * 3), 0, 0
    if heat_val < 170:
        return 255, int((heat_val - 85) * 3), 0
    return 255, 255, int((heat_val - 170) * 3)


def make_score_map(width: int, height: int, *, score_shift: int, hot_x: int, hot_y: int) -> np.ndarray:
    """Create a deterministic score map with a single obvious hot spot plus background texture."""
    yy, xx = np.indices((height, width))
    hot_x = int(np.clip(hot_x, 0, width - 1))
    hot_y = int(np.clip(hot_y, 0, height - 1))

    # Low background exercises nonzero red values without saturating everything.
    background_heat = 5 + ((3 * xx + 7 * yy) % 18)

    # Gaussian-ish hot spot.  The size scales with the frame so this remains useful
    # for both fast small sims and full 640x480/320x240 sims.
    sigma = max(3.0, min(width, height) / 13.0)
    dist2 = (xx - hot_x) ** 2 + (yy - hot_y) ** 2
    peak_heat = 245.0 * np.exp(-dist2 / (2.0 * sigma * sigma))

    # A smaller negative-looking trench in software terms is represented as zero
    # because the current RTL heatmap clamps negative scores to black.  Keep all
    # scores positive here so the spatial mapping error is the only variable.
    heat = np.clip(background_heat + peak_heat, 0, 255).astype(np.int64)
    return (heat << score_shift).astype(np.int64)


def render_expected_vga(score_map: np.ndarray, vga_width: int, vga_height: int, *, score_shift: int) -> np.ndarray:
    """Ideal heatmap: VGA pixel reads the score map at the corresponding downsampled coordinate."""
    ds_h, ds_w = score_map.shape
    img = np.zeros((vga_height, vga_width, 3), dtype=np.uint8)
    for y in range(vga_height):
        sy = min((y * ds_h) // vga_height, ds_h - 1)
        for x in range(vga_width):
            sx = min((x * ds_w) // vga_width, ds_w - 1)
            img[y, x, :] = score_to_heat_rgb(int(score_map[sy, sx]), score_shift=score_shift)
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
    per_pixel_changed = np.any(diff != 0, axis=2)
    return {
        "changed_pixels": int(per_pixel_changed.sum()),
        "total_pixels": int(per_pixel_changed.size),
        "changed_pixel_ratio": float(per_pixel_changed.mean()),
        "max_channel_absdiff": int(diff.max()),
        "mean_channel_absdiff": float(diff.mean()),
    }


def flatten_score_stream(score_map: np.ndarray) -> list[tuple[int, int, int]]:
    h, w = score_map.shape
    return [(x, y, int(score_map[y, x])) for y in range(h) for x in range(w)]


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.mode.value = 2  # score heatmap
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


async def drive_one_score(dut, x: int, y: int, score: int) -> None:
    dut.score_x.value = int(x)
    dut.score_y.value = int(y)
    dut.score.value = int(score)
    dut.score_valid.value = 1
    await RisingEdge(dut.clk)
    dut.score_valid.value = 0


async def preload_scores(dut, scores: Iterable[tuple[int, int, int]]) -> None:
    dut.blank_n.value = 0
    dut.pixel_x.value = 0
    dut.pixel_y.value = 0
    for x, y, score in scores:
        dut.score_x.value = int(x)
        dut.score_y.value = int(y)
        dut.score.value = int(score)
        dut.score_valid.value = 1
        await RisingEdge(dut.clk)
    dut.score_valid.value = 0
    await RisingEdge(dut.clk)


def read_optional_int(dut, name: str, *, signed: bool = False) -> int | None:
    try:
        value = getattr(dut, name).value
        return int(value.signed_integer) if signed else int(value)
    except Exception:
        return None


async def capture_vga_frame(
    dut,
    *,
    vga_width: int,
    vga_height: int,
    score_stream: list[tuple[int, int, int]],
    drive_scores_while_scanning: bool,
) -> tuple[np.ndarray, list[dict[str, int | None]]]:
    """Capture one active VGA frame from vga_debug_mux.

    If drive_scores_while_scanning is false, the DUT reads only the preloaded
    score framebuffer.  If true, a free-running coordinate-tagged score stream
    is also driven while VGA scans, which exercises simultaneous score writes
    and VGA reads.
    """
    img = np.zeros((vga_height, vga_width, 3), dtype=np.uint8)
    probes: list[dict[str, int | None]] = []
    stream_len = max(1, len(score_stream))
    cycle = 0

    sample_points = {
        (0, 0),
        (vga_width // 4, vga_height // 4),
        (vga_width // 2, vga_height // 2),
        ((3 * vga_width) // 4, (3 * vga_height) // 4),
        (vga_width - 1, vga_height - 1),
    }

    for y in range(vga_height):
        for x in range(vga_width):
            dut.mode.value = 2
            dut.overlay_en.value = 0
            dut.found.value = 0
            dut.blank_n.value = 1
            dut.pixel_x.value = x
            dut.pixel_y.value = y

            if drive_scores_while_scanning:
                sx, sy, score_value = score_stream[cycle % stream_len]
                dut.score_x.value = sx
                dut.score_y.value = sy
                dut.score.value = score_value
                dut.score_valid.value = 1
            else:
                dut.score_valid.value = 0

            await RisingEdge(dut.clk)

            r = int(dut.vga_r.value)
            g = int(dut.vga_g.value)
            b = int(dut.vga_b.value)
            img[y, x, :] = (r, g, b)

            if (x, y) in sample_points:
                probes.append(
                    {
                        "cycle": cycle,
                        "pixel_x": x,
                        "pixel_y": y,
                        "score_x_input": read_optional_int(dut, "score_x"),
                        "score_y_input": read_optional_int(dut, "score_y"),
                        "score_input": read_optional_int(dut, "score", signed=True),
                        "score_valid": int(dut.score_valid.value),
                        "score_hold_internal": read_optional_int(dut, "score_hold", signed=True),
                        "heat_val_internal": read_optional_int(dut, "heat_val"),
                        "vga_r": r,
                        "vga_g": g,
                        "vga_b": b,
                    }
                )
            cycle += 1

    dut.blank_n.value = 0
    dut.score_valid.value = 0
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


def write_score_csv(path: Path, score_map: np.ndarray, *, score_shift: int, hot_x: int, hot_y: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    points = []
    h, w = score_map.shape
    for y, x in [
        (0, 0),
        (hot_y, hot_x),
        (h // 2, w // 2),
        (h - 1, w - 1),
        (max(0, hot_y - 4), hot_x),
        (min(h - 1, hot_y + 4), hot_x),
    ]:
        score = int(score_map[y, x])
        r, g, b = score_to_heat_rgb(score, score_shift=score_shift)
        points.append(
            {
                "score_x": int(x),
                "score_y": int(y),
                "score": score,
                "expected_heat_val": min(max(score, 0) >> score_shift, 255),
                "expected_r": r,
                "expected_g": g,
                "expected_b": b,
            }
        )
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(points[0].keys()))
        writer.writeheader()
        writer.writerows(points)


@cocotb.test()
async def vga_heatmap_spatial_debug_test(dut):
    output_dir = Path(os.environ.get("OUTPUT_DIR", "output/heatmap_unsigned"))
    output_dir.mkdir(parents=True, exist_ok=True)

    vga_width = env_int("VGA_WIDTH", 640)
    vga_height = env_int("VGA_HEIGHT", 480)
    ds_width = env_int("DS_WIDTH", max(1, vga_width // 2))
    ds_height = env_int("DS_HEIGHT", max(1, vga_height // 2))
    score_shift = env_int("SCORE_SHIFT", 10)
    hot_x = env_int("HOT_X", ds_width // 2)
    hot_y = env_int("HOT_Y", ds_height // 2)
    fail_on_mismatch = env_bool("FAIL_ON_MISMATCH", False)
    fail_ratio = env_float("FAIL_MISMATCH_RATIO", 0.02)

    try:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        await reset_dut(dut)

        score_map = make_score_map(ds_width, ds_height, score_shift=score_shift, hot_x=hot_x, hot_y=hot_y)
        score_stream = flatten_score_stream(score_map)
        expected = render_expected_vga(score_map, vga_width, vga_height, score_shift=score_shift)

        write_rgb_png(output_dir / "heatmap_expected_spatial.png", expected)
        write_rgb_png(
            output_dir / "heatmap_score_map_raw.png",
            render_expected_vga(score_map, ds_width, ds_height, score_shift=score_shift),
        )
        write_score_csv(output_dir / "llm_score_probe_points.csv", score_map, score_shift=score_shift, hot_x=hot_x, hot_y=hot_y)

        # Phase A: preload all coordinate-tagged scores, then render a frame.
        # A correct heatmap display should read those stored scores spatially.
        await preload_scores(dut, score_stream)
        dut._log.info("preload complete; final score_hold=%s", read_optional_int(dut, "score_hold", signed=True))
        observed_preloaded, probes_preloaded = await capture_vga_frame(
            dut,
            vga_width=vga_width,
            vga_height=vga_height,
            score_stream=score_stream,
            drive_scores_while_scanning=False,
        )

        # Phase B: render while a coordinate-tagged score stream runs in parallel.
        # This exercises the framebuffer read/write behavior during normal scanout.
        observed_streamed, probes_streamed = await capture_vga_frame(
            dut,
            vga_width=vga_width,
            vga_height=vga_height,
            score_stream=score_stream,
            drive_scores_while_scanning=True,
        )

        diff_preloaded = np.abs(expected.astype(np.int16) - observed_preloaded.astype(np.int16)).astype(np.uint8)
        diff_streamed = np.abs(expected.astype(np.int16) - observed_streamed.astype(np.int16)).astype(np.uint8)
        write_rgb_png(output_dir / "heatmap_dut_preloaded_last_score.png", observed_preloaded)
        write_rgb_png(output_dir / "heatmap_diff_preloaded_last_score.png", diff_preloaded)
        write_rgb_png(output_dir / "heatmap_dut_streamed_scores.png", observed_streamed)
        write_rgb_png(output_dir / "heatmap_diff_streamed_scores.png", diff_streamed)

        write_probe_csv(output_dir / "llm_vga_probe_samples_preloaded.csv", probes_preloaded)
        write_probe_csv(output_dir / "llm_vga_probe_samples_streamed.csv", probes_streamed)

        preloaded_stats = diff_stats(expected, observed_preloaded)
        streamed_stats = diff_stats(expected, observed_streamed)
        summary = {
            "bench": "test_vga_heatmap_debug.py::vga_heatmap_spatial_debug_test",
            "purpose": "Check whether vga_debug_mux renders a spatial score heatmap or only the most recent score.",
            "configuration": {
                "vga_width": vga_width,
                "vga_height": vga_height,
                "ds_width": ds_width,
                "ds_height": ds_height,
                "score_shift_matches_rtl": score_shift,
                "hotspot_score_x": int(np.clip(hot_x, 0, ds_width - 1)),
                "hotspot_score_y": int(np.clip(hot_y, 0, ds_height - 1)),
                "fail_on_mismatch": fail_on_mismatch,
                "fail_mismatch_ratio": fail_ratio,
            },
            "input_score_map_stats": {
                "min_score": int(score_map.min()),
                "max_score": int(score_map.max()),
                "mean_score": float(score_map.mean()),
                "unique_scores": int(np.unique(score_map).size),
            },
            "expected_image_stats": image_stats(expected),
            "dut_preloaded_last_score_image_stats": image_stats(observed_preloaded),
            "dut_streamed_scores_image_stats": image_stats(observed_streamed),
            "preloaded_last_score_vs_expected": preloaded_stats,
            "streamed_scores_vs_expected": streamed_stats,
            "likely_root_cause": (
                "Fixed design should store score_valid samples by score_x/score_y and read the "
                "stored heatmap cell corresponding to pixel_x/pixel_y during VGA scanout."
            ),
            "what_to_upload_to_llm": [
                "llm_heatmap_debug_summary.json",
                "llm_vga_probe_samples_preloaded.csv",
                "llm_vga_probe_samples_streamed.csv",
                "llm_score_probe_points.csv",
                "heatmap_expected_spatial.png",
                "heatmap_dut_preloaded_last_score.png",
                "heatmap_dut_streamed_scores.png",
            ],
            "recommended_fix_direction": (
                "Use the replacement vga_debug_mux.v with score_x/score_y ports and its 320x240 "
                "score framebuffer.  A later improvement is runtime or frame-level scaling instead of "
                "the fixed score >> 10."
            ),
        }
        (output_dir / "llm_heatmap_debug_summary.json").write_text(json.dumps(summary, indent=2) + "\n")

        dut._log.info("preloaded changed_pixel_ratio=%.4f", preloaded_stats["changed_pixel_ratio"])
        dut._log.info("streamed changed_pixel_ratio=%.4f", streamed_stats["changed_pixel_ratio"])
        dut._log.info("wrote heatmap debug artifacts to %s", output_dir)

        if fail_on_mismatch:
            assert preloaded_stats["changed_pixel_ratio"] <= fail_ratio, (
                "Heatmap display is not spatially correct; see llm_heatmap_debug_summary.json"
            )
    except Exception:
        (output_dir / "test_exception.txt").write_text(traceback.format_exc())
        raise
