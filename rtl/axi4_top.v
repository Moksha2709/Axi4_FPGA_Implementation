//=============================================================================
// axi4_top.v  --  master, a D flip-flop stage at each end, and the slave
//
//   master --AW,W,AR--> [stage: master side] --> [stage: slave side] --> slave
//   master <--B,R------ [stage: master side] <-- [stage: slave side] <-- slave
//
// Every one of the five channels passes through two axi4_reg_stage blocks.
// Nothing else connects the master and the slave.
//
// What each stage carries (packed as one block):
//   AW : {AWID[3:0], AWADDR[31:0], AWLEN[7:0]}              44 bits
//   W  : {WDATA[31:0], WSTRB[3:0], WLAST}                   37 bits
//   B  : {BID[3:0], BRESP[1:0]}                              6 bits
//   AR : {ARID[3:0], ARADDR[31:0], ARLEN[7:0]}              44 bits
//   R  : {RID[3:0], RDATA[31:0], RRESP[1:0], RLAST}         39 bits
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_top (
    input  wire clk,
    input  wire resetn,
    output wire done,        // the master has finished its write and read
    output wire pass         // the data read back matched the data written
);

    //-------------------------------------------------------------------------
    // Master side of each channel (m_*), and slave side (s_*)
    //-------------------------------------------------------------------------
    // wires at the master
    wire [3:0]  m_awid;   wire [31:0] m_awaddr;  wire [7:0] m_awlen;
    wire        m_awvalid, m_awready;
    wire [31:0] m_wdata;  wire [3:0]  m_wstrb;   wire m_wlast;
    wire        m_wvalid, m_wready;
    wire [3:0]  m_bid;    wire [1:0]  m_bresp;
    wire        m_bvalid, m_bready;
    wire [3:0]  m_arid;   wire [31:0] m_araddr;  wire [7:0] m_arlen;
    wire        m_arvalid, m_arready;
    wire [3:0]  m_rid;    wire [31:0] m_rdata;   wire [1:0] m_rresp;
    wire        m_rlast, m_rvalid, m_rready;

    // wires at the slave
    wire [43:0] aw_s_data;  wire aw_s_valid, aw_s_ready;
    wire [36:0] w_s_data;   wire w_s_valid,  w_s_ready;
    wire [43:0] ar_s_data;  wire ar_s_valid, ar_s_ready;
    wire [3:0]  s_bid, s_rid;
    wire [1:0]  s_bresp, s_rresp;
    wire [31:0] s_rdata;
    wire        s_rlast, s_bvalid, s_bready, s_rvalid, s_rready;

    // wires between the two stages of a channel
    wire [43:0] aw_x_data;  wire aw_x_valid, aw_x_ready;
    wire [36:0] w_x_data;   wire w_x_valid,  w_x_ready;
    wire [43:0] ar_x_data;  wire ar_x_valid, ar_x_ready;
    wire [5:0]  b_x_data;   wire b_x_valid,  b_x_ready;
    wire [38:0] r_x_data;   wire r_x_valid,  r_x_ready;

    //-------------------------------------------------------------------------
    // The master and the slave
    //-------------------------------------------------------------------------
    axi4_master u_master (
        .clk (clk), .resetn (resetn),
        .M_AXI_AWID (m_awid), .M_AXI_AWADDR (m_awaddr), .M_AXI_AWLEN (m_awlen),
        .M_AXI_AWVALID (m_awvalid), .M_AXI_AWREADY (m_awready),
        .M_AXI_WDATA (m_wdata), .M_AXI_WSTRB (m_wstrb), .M_AXI_WLAST (m_wlast),
        .M_AXI_WVALID (m_wvalid), .M_AXI_WREADY (m_wready),
        .M_AXI_BID (m_bid), .M_AXI_BRESP (m_bresp),
        .M_AXI_BVALID (m_bvalid), .M_AXI_BREADY (m_bready),
        .M_AXI_ARID (m_arid), .M_AXI_ARADDR (m_araddr), .M_AXI_ARLEN (m_arlen),
        .M_AXI_ARVALID (m_arvalid), .M_AXI_ARREADY (m_arready),
        .M_AXI_RID (m_rid), .M_AXI_RDATA (m_rdata), .M_AXI_RRESP (m_rresp),
        .M_AXI_RLAST (m_rlast), .M_AXI_RVALID (m_rvalid), .M_AXI_RREADY (m_rready),
        .done (done), .pass (pass)
    );

    axi4_slave u_slave (
        .S_AXI_ACLK (clk), .S_AXI_ARESETN (resetn),
        .S_AXI_AWID (aw_s_data[43:40]), .S_AXI_AWADDR (aw_s_data[39:8]),
        .S_AXI_AWLEN (aw_s_data[7:0]),
        .S_AXI_AWVALID (aw_s_valid), .S_AXI_AWREADY (aw_s_ready),
        .S_AXI_WDATA (w_s_data[36:5]), .S_AXI_WSTRB (w_s_data[4:1]),
        .S_AXI_WLAST (w_s_data[0]),
        .S_AXI_WVALID (w_s_valid), .S_AXI_WREADY (w_s_ready),
        .S_AXI_BID (s_bid), .S_AXI_BRESP (s_bresp),
        .S_AXI_BVALID (s_bvalid), .S_AXI_BREADY (s_bready),
        .S_AXI_ARID (ar_s_data[43:40]), .S_AXI_ARADDR (ar_s_data[39:8]),
        .S_AXI_ARLEN (ar_s_data[7:0]),
        .S_AXI_ARVALID (ar_s_valid), .S_AXI_ARREADY (ar_s_ready),
        .S_AXI_RID (s_rid), .S_AXI_RDATA (s_rdata), .S_AXI_RRESP (s_rresp),
        .S_AXI_RLAST (s_rlast), .S_AXI_RVALID (s_rvalid), .S_AXI_RREADY (s_rready)
    );

    //-------------------------------------------------------------------------
    // AW : master -> master side -> slave side -> slave
    //-------------------------------------------------------------------------
    axi4_reg_stage #(.WIDTH(44)) aw_master_side (
        .clk (clk), .resetn (resetn),
        .in_data  ({m_awid, m_awaddr, m_awlen}),
        .in_valid (m_awvalid),  .in_ready (m_awready),
        .out_data (aw_x_data),  .out_valid (aw_x_valid), .out_ready (aw_x_ready));

    axi4_reg_stage #(.WIDTH(44)) aw_slave_side (
        .clk (clk), .resetn (resetn),
        .in_data  (aw_x_data),  .in_valid (aw_x_valid),  .in_ready (aw_x_ready),
        .out_data (aw_s_data),  .out_valid (aw_s_valid), .out_ready (aw_s_ready));

    //-------------------------------------------------------------------------
    // W : master -> master side -> slave side -> slave
    //-------------------------------------------------------------------------
    axi4_reg_stage #(.WIDTH(37)) w_master_side (
        .clk (clk), .resetn (resetn),
        .in_data  ({m_wdata, m_wstrb, m_wlast}),
        .in_valid (m_wvalid),   .in_ready (m_wready),
        .out_data (w_x_data),   .out_valid (w_x_valid),  .out_ready (w_x_ready));

    axi4_reg_stage #(.WIDTH(37)) w_slave_side (
        .clk (clk), .resetn (resetn),
        .in_data  (w_x_data),   .in_valid (w_x_valid),   .in_ready (w_x_ready),
        .out_data (w_s_data),   .out_valid (w_s_valid),  .out_ready (w_s_ready));

    //-------------------------------------------------------------------------
    // AR : master -> master side -> slave side -> slave
    //-------------------------------------------------------------------------
    axi4_reg_stage #(.WIDTH(44)) ar_master_side (
        .clk (clk), .resetn (resetn),
        .in_data  ({m_arid, m_araddr, m_arlen}),
        .in_valid (m_arvalid),  .in_ready (m_arready),
        .out_data (ar_x_data),  .out_valid (ar_x_valid), .out_ready (ar_x_ready));

    axi4_reg_stage #(.WIDTH(44)) ar_slave_side (
        .clk (clk), .resetn (resetn),
        .in_data  (ar_x_data),  .in_valid (ar_x_valid),  .in_ready (ar_x_ready),
        .out_data (ar_s_data),  .out_valid (ar_s_valid), .out_ready (ar_s_ready));

    //-------------------------------------------------------------------------
    // B : slave -> slave side -> master side -> master
    //-------------------------------------------------------------------------
    axi4_reg_stage #(.WIDTH(6)) b_slave_side (
        .clk (clk), .resetn (resetn),
        .in_data  ({s_bid, s_bresp}),
        .in_valid (s_bvalid),   .in_ready (s_bready),
        .out_data (b_x_data),   .out_valid (b_x_valid),  .out_ready (b_x_ready));

    axi4_reg_stage #(.WIDTH(6)) b_master_side (
        .clk (clk), .resetn (resetn),
        .in_data  (b_x_data),   .in_valid (b_x_valid),   .in_ready (b_x_ready),
        .out_data ({m_bid, m_bresp}),
        .out_valid (m_bvalid),  .out_ready (m_bready));

    //-------------------------------------------------------------------------
    // R : slave -> slave side -> master side -> master
    //-------------------------------------------------------------------------
    axi4_reg_stage #(.WIDTH(39)) r_slave_side (
        .clk (clk), .resetn (resetn),
        .in_data  ({s_rid, s_rdata, s_rresp, s_rlast}),
        .in_valid (s_rvalid),   .in_ready (s_rready),
        .out_data (r_x_data),   .out_valid (r_x_valid),  .out_ready (r_x_ready));

    axi4_reg_stage #(.WIDTH(39)) r_master_side (
        .clk (clk), .resetn (resetn),
        .in_data  (r_x_data),   .in_valid (r_x_valid),   .in_ready (r_x_ready),
        .out_data ({m_rid, m_rdata, m_rresp, m_rlast}),
        .out_valid (m_rvalid),  .out_ready (m_rready));

endmodule

`default_nettype wire
