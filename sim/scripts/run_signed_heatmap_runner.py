#!/usr/bin/env python3
r"""
run_signed_heatmap_runner.py
============================

Windows-friendly cocotb runner for the signed heatmap autocontrast test.

This avoids the cocotb Makefile flow, which can fail under PowerShell/cmd when
Unix tools such as `tr` are not available or when GNU make resolves `python`
outside the active venv.

Run from sim/:

    .\.venv\Scripts\python.exe scripts\run_signed_heatmap_runner.py

Examples:

    .\.venv\Scripts\python.exe scripts\run_signed_heatmap_runner.py --sim questa
    .\.venv\Scripts\python.exe scripts\run_signed_heatmap_runner.py --vga-width 640 --vga-height 480 --ds-width 320 --ds-height 240
    .\.venv\Scripts\python.exe scripts\run_signed_heatmap_runner.py --waves
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Dict


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    p.add_argument("--sim", default=os.environ.get("SIM", "modelsim"), help="Simulator name for cocotb runner: modelsim or questa")
    p.add_argument("--vga-width", type=int, default=int(os.environ.get("VGA_WIDTH", "64")))
    p.add_argument("--vga-height", type=int, default=int(os.environ.get("VGA_HEIGHT", "48")))
    p.add_argument("--ds-width", type=int, default=int(os.environ.get("DS_WIDTH", "32")))
    p.add_argument("--ds-height", type=int, default=int(os.environ.get("DS_HEIGHT", "24")))
    p.add_argument("--score-w", type=int, default=int(os.environ.get("SCORE_W", "32")))
    p.add_argument("--score-shift", type=int, default=int(os.environ.get("SCORE_SHIFT", "10")))
    p.add_argument("--autocontrast-en", type=int, default=int(os.environ.get("AUTOCONTRAST_EN", "1")))
    p.add_argument("--box-size-ds", type=int, default=int(os.environ.get("BOX_SIZE_DS", "32")))
    p.add_argument("--box-thick", type=int, default=int(os.environ.get("BOX_THICK", "2")))
    p.add_argument("--fail-on-mismatch", type=int, default=int(os.environ.get("FAIL_ON_MISMATCH", "1")))
    p.add_argument("--fail-mismatch-ratio", type=float, default=float(os.environ.get("FAIL_MISMATCH_RATIO", "0.03")))
    p.add_argument("--waves", action="store_true", help="Ask the simulator/runner to dump waves if supported")
    p.add_argument("--gui", action="store_true", help="Launch simulator GUI if supported")
    p.add_argument("--clean", action="store_true", help="Delete/rebuild sim/build/heatmap_signed_runner")
    p.add_argument("--verbose", action="store_true")
    return p.parse_args()


def main() -> None:
    args = parse_args()

    try:
        from cocotb_tools.runner import get_runner
    except Exception as exc:
        raise SystemExit(
            "Could not import cocotb_tools.runner. Activate sim/.venv and install cocotb first:\n"
            "  .\\.venv\\Scripts\\Activate.ps1\n"
            "  python -m pip install cocotb opencv-python numpy\n"
            f"Original import error: {exc}"
        )

    script_dir = Path(__file__).resolve().parent
    sim_dir = script_dir.parent
    tests_dir = sim_dir / "tests"
    project_root = sim_dir.parent
    rtl_dir = project_root / "rtl" / "object_detection"
    dut_file = rtl_dir / "vga_debug_mux.v"
    if not dut_file.is_file():
        raise SystemExit(f"Missing DUT file: {dut_file}")

    params: Dict[str, int] = {
        "SCORE_W": args.score_w,
        "BOX_SIZE_DS": args.box_size_ds,
        "BOX_THICK": args.box_thick,
        "DS_WIDTH": args.ds_width,
        "DS_HEIGHT": args.ds_height,
        "VGA_WIDTH": args.vga_width,
        "VGA_HEIGHT": args.vga_height,
        "SCORE_SHIFT": args.score_shift,
        "AUTOCONTRAST_EN": args.autocontrast_en,
    }

    extra_env = os.environ.copy()
    extra_env.update(
        {
            "PROJECT_ROOT": str(project_root),
            "OUTPUT_DIR": str(sim_dir / "output" / "heatmap_signed"),
            "VGA_WIDTH": str(args.vga_width),
            "VGA_HEIGHT": str(args.vga_height),
            "DS_WIDTH": str(args.ds_width),
            "DS_HEIGHT": str(args.ds_height),
            "SCORE_W": str(args.score_w),
            "SCORE_SHIFT": str(args.score_shift),
            "AUTOCONTRAST_EN": str(args.autocontrast_en),
            "FAIL_ON_MISMATCH": str(args.fail_on_mismatch),
            "FAIL_MISMATCH_RATIO": str(args.fail_mismatch_ratio),
            "PYTHONPATH": str(tests_dir) + os.pathsep + str(sim_dir) + os.pathsep + extra_env.get("PYTHONPATH", ""),
        }
    )

    print(f"Python: {sys.executable}")
    print(f"Simulator: {args.sim}")
    print(f"DUT: {dut_file}")
    print(f"Params: {params}")

    runner = get_runner(args.sim)
    build_dir = sim_dir / "build" / "heatmap_signed_runner"

    runner.build(
        sources=[dut_file],
        hdl_toplevel="vga_debug_mux",
        parameters=params,
        build_dir=build_dir,
        always=True,
        clean=args.clean,
        verbose=args.verbose,
        timescale=("1ns", "1ps"),
        waves=args.waves,
    )

    runner.test(
        hdl_toplevel="vga_debug_mux",
        hdl_toplevel_lang="verilog",
        test_module="test_vga_signed_heatmap_autocontrast",
        parameters=params,
        build_dir=build_dir,
        test_dir=tests_dir,
        extra_env=extra_env,
        waves=args.waves,
        gui=args.gui,
        verbose=args.verbose,
        timescale=("1ns", "1ps"),
    )


if __name__ == "__main__":
    main()
