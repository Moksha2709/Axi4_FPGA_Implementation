#==============================================================================
# AMBA AXI4 (full, burst-capable) -- simulation build
#
# Simulator : Icarus Verilog (iverilog + vvp), waveform viewer: GTKWave
#
# Targets
#   make test_slave        Level 1 : axi4_slave unit test
#   make test_master       Level 2 : axi4_master unit test with a mock slave
#   make test_top          Level 3 : integration, D-flip-flop channel stages
#   make test_top_direct   Level 3 : same test, modules wired directly
#   make test_all          all of the above; non-zero exit if any test fails
#   make wave_slave        open the Level 1 waveform in GTKWave
#   make wave_master       open the Level 2 waveform
#   make wave_top          open the Level 3 waveform
#   make clean             remove simulation binaries and .vcd dumps
#==============================================================================

IVERILOG  := iverilog
VVP       := vvp
GTKWAVE   := gtkwave

# -g2005 enables Verilog-2005 constructs; the RTL itself stays Verilog-2001.
IVFLAGS   := -g2005 -Wall

RTL_DIR   := rtl
SIM_DIR   := sim
BUILD_DIR := build

RTL_SRCS  := $(RTL_DIR)/axi4_skid_buffer.v \
             $(RTL_DIR)/axi4_slave.v \
             $(RTL_DIR)/axi4_master.v \
             $(RTL_DIR)/axi4_top.v

.PHONY: all test_all test_slave test_master test_top test_top_direct \
        wave_slave wave_master wave_top clean

all: test_all

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

#------------------------------------------------------------------------------
# Level 1 : subordinate
#------------------------------------------------------------------------------
test_slave: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_slave.vvp \
		$(RTL_DIR)/axi4_slave.v $(SIM_DIR)/tb_axi4_slave.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_slave.vvp | tee tb_axi4_slave.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_slave.log

#------------------------------------------------------------------------------
# Level 2 : manager against a programmable mock subordinate
#------------------------------------------------------------------------------
test_master: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_master.vvp \
		$(RTL_DIR)/axi4_master.v $(SIM_DIR)/tb_axi4_master.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_master.vvp | tee tb_axi4_master.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_master.log

#------------------------------------------------------------------------------
# Level 3 : full system through the D-flip-flop channel stages
#------------------------------------------------------------------------------
test_top: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_top.vvp \
		$(RTL_SRCS) $(SIM_DIR)/tb_axi4_top.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_top.vvp | tee tb_axi4_top.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_top.log

# Same stimulus with the pipeline stages bypassed, for a latency comparison.
test_top_direct: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -Ptb_axi4_top.PIPE_STAGE=0 \
		-o $(BUILD_DIR)/tb_axi4_top_direct.vvp \
		$(RTL_SRCS) $(SIM_DIR)/tb_axi4_top.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_top_direct.vvp | tee tb_axi4_top_direct.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_top_direct.log

#------------------------------------------------------------------------------
test_all: test_slave test_master test_top test_top_direct
	@echo ""
	@echo "================ all AXI4 test suites passed ================"

#------------------------------------------------------------------------------
wave_slave:
	$(GTKWAVE) $(BUILD_DIR)/tb_axi4_slave.vcd &

wave_master:
	$(GTKWAVE) $(BUILD_DIR)/tb_axi4_master.vcd &

wave_top:
	$(GTKWAVE) $(BUILD_DIR)/tb_axi4_top.vcd &

#------------------------------------------------------------------------------
clean:
	rm -rf $(BUILD_DIR)
