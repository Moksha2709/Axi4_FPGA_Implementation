#==============================================================================
# AXI4 design -- simulation build (Icarus Verilog)
#
#   make test_slave   the slave on its own, driven by the testbench
#   make test_top     input DFFs -> master -> slave -> output DFFs
#   make test_all     both; non-zero exit if either fails
#   make clean        remove build output
#==============================================================================

IVERILOG  := iverilog
VVP       := vvp
IVFLAGS   := -g2005 -Wall
BUILD_DIR := build

.PHONY: all test_all test_slave test_top clean

all: test_all

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

test_slave: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_slave.vvp \
		rtl/axi4_slave.v sim/tb_axi4_slave.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_slave.vvp | tee tb_axi4_slave.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_slave.log

test_top: | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -o $(BUILD_DIR)/tb_axi4_top.vvp \
		rtl/axi4_in_dff.v rtl/axi4_out_dff.v rtl/axi4_slave.v rtl/axi4_master.v rtl/axi4_top.v \
		sim/tb_axi4_top.v
	cd $(BUILD_DIR) && $(VVP) tb_axi4_top.vvp | tee tb_axi4_top.log
	@! grep -q "TEST FAILED" $(BUILD_DIR)/tb_axi4_top.log

test_all: test_slave test_top
	@echo "================ all tests passed ================"

clean:
	rm -rf $(BUILD_DIR)
