#==============================================================================
# AMBA AXI4 (burst-capable manager and subordinate) -- simulation build
#
# Simulator : Icarus Verilog (iverilog + vvp), waveform viewer: GTKWave
#
#   make test_slave    Level 1 : axi4_slave unit test
#   make test_master   Level 2 : axi4_master unit test with a mock slave
#   make test_top      Level 3 : manager wired to subordinate
#   make test_all      all of the above; non-zero exit if any test fails
#   make clean         remove simulation binaries and waveform dumps
#==============================================================================

IVERILOG  := iverilog
VVP       := vvp
IVFLAGS   := -g2005 -Wall

RTL_DIR   := rtl
SIM_DIR   := sim
BUILD_DIR := build

RTL_SRCS  := $(RTL_DIR)/axi4_slave.v \
             $(RTL_DIR)/axi4_master.v \
             $(RTL_DIR)/axi4_top.v

.PHONY: all test_all test_slave test_master test_top clean

all: test_all

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

test_slave: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_slave.vvp \
		$(RTL_DIR)/axi4_slave.v $(SIM_DIR)/tb_axi4_slave.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_slave.vvp | tee tb_axi4_slave.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_slave.log

test_master: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_master.vvp \
		$(RTL_DIR)/axi4_master.v $(SIM_DIR)/tb_axi4_master.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_master.vvp | tee tb_axi4_master.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_master.log

test_top: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_top.vvp \
		$(RTL_SRCS) $(SIM_DIR)/tb_axi4_top.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_top.vvp | tee tb_axi4_top.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_top.log

test_all: test_slave test_master test_top
	@echo ""
	@echo "================ all AXI4 test suites passed ================"

clean:
	rm -rf $(BUILD_DIR)
