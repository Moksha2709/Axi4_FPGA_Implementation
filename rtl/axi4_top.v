//=============================================================================
// axi4_top.v
//
// One AXI4 manager wired directly to one AXI4 subordinate.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_top #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_ADDR_BITS = 12
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // Host: command
    input  wire                      cmd_start_write,
    input  wire                      cmd_start_read,
    input  wire [ID_WIDTH-1:0]       cmd_id,
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [7:0]                cmd_len,
    input  wire [2:0]                cmd_size,
    input  wire [1:0]                cmd_burst,
    output wire                      cmd_done,
    output wire [1:0]                cmd_resp,

    // Host: write data in
    input  wire [DATA_WIDTH-1:0]     hw_data,
    input  wire [(DATA_WIDTH/8)-1:0] hw_strb,
    input  wire                      hw_valid,
    output wire                      hw_ready,

    // Host: read data out
    output wire [DATA_WIDTH-1:0]     hr_data,
    output wire                      hr_valid,
    input  wire                      hr_ready
);

    localparam STRB_WIDTH = DATA_WIDTH/8;

    wire [ID_WIDTH-1:0]   awid;
    wire [ADDR_WIDTH-1:0] awaddr;
    wire [7:0]            awlen;
    wire [2:0]            awsize;
    wire [1:0]            awburst;
    wire                  awlock;
    wire [3:0]            awcache;
    wire [2:0]            awprot;
    wire [3:0]            awqos;
    wire                  awvalid, awready;

    wire [DATA_WIDTH-1:0] wdata;
    wire [STRB_WIDTH-1:0] wstrb;
    wire                  wlast, wvalid, wready;

    wire [ID_WIDTH-1:0]   bid;
    wire [1:0]            bresp;
    wire                  bvalid, bready;

    wire [ID_WIDTH-1:0]   arid;
    wire [ADDR_WIDTH-1:0] araddr;
    wire [7:0]            arlen;
    wire [2:0]            arsize;
    wire [1:0]            arburst;
    wire                  arlock;
    wire [3:0]            arcache;
    wire [2:0]            arprot;
    wire [3:0]            arqos;
    wire                  arvalid, arready;

    wire [ID_WIDTH-1:0]   rid;
    wire [DATA_WIDTH-1:0] rdata;
    wire [1:0]            rresp;
    wire                  rlast, rvalid, rready;

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
        .cmd_done        (cmd_done),
        .cmd_resp        (cmd_resp),

        .hw_data         (hw_data),
        .hw_strb         (hw_strb),
        .hw_valid        (hw_valid),
        .hw_ready        (hw_ready),

        .hr_data         (hr_data),
        .hr_valid        (hr_valid),
        .hr_ready        (hr_ready),

        .M_AXI_AWID      (awid),
        .M_AXI_AWADDR    (awaddr),
        .M_AXI_AWLEN     (awlen),
        .M_AXI_AWSIZE    (awsize),
        .M_AXI_AWBURST   (awburst),
        .M_AXI_AWLOCK    (awlock),
        .M_AXI_AWCACHE   (awcache),
        .M_AXI_AWPROT    (awprot),
        .M_AXI_AWQOS     (awqos),
        .M_AXI_AWVALID   (awvalid),
        .M_AXI_AWREADY   (awready),

        .M_AXI_WDATA     (wdata),
        .M_AXI_WSTRB     (wstrb),
        .M_AXI_WLAST     (wlast),
        .M_AXI_WVALID    (wvalid),
        .M_AXI_WREADY    (wready),

        .M_AXI_BID       (bid),
        .M_AXI_BRESP     (bresp),
        .M_AXI_BVALID    (bvalid),
        .M_AXI_BREADY    (bready),

        .M_AXI_ARID      (arid),
        .M_AXI_ARADDR    (araddr),
        .M_AXI_ARLEN     (arlen),
        .M_AXI_ARSIZE    (arsize),
        .M_AXI_ARBURST   (arburst),
        .M_AXI_ARLOCK    (arlock),
        .M_AXI_ARCACHE   (arcache),
        .M_AXI_ARPROT    (arprot),
        .M_AXI_ARQOS     (arqos),
        .M_AXI_ARVALID   (arvalid),
        .M_AXI_ARREADY   (arready),

        .M_AXI_RID       (rid),
        .M_AXI_RDATA     (rdata),
        .M_AXI_RRESP     (rresp),
        .M_AXI_RLAST     (rlast),
        .M_AXI_RVALID    (rvalid),
        .M_AXI_RREADY    (rready)
    );

    axi4_slave #(
        .ID_WIDTH      (ID_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_ADDR_BITS (MEM_ADDR_BITS)
    ) u_slave (
        .S_AXI_ACLK      (ACLK),
        .S_AXI_ARESETN   (ARESETn),

        .S_AXI_AWID      (awid),
        .S_AXI_AWADDR    (awaddr),
        .S_AXI_AWLEN     (awlen),
        .S_AXI_AWSIZE    (awsize),
        .S_AXI_AWBURST   (awburst),
        .S_AXI_AWLOCK    (awlock),
        .S_AXI_AWCACHE   (awcache),
        .S_AXI_AWPROT    (awprot),
        .S_AXI_AWQOS     (awqos),
        .S_AXI_AWVALID   (awvalid),
        .S_AXI_AWREADY   (awready),

        .S_AXI_WDATA     (wdata),
        .S_AXI_WSTRB     (wstrb),
        .S_AXI_WLAST     (wlast),
        .S_AXI_WVALID    (wvalid),
        .S_AXI_WREADY    (wready),

        .S_AXI_BID       (bid),
        .S_AXI_BRESP     (bresp),
        .S_AXI_BVALID    (bvalid),
        .S_AXI_BREADY    (bready),

        .S_AXI_ARID      (arid),
        .S_AXI_ARADDR    (araddr),
        .S_AXI_ARLEN     (arlen),
        .S_AXI_ARSIZE    (arsize),
        .S_AXI_ARBURST   (arburst),
        .S_AXI_ARLOCK    (arlock),
        .S_AXI_ARCACHE   (arcache),
        .S_AXI_ARPROT    (arprot),
        .S_AXI_ARQOS     (arqos),
        .S_AXI_ARVALID   (arvalid),
        .S_AXI_ARREADY   (arready),

        .S_AXI_RID       (rid),
        .S_AXI_RDATA     (rdata),
        .S_AXI_RRESP     (rresp),
        .S_AXI_RLAST     (rlast),
        .S_AXI_RVALID    (rvalid),
        .S_AXI_RREADY    (rready)
    );

endmodule

`default_nettype wire
