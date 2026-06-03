from __future__ import annotations

import os
import traceback
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

from reference_model import (
    env_int,
    make_feature_frame,
    parse_template_vh,
    reference_scores,
    resolve_template_path,
    write_debug_images,
)


async def reset_dut(dut) -> None:
    dut.rst_n.value = 0
    dut.feature_valid.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.feature_in.value = 0
    for _ in range(6):
        await RisingEdge(dut.clk)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def tick_and_capture(dut, observed: dict[tuple[int, int], int]) -> None:
    await RisingEdge(dut.clk)
    # Sample after the registered outputs settle in ModelSim/cocotb.
    await Timer(1, units="ns")
    if int(dut.score_valid.value) == 1:
        coord = (int(dut.x_out.value), int(dut.y_out.value))
        score = int(dut.score_out.value.signed_integer)
        if coord in observed:
            raise AssertionError(f"Duplicate score_valid output for coordinate {coord}")
        observed[coord] = score


async def drive_feature_frame(dut, feature, flush_cycles: int) -> dict[tuple[int, int], int]:
    observed: dict[tuple[int, int], int] = {}
    height, width = feature.shape

    for y in range(height):
        for x in range(width):
            dut.feature_valid.value = 1
            dut.x_in.value = x
            dut.y_in.value = y
            dut.feature_in.value = int(feature[y, x])
            await tick_and_capture(dut, observed)

    dut.feature_valid.value = 0
    dut.x_in.value = 0
    dut.y_in.value = 0
    dut.feature_in.value = 0
    for _ in range(flush_cycles):
        await tick_and_capture(dut, observed)

    return observed


def write_metrics(
    path: Path,
    *,
    expected: dict[tuple[int, int], int],
    observed: dict[tuple[int, int], int],
    mismatches: list[str],
    expected_best_coord: tuple[int, int],
) -> None:
    common = set(expected) & set(observed)
    max_abs = 0
    if common:
        max_abs = max(abs(expected[c] - observed[c]) for c in common)
    best_ref_coord = max(expected, key=expected.get)
    best_dut_coord = max(observed, key=observed.get) if observed else None
    lines = [
        "object_name=cow",
        f"expected_count={len(expected)}",
        f"observed_count={len(observed)}",
        f"common_count={len(common)}",
        f"max_abs_score_error={max_abs}",
        f"expected_inserted_object_bottom_right={expected_best_coord}",
        f"best_reference_coord={best_ref_coord}",
        f"best_reference_score={expected[best_ref_coord]}",
        f"best_dut_coord={best_dut_coord}",
        f"best_dut_score={observed.get(best_dut_coord, 'NA') if best_dut_coord is not None else 'NA'}",
        f"mismatch_count={len(mismatches)}",
    ]
    if mismatches:
        lines.append("first_mismatches:")
        lines.extend(mismatches[:40])
    path.write_text("\n".join(lines) + "\n")


@cocotb.test()
async def sparse_template_matcher_cow_score_test(dut):
    width = env_int("TEST_WIDTH", 192)
    height = env_int("TEST_HEIGHT", 144)
    template_size = env_int("TEMPLATE_SIZE", 64)
    num_taps = env_int("NUM_TAPS", 64)
    object_x = env_int("OBJECT_X", env_int("COW_X", max(0, (width - template_size) // 2)))
    object_y = env_int("OBJECT_Y", env_int("COW_Y", max(0, (height - template_size) // 2)))
    output_dir = Path(os.environ.get("OUTPUT_DIR", "output/sparse_matcher_cow"))
    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        cocotb.start_soon(Clock(dut.clk, 10, units="ns").start())
        await reset_dut(dut)

        template_path = resolve_template_path()
        taps = parse_template_vh(template_path, expected_taps=num_taps)
        feature = make_feature_frame(width, height, template_size, object_x, object_y)
        expected = reference_scores(feature, taps, template_size)

        # Stream-delay flush plus score-tree/MAC latency margin.
        flush_cycles = template_size + num_taps + 64
        observed = await drive_feature_frame(dut, feature, flush_cycles)

        write_debug_images(output_dir, feature, expected, observed)

        missing = sorted(set(expected) - set(observed))
        extra = sorted(set(observed) - set(expected))
        mismatches: list[str] = []
        if missing:
            mismatches.append(f"missing {len(missing)} expected coordinates, first={missing[:10]}")
        if extra:
            mismatches.append(f"extra {len(extra)} unexpected coordinates, first={extra[:10]}")
        for coord in sorted(set(expected) & set(observed)):
            if observed[coord] != expected[coord]:
                mismatches.append(f"score mismatch at {coord}: dut={observed[coord]} ref={expected[coord]}")
                if len(mismatches) >= 50:
                    break

        expected_best_coord = (object_x + template_size - 1, object_y + template_size - 1)
        write_metrics(
            output_dir / "compare_metrics.txt",
            expected=expected,
            observed=observed,
            mismatches=mismatches,
            expected_best_coord=expected_best_coord,
        )

        best_ref_coord = max(expected, key=expected.get)
        best_dut_coord = max(observed, key=observed.get) if observed else None
        dut._log.info("best_ref_coord=%s score=%d", best_ref_coord, expected[best_ref_coord])
        if best_dut_coord is not None:
            dut._log.info("best_dut_coord=%s score=%d", best_dut_coord, observed[best_dut_coord])

        assert not mismatches, "DUT cow sparse matcher did not match Python reference; see sim/output/sparse_matcher_cow/compare_metrics.txt"
        assert best_ref_coord == expected_best_coord, "Python reference best-match coordinate is not the inserted cow location"
        assert best_dut_coord == best_ref_coord, "DUT best-match coordinate differs from reference"
    except Exception:
        (output_dir / "test_exception.txt").write_text(traceback.format_exc())
        raise
