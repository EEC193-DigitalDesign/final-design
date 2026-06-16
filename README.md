# Real-Time Object Detection using Matched Filtering on FPGA

> **ECE Outstanding Senior Design Project Award Winner**

A dedicated hardware pipeline for template-based object detection on the
DE1-SoC + D8M camera. Object recognition is normally a software task on GPUs
or CPUs; those are flexible but bottleneck on data movement, which hurts in
real-time settings where latency matters. This design replaces the software
path with a streaming RTL pipeline: 640x480 RGB from the camera is downsampled,
converted to grayscale, blurred, run through a Sobel edge detector, and scored
against a sparse matched-filter template, all in hardware. The detector
operates on the live pixel stream at the camera's pixel clock, with one score
per template-aligned window and a single best-match decision per frame.

Senior design project (UC Davis EEC 193). The repo is the full Quartus
project: top-level RTL, the detection pipeline, Terasic D8M camera/autofocus
infrastructure, simulation environment, and template-generation utilities.

## Project materials

- [Final paper](docs/TeamThomas_RealTimeObjectDetectionFPGA_2026.pdf)
- [Final poster](../final-poster)

## Pipeline

```
D8M camera (RAW, 640x480)
   |  MIPI bridge + RAW2RGB
   v
RGB stream (8b R/G/B, 25 MHz pixel clock)
   |  rgb_downsample_gray.v      (2:1 downsample, ITU-R BT.601 grayscale)
   v
Gray stream (320x240, 8b)
   |  gaussian3x3_stream.v       (3x3 Gaussian blur, noise reduction)
   v
Smoothed Gray stream (320x240, 8b)
   |  sobel3x3_stream.v          (3x3 Sobel, L1 |Gx|+|Gy|, edge thresholding)
   v
Edge magnitude stream (320x240, 8b)
   |  sparse_template_matcher.v
   |    stream_delay_engine.v    (TEMPLATE_SIZE row buffers in M10K)
   |    score_tree.v             (column shift register, sparse tap gather)
   |    score_mac_tree.v         (pipelined signed MAC reduction tree)
   v
Score stream (signed 32b, one per window position)
   |  detection_logic.v          (per-frame argmax + threshold)
   v
Detection (found, det_x, det_y, confidence)
   |  vga_debug_mux.v            (RGB / Sobel / heatmap / mask, bounding box)
   v
VGA out (640x480)
```

Templates are sparse: each is a list of `NUM_TAPS` `{row, col, signed weight}`
entries describing the strongest Sobel-edge taps from a reference image. The
current design uses `TEMPLATE_SIZE = 64`, `NUM_TAPS = 64` for the cow template.
The matcher computes one inner product per sliding window in a single MAC tree
stage with `log2(next_pow2(NUM_TAPS))` cycles of latency.

## Switches, keys, and HEX

- `SW[0]` - detection enable
- `SW[2:1]` - VGA display mode (00 camera RGB, 01 Sobel, 10 signed heatmap with
  autocontrast, 11 threshold mask)
- `SW[3]` - bounding box overlay
- `SW[4]` - grayscale view in mode 00
- `SW[9]` - selects which threshold KEY[1]/KEY[2] adjusts (0 = detection
  threshold, 1 = Sobel edge threshold)
- `KEY[0]` - reset
- `KEY[1]/KEY[2]` - decrease / increase selected threshold
- `KEY[3]` - autofocus trigger
- `HEX1:HEX0` - frame rate
- `HEX3:HEX2` - selected threshold value
- `HEX5:HEX4` - confidence of current detection (blank if none)
- `LEDR[9]` - found, `LEDR[8]` - score valid, `LEDR[7]` - det enable

## Repo layout

```
final-design/
├── DE1_SOC_D8M_LB_RTL.v             # top-level: clocks, camera, pipeline, VGA, HEX/LEDs
├── rtl/
│   ├── object_detection/            # core detection pipeline (the interesting stuff)
│   │   ├── rgb_downsample_gray.v
│   │   ├── gaussian3x3_stream.v     
│   │   ├── sobel3x3_stream.v
│   │   ├── stream_delay_engine.v
│   │   ├── score_tree.v
│   │   ├── score_mac_tree.v
│   │   ├── sparse_template_matcher.v
│   │   ├── detection_logic.v
│   │   ├── vga_debug_mux.v
│   │   └── templates/               # generated .vh template includes
│   ├── camera_d8m/                  # Terasic D8M MIPI + RAW2RGB reference RTL
│   ├── autofocus/                   # Terasic D8M VCM autofocus reference RTL
│   ├── common/                      # SEG7_LUT, CLOCKMEM, FpsMonitor, I2C bits, reset
│   └── pll_test/                    # Quartus PLL IP (camera reference clock)
├── vga_pll/                         # Quartus PLL IP (25 MHz VGA clock)
├── synthesis/                       # Quartus project files (.qpf, .qsf, .sdc)
├── sim/                             # cocotb / ModelSim env (see sim/README.md)
├── python/
│   ├── pythonTemplateGen/           # template generators (image -> .vh)
│   └── posterpy/                    # poster figure renderer (OpenCV mock of pipeline)
├── objects/                         # reference images and generated debug overlays
└── docs/                            # Senior Design Final Paper
```

The RTL under `rtl/object_detection/` is the senior design contribution.
`rtl/camera_d8m/` and `rtl/autofocus/` are Terasic reference RTL shipped with
the D8M demo kit, unmodified except for instantiation in the top level.
`rtl/pll_test/` and `vga_pll/` are Quartus-generated PLL IP.

## Tech stack

- **HDL** - Verilog-2001 (synthesizable RTL)
- **Target** - Intel/Altera Cyclone V SoC (DE1-SoC, `5CSEMA5F31C6`)
- **Camera** - Terasic D8M-GPIO (8 MP MIPI module on GPIO header)
- **Synthesis** - Quartus Prime 20.1 Standard
- **Simulation** - ModelSim + cocotb (Python)
- **Python (sim + template gen)** - numpy, opencv-python, Pillow, cocotb>=1.9

## Build (Quartus)

1. Install Quartus Prime 20.1 Standard (or compatible) with Cyclone V device
   support.
2. Open `synthesis/DE1_SOC_D8M_LB_RTL.qpf`.
3. Processing -> Start Compilation.
4. Tools -> Programmer, load `output_files/DE1_SOC_D8M_LB_RTL.sof` onto the
   DE1-SoC over USB-Blaster II.

Pin assignments for the DE1-SoC + D8M (mounted on GPIO_1) and the VGA / HEX /
KEY / SW pins are all in `synthesis/DE1_SOC_D8M_LB_RTL.qsf`. Timing
constraints are in `DE1_SOC_D8M_LB_RTL.sdc`.

## Running on hardware

1. Plug the D8M camera into GPIO_1, connect VGA to a monitor.
2. Program the FPGA with the `.sof`.
3. Press `KEY[0]` to reset, `KEY[3]` to autofocus.
4. `SW[0]` up to enable detection, `SW[3]` up to draw the bounding box.
5. `SW[2:1]` cycles through camera / Sobel edge / signed score heatmap / mask
   views. The heatmap view is the most useful for tuning - it auto-contrasts
   per frame and shows where the matcher is scoring high.
6. Use `SW[9]` + `KEY[1]/KEY[2]` to tune the Sobel edge threshold and the
   detection threshold. Read the current value off HEX3:HEX2 and the detection
   confidence off HEX5:HEX4 when `LEDR[9]` lights.

## Generating a new template

Templates are produced by Python scripts from a reference image. Each script
reads its source image, runs the same downsample / grayscale / Gaussian Blur / Sobel chain in
software, picks the strongest `NUM_TAPS` edge pixels, and emits a `.vh` file
that gets `\`included` by `score_tree.v` at synthesis time.

```sh
# From the repo root, with numpy + opencv-python + Pillow installed:
python python/pythonTemplateGen/make_template_cow1.py    # cow,   64x64, 64 taps
python python/pythonTemplateGen/make_template_donut.py   # donut, 32x32, 64 taps
```

Outputs (per object) land in `rtl/object_detection/templates/*.vh` plus debug
images in `objects/<object>_<size>_<taps>tap/`. To switch the active template,
change the default `TEMPLATE_INCLUDE` macro in `score_tree.v` or define it on
the Quartus command line, and update `TEMPLATE_SIZE`, `NUM_TAPS`, `ROW_W`, and
`COL_W` in the top-level instantiation to match.

## Simulation

The cocotb environment under `sim/` is the easiest way to sanity-check the
matcher against a Python reference model without touching hardware. Full
instructions and a parameter-sweep smoke test are in `sim/README.md`. The
short version, from `sim/` on Windows PowerShell:

```powershell
.\scripts\setup_env.ps1      # creates sim/.venv, installs requirements
.\scripts\run_modelsim.ps1   # default sparse matcher test
```

Or from a shell with `make` and cocotb installed:

```sh
make -C sim
```

Available tests:

- `test_sparse_template_matcher.py` - full matcher vs. Python reference on a
  synthetic donut frame
- `test_sparse_template_matcher_cow.py` - same flow with the cow template
- `test_vga_heatmap_debug.py` - unsigned heatmap debug path
- `test_vga_signed_heatmap_autocontrast.py` - signed heatmap with per-frame
  autocontrast

## Team

Team Thomas, UC Davis (EEC 193):

- Max Madrigal
- Yaseen Alkhameri
- Justin Hsu
- Ricardo Gonzales
- Isidro Pulido



Advisor: Professor Anthony Thomas.

## AI use

The RTL, testbenches, and overall hardware architecture are our own work. 
The Python utilities under `python/pythonTemplateGen/` and `python/posterpy/`, and the cocotb
harness under `sim/`, were written with AI assistance. They are
supplementary - the matched-filter design itself is the point of the project.



