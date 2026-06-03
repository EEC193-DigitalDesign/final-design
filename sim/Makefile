TOPLEVEL_LANG ?= verilog
SIM ?= modelsim
PYTHON ?= python

# Keep paths relative to this Makefile so `make -f sim/Makefile` and Windows shells work.
SIM_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PROJECT_ROOT := $(abspath $(SIM_DIR)/..)
RTL_DIR := $(PROJECT_ROOT)/rtl/object_detection
TEST_DIR := $(SIM_DIR)/tests

TOPLEVEL := sparse_template_matcher
MODULE := test_sparse_template_matcher

# Default matches the active Quartus design. The README shows how to override
# these with the smaller 16x16/5-tap smoke template.
TEST_WIDTH ?= 128
TEST_HEIGHT ?= 96
TEMPLATE_SIZE ?= 32
NUM_TAPS ?= 64
ROW_W ?= 5
COL_W ?= 5
FEATURE_W ?= 8
WEIGHT_W ?= 8
SCORE_W ?= 32
DONUT_X ?= 48
DONUT_Y ?= 32
TEMPLATE_INCLUDE ?= donut_edge_template_32.vh
TEMPLATE_VH ?= $(RTL_DIR)/templates/$(TEMPLATE_INCLUDE)

ifeq ($(OS),Windows_NT)
PATHSEP := ;
else
PATHSEP := :
endif

export TEST_WIDTH
export TEST_HEIGHT
export TEMPLATE_SIZE
export NUM_TAPS
export ROW_W
export COL_W
export FEATURE_W
export WEIGHT_W
export SCORE_W
export DONUT_X
export DONUT_Y
export TEMPLATE_INCLUDE
export TEMPLATE_VH
export PROJECT_ROOT
export OUTPUT_DIR ?= $(SIM_DIR)/output/sparse_matcher
export COCOTB_RESULTS_FILE ?= $(SIM_DIR)/logs/results_sparse_matcher.xml
export PYTHONPATH := $(TEST_DIR)$(PATHSEP)$(SIM_DIR)$(PATHSEP)$(PYTHONPATH)

SIM_BUILD ?= $(SIM_DIR)/build/sparse_matcher
$(shell $(PYTHON) -c "from pathlib import Path; [Path(p).mkdir(parents=True, exist_ok=True) for p in ['$(OUTPUT_DIR)', '$(SIM_DIR)/logs', '$(SIM_BUILD)']]")

VERILOG_SOURCES += $(RTL_DIR)/score_mac_tree.v
VERILOG_SOURCES += $(RTL_DIR)/stream_delay_engine.v
VERILOG_SOURCES += $(RTL_DIR)/score_tree.v
VERILOG_SOURCES += $(RTL_DIR)/sparse_template_matcher.v

COMPILE_ARGS += +incdir+$(RTL_DIR)/templates
COMPILE_ARGS += +incdir+$(RTL_DIR)
COMPILE_ARGS += +incdir+$(SIM_DIR)/templates
COMPILE_ARGS += +define+TEMPLATE_INCLUDE=\"$(TEMPLATE_INCLUDE)\"
SIM_ARGS += -gIMAGE_WIDTH=$(TEST_WIDTH)
SIM_ARGS += -gTEMPLATE_SIZE=$(TEMPLATE_SIZE)
SIM_ARGS += -gNUM_TAPS=$(NUM_TAPS)
SIM_ARGS += -gROW_W=$(ROW_W)
SIM_ARGS += -gCOL_W=$(COL_W)
SIM_ARGS += -gFEATURE_W=$(FEATURE_W)
SIM_ARGS += -gWEIGHT_W=$(WEIGHT_W)
SIM_ARGS += -gSCORE_W=$(SCORE_W)
SIM_ARGS += -l $(SIM_DIR)/logs/transcript_sparse_matcher.log
SIM_ARGS += -voptargs=+acc

COCOTB_MAKEFILES := $(shell $(PYTHON) -m cocotb_tools.config --makefiles)
ifeq ($(strip $(COCOTB_MAKEFILES)),)
$(error Could not locate cocotb Makefile.sim. Rebuild sim/.venv or run: $(PYTHON) -m pip install -r requirements.txt)
endif

include $(COCOTB_MAKEFILES)/Makefile.sim
