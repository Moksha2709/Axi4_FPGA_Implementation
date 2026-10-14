//=============================================================================
// axi4_top.v
//
// Integration wrapper: one AXI4 manager talking to one AXI4 subordinate
// THROUGH A REGISTERED (D-flip-flop) STAGE ON EVERY ONE OF THE FIVE CHANNELS.
//
//   master ──AW──►[FF]──►  slave          forward channels : AW, W, AR
//   master ──W───►[FF]──►  slave
//   master ──AR──►[FF]──►  slave
//   master ◄──[FF]◄──B───  slave          reverse channels : B, R
//   master ◄──[FF]◄──R───  slave
//
// Each [FF] is an axi4_skid_buffer, so the payload, VALID and READY of every
// channel are all driven from flip-flops and nothing crosses between the two
// modules combinationally.  Cost is one clock of latency per channel;
// throughput is unchanged at one beat per clock, so a 256-beat burst still
// streams back to back.  This is the same structure Xilinx ships as the
// "AXI Register Slice", and it is what lets the two modules be placed far
// apart on the die and still close timing.
//
// Payload carried through each stage
//   AW/AR : {ID, ADDR, LEN[8], SIZE[3], BURST[2], LOCK, CACHE[4], PROT[3], QOS[4]}
//   W     : {WDATA, WSTRB, WLAST}
//   B     : {BID, BRESP[2]}
//   R     : {RID, RDATA, RRESP[2], RLAST}
//
// Set PIPE_STAGE = 0 to bypass every stage and wire the two modules directly,
// which is useful for comparing latency in simulation.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_top #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_ADDR_BITS = 12,
    parameter PIPE_STAGE    = 1          // 1 = registered channels, 0 = direct
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // ---- Host command port -------------------------------------------------
    input  wire                      cmd_start_write,
    input  wire                      cmd_start_read,
    input  wire [ID_WIDTH-1:0]       cmd_id,
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [7:0]                cmd_len,
    input  wire [2:0]                cmd_size,
    input  wire [1:0]                cmd_burst,
    output wire                      cmd_busy,
    output wire                      cmd_done,
    output wire [1:0]                cmd_resp,
    output wire [ID_WIDTH-1:0]       cmd_resp_id,
    output wire                      cmd_last_err,

    // ---- Host write data stream -------------------------------------------
    input  wire [DATA_WIDTH-1:0]     hw_data,
    input  wire [(DATA_WIDTH/8)-1:0] hw_strb,
    input  wire                      hw_valid,
    output wire                      hw_ready,

    // ---- Host read data stream --------------------------------------------
    output wire [DATA_WIDTH-1:0]     hr_data,
    output wire [1:0]                hr_resp,
    output wire                      hr_last,
    output wire                      hr_valid,
    input  wire                      hr_ready
);

    localparam STRB_WIDTH = DATA_WIDTH/8;

    // Channel payload widths for the pipeline stages
    localparam AX_WIDTH = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2 + 1 + 4 + 3 + 4;
    localparam W_WIDTH  = DATA_WIDTH + STRB_WIDTH + 1;
    localparam B_WIDTH  = ID_WIDTH + 2;
    localparam R_WIDTH  = ID_WIDTH + DATA_WIDTH + 2 + 1;

    //-------------------------------------------------------------------------
    // Manager-side (m_*) and subordinate-side (s_*) channel nets
    //-------------------------------------------------------------------------
    wire [ID_WIDTH-1:0]   m_awid,    s_awid;
    wire [ADDR_WIDTH-1:0] m_awaddr,  s_awaddr;
    wire [7:0]            m_awlen,   s_awlen;
    wire [2:0]            m_awsize,  s_awsize;
    wire [1:0]            m_awburst, s_awburst;
    wire                  m_awlock,  s_awlock;
    wire [3:0]            m_awcache, s_awcache;
    wire [2:0]            m_awprot,  s_awprot;
    wire [3:0]            m_awqos,   s_awqos;
    wire                  m_awvalid, s_awvalid;
    wire                  m_awready, s_awready;

    wire [DATA_WIDTH-1:0] m_wdata,   s_wdata;
    wire [STRB_WIDTH-1:0] m_wstrb,   s_wstrb;
    wire                  m_wlast,   s_wlast;
    wire                  m_wvalid,  s_wvalid;
    wire                  m_wready,  s_wready;

    wire [ID_WIDTH-1:0]   m_bid,     s_bid;
    wire [1:0]            m_bresp,   s_bresp;
    wire                  m_bvalid,  s_bvalid;
    wire                  m_bready,  s_bready;

    wire [ID_WIDTH-1:0]   m_arid,    s_arid;
    wire [ADDR_WIDTH-1:0] m_araddr,  s_araddr;
    wire [7:0]            m_arlen,   s_arlen;
    wire [2:0]            m_arsize,  s_arsize;
    wire [1:0]            m_arburst, s_arburst;
    wire                  m_arlock,  s_arlock;
    wire [3:0]            m_arcache, s_arcache;
    wire [2:0]            m_arprot,  s_arprot;
    wire [3:0]            m_arqos,   s_arqos;
    wire                  m_arvalid, s_arvalid;
    wire                  m_arready, s_arready;

    wire [ID_WIDTH-1:0]   m_rid,     s_rid;
    wire [DATA_WIDTH-1:0] m_rdata,   s_rdata;
    wire [1:0]            m_rresp,   s_rresp;
    wire                  m_rlast,   s_rlast;
    wire                  m_rvalid,  s_rvalid;
    wire                  m_rready,  s_rready;

    //-------------------------------------------------------------------------
    // The five D-flip-flop pipeline stages
    //-------------------------------------------------------------------------
    generate
    if (PIPE_STAGE != 0) begin : g_registered

        // ---- AW ------------------------------------------------------------
        wire [AX_WIDTH-1:0] aw_in = {m_awid, m_awaddr, m_awlen, m_awsize,
                                     m_awburst, m_awlock, m_awcache,
                                     m_awprot, m_awqos};
        wire [AX_WIDTH-1:0] aw_out;
        axi4_skid_buffer #(.WIDTH(AX_WIDTH)) u_aw_ff (
            .ACLK (ACLK), .ARESETn (ARESETn),
            .in_data (aw_in),  .in_valid (m_awvalid), .in_ready (m_awready),
            .out_data(aw_out), .out_valid(s_awvalid), .out_ready(s_awready)
        );
        assign {s_awid, s_awaddr, s_awlen, s_awsize, s_awburst, s_awlock,
                s_awcache, s_awprot, s_awqos} = aw_out;

        // ---- W -------------------------------------------------------------
        wire [W_WIDTH-1:0] w_in = {m_wdata, m_wstrb, m_wlast};
        wire [W_WIDTH-1:0] w_out;
        axi4_skid_buffer #(.WIDTH(W_WIDTH)) u_w_ff (
            .ACLK (ACLK), .ARESETn (ARESETn),
            .in_data (w_in),  .in_valid (m_wvalid), .in_ready (m_wready),
            .out_data(w_out), .out_valid(s_wvalid), .out_ready(s_wready)
        );
        assign {s_wdata, s_wstrb, s_wlast} = w_out;

        // ---- B : subordinate is the transmitter ----------------------------
        wire [B_WIDTH-1:0] b_in = {s_bid, s_bresp};
        wire [B_WIDTH-1:0] b_out;
        axi4_skid_buffer #(.WIDTH(B_WIDTH)) u_b_ff (
            .ACLK (ACLK), .ARESETn (ARESETn),
            .in_data (b_in),  .in_valid (s_bvalid), .in_ready (s_bready),
            .out_data(b_out), .out_valid(m_bvalid), .out_ready(m_bready)
        );
        assign {m_bid, m_bresp} = b_out;

        // ---- AR ------------------------------------------------------------
        wire [AX_WIDTH-1:0] ar_in = {m_arid, m_araddr, m_arlen, m_arsize,
                                     m_arburst, m_arlock, m_arcache,
                                     m_arprot, m_arqos};
        wire [AX_WIDTH-1:0] ar_out;
        axi4_skid_buffer #(.WIDTH(AX_WIDTH)) u_ar_ff (
            .ACLK (ACLK), .ARESETn (ARESETn),
            .in_data (ar_in),  .in_valid (m_arvalid), .in_ready (m_arready),
            .out_data(ar_out), .out_valid(s_arvalid), .out_ready(s_arready)
        );
        assign {s_arid, s_araddr, s_arlen, s_arsize, s_arburst, s_arlock,
                s_arcache, s_arprot, s_arqos} = ar_out;

        // ---- R : subordinate is the transmitter ----------------------------
        wire [R_WIDTH-1:0] r_in = {s_rid, s_rdata, s_rresp, s_rlast};
        wire [R_WIDTH-1:0] r_out;
        axi4_skid_buffer #(.WIDTH(R_WIDTH)) u_r_ff (
            .ACLK (ACLK), .ARESETn (ARESETn),
            .in_data (r_in),  .in_valid (s_rvalid), .in_ready (s_rready),
            .out_data(r_out), .out_valid(m_rvalid), .out_ready(m_rready)
        );
        assign {m_rid, m_rdata, m_rresp, m_rlast} = r_out;

    end else begin : g_direct

        assign s_awid    = m_awid;
        assign s_awaddr  = m_awaddr;
        assign s_awlen   = m_awlen;
        assign s_awsize  = m_awsize;
        assign s_awburst = m_awburst;
        assign s_awlock  = m_awlock;
        assign s_awcache = m_awcache;
        assign s_awprot  = m_awprot;
        assign s_awqos   = m_awqos;
        assign s_awvalid = m_awvalid;
        assign m_awready = s_awready;

        assign s_wdata   = m_wdata;
        assign s_wstrb   = m_wstrb;
        assign s_wlast   = m_wlast;
        assign s_wvalid  = m_wvalid;
        assign m_wready  = s_wready;

        assign m_bid     = s_bid;
        assign m_bresp   = s_bresp;
        assign m_bvalid  = s_bvalid;
        assign s_bready  = m_bready;

        assign s_arid    = m_arid;
        assign s_araddr  = m_araddr;
        assign s_arlen   = m_arlen;
        assign s_arsize  = m_arsize;
        assign s_arburst = m_arburst;
        assign s_arlock  = m_arlock;
        assign s_arcache = m_arcache;
        assign s_arprot  = m_arprot;
        assign s_arqos   = m_arqos;
        assign s_arvalid = m_arvalid;
        assign m_arready = s_arready;

        assign m_rid     = s_rid;
        assign m_rdata   = s_rdata;
        assign m_rresp   = s_rresp;
        assign m_rlast   = s_rlast;
        assign m_rvalid  = s_rvalid;
        assign s_rready  = m_rready;

    end
    endgenerate

    //-------------------------------------------------------------------------
    axi4_master #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_master (
        .M_AXI_ACLK      (ACLK),
        .M_AXI_ARESETN   (ARESETn),

        .cmd_start_write (cmd_start_write),
        .cmd_start_read  (cmd_start_read),
        .cmd_id          (cmd_id),
        .cmd_addr        (cmd_addr),
        .cmd_len         (cmd_len),
        .cmd_size        (cmd_size),
        .cmd_burst       (cmd_burst),
        .cmd_busy        (cmd_busy),
        .cmd_done        (cmd_done),
        .cmd_resp        (cmd_resp),
        .cmd_resp_id     (cmd_resp_id),
        .cmd_last_err    (cmd_last_err),

        .hw_data         (hw_data),
        .hw_strb         (hw_strb),
        .hw_valid        (hw_valid),
        .hw_ready        (hw_ready),

        .hr_data         (hr_data),
        .hr_resp         (hr_resp),
        .hr_last         (hr_last),
        .hr_valid        (hr_valid),
        .hr_ready        (hr_ready),

        .M_AXI_AWID      (m_awid),
        .M_AXI_AWADDR    (m_awaddr),
        .M_AXI_AWLEN     (m_awlen),
        .M_AXI_AWSIZE    (m_awsize),
        .M_AXI_AWBURST   (m_awburst),
        .M_AXI_AWLOCK    (m_awlock),
        .M_AXI_AWCACHE   (m_awcache),
        .M_AXI_AWPROT    (m_awprot),
        .M_AXI_AWQOS     (m_awqos),
        .M_AXI_AWVALID   (m_awvalid),
        .M_AXI_AWREADY   (m_awready),

        .M_AXI_WDATA     (m_wdata),
        .M_AXI_WSTRB     (m_wstrb),
        .M_AXI_WLAST     (m_wlast),
        .M_AXI_WVALID    (m_wvalid),
        .M_AXI_WREADY    (m_wready),

        .M_AXI_BID       (m_bid),
        .M_AXI_BRESP     (m_bresp),
        .M_AXI_BVALID    (m_bvalid),
        .M_AXI_BREADY    (m_bready),

        .M_AXI_ARID      (m_arid),
        .M_AXI_ARADDR    (m_araddr),
        .M_AXI_ARLEN     (m_arlen),
        .M_AXI_ARSIZE    (m_arsize),
        .M_AXI_ARBURST   (m_arburst),
        .M_AXI_ARLOCK    (m_arlock),
        .M_AXI_ARCACHE   (m_arcache),
        .M_AXI_ARPROT    (m_arprot),
        .M_AXI_ARQOS     (m_arqos),
        .M_AXI_ARVALID   (m_arvalid),
        .M_AXI_ARREADY   (m_arready),

        .M_AXI_RID       (m_rid),
        .M_AXI_RDATA     (m_rdata),
        .M_AXI_RRESP     (m_rresp),
        .M_AXI_RLAST     (m_rlast),
        .M_AXI_RVALID    (m_rvalid),
        .M_AXI_RREADY    (m_rready)
    );

    //-------------------------------------------------------------------------
    axi4_slave #(
        .ID_WIDTH      (ID_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_ADDR_BITS (MEM_ADDR_BITS)
    ) u_slave (
        .S_AXI_ACLK      (ACLK),
        .S_AXI_ARESETN   (ARESETn),

        .S_AXI_AWID      (s_awid),
        .S_AXI_AWADDR    (s_awaddr),
        .S_AXI_AWLEN     (s_awlen),
        .S_AXI_AWSIZE    (s_awsize),
        .S_AXI_AWBURST   (s_awburst),
        .S_AXI_AWLOCK    (s_awlock),
        .S_AXI_AWCACHE   (s_awcache),
        .S_AXI_AWPROT    (s_awprot),
        .S_AXI_AWQOS     (s_awqos),
        .S_AXI_AWVALID   (s_awvalid),
        .S_AXI_AWREADY   (s_awready),

        .S_AXI_WDATA     (s_wdata),
        .S_AXI_WSTRB     (s_wstrb),
        .S_AXI_WLAST     (s_wlast),
        .S_AXI_WVALID    (s_wvalid),
        .S_AXI_WREADY    (s_wready),

        .S_AXI_BID       (s_bid),
        .S_AXI_BRESP     (s_bresp),
        .S_AXI_BVALID    (s_bvalid),
        .S_AXI_BREADY    (s_bready),

        .S_AXI_ARID      (s_arid),
        .S_AXI_ARADDR    (s_araddr),
        .S_AXI_ARLEN     (s_arlen),
        .S_AXI_ARSIZE    (s_arsize),
        .S_AXI_ARBURST   (s_arburst),
        .S_AXI_ARLOCK    (s_arlock),
        .S_AXI_ARCACHE   (s_arcache),
        .S_AXI_ARPROT    (s_arprot),
        .S_AXI_ARQOS     (s_arqos),
        .S_AXI_ARVALID   (s_arvalid),
        .S_AXI_ARREADY   (s_arready),

        .S_AXI_RID       (s_rid),
        .S_AXI_RDATA     (s_rdata),
        .S_AXI_RRESP     (s_rresp),
        .S_AXI_RLAST     (s_rlast),
        .S_AXI_RVALID    (s_rvalid),
        .S_AXI_RREADY    (s_rready)
    );

endmodule

`default_nettype wire
