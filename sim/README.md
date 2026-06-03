# Sparse Sobel matched-filter simulation

This folder contains the cocotb/ModelSim simulation environment for the current
sparse Sobel matched-filter and VGA heatmap debug paths. The folder is organized
so source files, helper scripts, generated build products, logs, and test output
do not mix together.

## Folder layout

```text
sim/
├── Makefile                         # sparse matcher cocotb make flow
├── Makefile.heatmap                 # unsigned/raw heatmap debug make flow
├── Makefile.signed_heatmap          # signed autocontrast heatmap make flow
├── requirements.txt
├── scripts/                         # PowerShell and Python run helpers
├── templates/                       # simulation-only Verilog include templates
├── tests/                           # cocotb tests and Python reference model
├── output/                          # generated test artifacts, by category
│   ├── sparse_matcher/
│   ├── heatmap_unsigned/
│   └── heatmap_signed/
├── build/                           # generated simulator build libraries
└── logs/                            # generated transcripts and results XML
```

`output/`, `build/`, `logs/`, `.venv/`, `modelsim.ini`, caches, wave files, and
transcripts are generated/local artifacts and are ignored by git.

## Output categories

- `output/sparse_matcher/` - direct MAC-tree matcher outputs such as
  `feature_frame.png`, `reference_score_map.png`, `dut_score_map.png`,
  `score_absdiff.png`, `score_map_geometry.txt`, and `compare_metrics.txt`.
- `output/heatmap_unsigned/` - raw/unsigned VGA heatmap debug images, probe CSVs,
  and `llm_heatmap_debug_summary.json`.
- `output/heatmap_signed/` - signed-score autocontrast heatmap debug images,
  probe CSVs, and `llm_signed_heatmap_debug_summary.json`.

## Setup

From `sim/` on Windows PowerShell:

```powershell
.\scripts\setup_env.ps1
```

This creates `sim/.venv` and installs the Python packages in `requirements.txt`.
The virtual environment is intentionally not committed.

## Default sparse matcher test

From `sim/`:

```powershell
.\scripts\run_modelsim.ps1
```

The default run matches the active project configuration:

```text
TEST_WIDTH     = 128
TEST_HEIGHT    = 96
TEMPLATE_SIZE  = 64
NUM_TAPS       = 32
ROW_W/COL_W    = 6/6
TEMPLATE       = rtl/object_detection/donut_edge_template_32.vh
OUTPUT_DIR     = sim/output/sparse_matcher
```

Equivalent make flow:

```sh
make -C sim
```

## Parameterization smoke test

This uses the same RTL with a small simulation-only include file to prove the
MAC/tree path is not hardwired to 64x64 or 32 taps:

```powershell
.\scripts\run_modelsim.ps1 -TestWidth 48 -TestHeight 40 -TemplateSize 16 -NumTaps 5 -RowW 4 -ColW 4 -TemplateInclude sim_template_16_5.vh -TemplateVh .\templates\sim_template_16_5.vh -DonutX 12 -DonutY 8
```

Equivalent make flow from the repository root:

```sh
make -C sim TEST_WIDTH=48 TEST_HEIGHT=40 TEMPLATE_SIZE=16 NUM_TAPS=5 ROW_W=4 COL_W=4 TEMPLATE_INCLUDE=sim_template_16_5.vh TEMPLATE_VH=$(pwd)/sim/templates/sim_template_16_5.vh DONUT_X=12 DONUT_Y=8
```

## Heatmap debug tests

Unsigned/raw heatmap debug:

```powershell
.\scripts\run_heatmap_debug.ps1
```

Equivalent make flow:

```sh
make -C sim -f Makefile.heatmap
```

Signed autocontrast heatmap debug:

```powershell
.\scripts\run_signed_heatmap_debug.ps1
```

Equivalent make flow:

```sh
make -C sim -f Makefile.signed_heatmap
```

A Windows-friendly cocotb runner is also available for the signed heatmap path:

```powershell
.\scripts\run_signed_heatmap_runner.ps1
```

Use `-FullSize` on that wrapper to run the 640x480 / 320x240 configuration.

## Notes

- The sparse matcher sim drives `feature_in` directly with Sobel magnitude
  pixels. It does not re-test RGB downsampling or `sobel3x3_stream`; those are
  separate pipeline stages.
- The RTL include selected by `TEMPLATE_INCLUDE` must match `NUM_TAPS`, `ROW_W`,
  and `COL_W`.
- Intel ModelSim Starter does not enable FLI, so the Windows scripts use
  cocotb's VPI bridge DLL.
