//=============================================================================
// axi4_top.v  --  input DFFs -> master -> slave -> output DFFs
//
//   testbench                                                      testbench
//      |                                                               ^
//      v                                                               |
//   [ in DFF ] --> master ==AW,W,B,AR,R (direct)== slave      master --> [ out DFF ]
//
// The master and the slave are connected directly: the five AXI4 channels go
// straight across, with nothing in between.
//
// The testbench loads the address and four words into the input DFFs
// (load, load_sel, load_data), then raises start.  When done goes high the
// words that came back are in the output DFFs (rd0..rd3), and pass says
// they equal what was loaded.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_top (
    input  wire        clk,
    input  wire        resetn,

    // ---- fill the input flip-flops -----------------------------------------
    input  wire        load,
    input  wire [2:0]  load_sel,         // 0 = address, 1..4 = the four words
    input  wire [31:0] load_data,

    // ---- run it ------------------------------------------------------------
    input  wire        start,
    output wire        done,             // the write and the read have finished
    output wire        pass,             // read-back words equal the loaded words

    // ---- what came back (output flip-flops) --------------------------------
    output wire [31:0] rd0,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    output wire [31:0] rd3
);

    // input flip-flops -> master
    wire [31:0] addr, d0, d1, d2, d3;

    // master -> output flip-flops
    wire        rd_valid;
    wire [1:0]  rd_idx;
    wire [31:0] rd_data;

    // the five channels, master <-> slave
    wire [3:0]  awid;   wire [31:0] awaddr;  wire [7:0] awlen;
    wire        awvalid, awready;
    wire [31:0] wdata;  wire [3:0]  wstrb;   wire wlast;
    wire        wvalid, wready;
    wire [3:0]  bid;    wire [1:0]  bresp;
    wire        bvalid, bready;
    wire [3:0]  arid;   wire [31:0] araddr;  wire [7:0] arlen;
    wire        arvalid, arready;
    wire [3:0]  rid;    wire [31:0] rdata;   wire [1:0] rresp;
    wire        rlast, rvalid, rready;

    //-------------------------------------------------------------------------
    axi4_in_dff u_in (
        .clk (clk), .resetn (resetn),
        .load (load), .load_sel (load_sel), .load_data (load_data),
        .addr (addr), .data0 (d0), .data1 (d1), .data2 (d2), .data3 (d3)
    );

    axi4_master u_master (
        .clk (clk), .resetn (resetn),
        .start (start), .done (done),
        .addr_in (addr), .data_in0 (d0), .data_in1 (d1),
        .data_in2 (d2),  .data_in3 (d3),
        .rd_valid (rd_valid), .rd_idx (rd_idx), .rd_data (rd_data),
        .M_AXI_AWID (awid), .M_AXI_AWADDR (awaddr), .M_AXI_AWLEN (awlen),
        .M_AXI_AWVALID (awvalid), .M_AXI_AWREADY (awready),
        .M_AXI_WDATA (wdata), .M_AXI_WSTRB (wstrb), .M_AXI_WLAST (wlast),
        .M_AXI_WVALID (wvalid), .M_AXI_WREADY (wready),
        .M_AXI_BID (bid), .M_AXI_BRESP (bresp),
        .M_AXI_BVALID (bvalid), .M_AXI_BREADY (bready),
        .M_AXI_ARID (arid), .M_AXI_ARADDR (araddr), .M_AXI_ARLEN (arlen),
        .M_AXI_ARVALID (arvalid), .M_AXI_ARREADY (arready),
        .M_AXI_RID (rid), .M_AXI_RDATA (rdata), .M_AXI_RRESP (rresp),
        .M_AXI_RLAST (rlast), .M_AXI_RVALID (rvalid), .M_AXI_RREADY (rready)
    );

    axi4_slave u_slave (
        .S_AXI_ACLK (clk), .S_AXI_ARESETN (resetn),
        .S_AXI_AWID (awid), .S_AXI_AWADDR (awaddr), .S_AXI_AWLEN (awlen),
        .S_AXI_AWVALID (awvalid), .S_AXI_AWREADY (awready),
        .S_AXI_WDATA (wdata), .S_AXI_WSTRB (wstrb), .S_AXI_WLAST (wlast),
        .S_AXI_WVALID (wvalid), .S_AXI_WREADY (wready),
        .S_AXI_BID (bid), .S_AXI_BRESP (bresp),
        .S_AXI_BVALID (bvalid), .S_AXI_BREADY (bready),
        .S_AXI_ARID (arid), .S_AXI_ARADDR (araddr), .S_AXI_ARLEN (arlen),
        .S_AXI_ARVALID (arvalid), .S_AXI_ARREADY (arready),
        .S_AXI_RID (rid), .S_AXI_RDATA (rdata), .S_AXI_RRESP (rresp),
        .S_AXI_RLAST (rlast), .S_AXI_RVALID (rvalid), .S_AXI_RREADY (rready)
    );

    axi4_out_dff u_out (
        .clk (clk), .resetn (resetn),
        .rd_valid (rd_valid), .rd_idx (rd_idx), .rd_data (rd_data),
        .q0 (rd0), .q1 (rd1), .q2 (rd2), .q3 (rd3)
    );

    //-------------------------------------------------------------------------
    // pass: finished, and the four words that came back equal the four loaded
    //-------------------------------------------------------------------------
    assign pass = done && (rd0 == d0) && (rd1 == d1) && (rd2 == d2) && (rd3 == d3);

endmodule

`default_nettype wire
