//=============================================================================
// axi4_master.v
//
// AMBA AXI4 manager.  Protocol only, no extras.
//
// Host side (the minimum needed to start a transfer and move its data):
//   cmd_start_write / cmd_start_read   begin a burst (taken only when idle;
//                                      if both are high, the write is taken)
//   cmd_id cmd_addr cmd_len cmd_size cmd_burst
//                                      the burst description, copied into
//                                      registers when the burst starts
//   hw_*   write data in, a plain valid/ready stream
//   hr_*   read data out, a plain valid/ready stream
//   cmd_done   one-cycle pulse when the burst has finished
//   cmd_resp   BRESP for a write, RRESP of the last beat for a read
//
// The manager generates WLAST from its own beat counter and ends a read
// burst on RLAST.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_master #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                      M_AXI_ACLK,
    input  wire                      M_AXI_ARESETN,

    // ---- Host: command ------------------------------------------------------
    input  wire                      cmd_start_write,
    input  wire                      cmd_start_read,
    input  wire [ID_WIDTH-1:0]       cmd_id,
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [7:0]                cmd_len,
    input  wire [2:0]                cmd_size,
    input  wire [1:0]                cmd_burst,
    output reg                       cmd_done,
    output reg  [1:0]                cmd_resp,

    // ---- Host: write data in ------------------------------------------------
    input  wire [DATA_WIDTH-1:0]     hw_data,
    input  wire [(DATA_WIDTH/8)-1:0] hw_strb,
    input  wire                      hw_valid,
    output wire                      hw_ready,

    // ---- Host: read data out ------------------------------------------------
    output wire [DATA_WIDTH-1:0]     hr_data,
    output wire                      hr_valid,
    input  wire                      hr_ready,

    // ---- AXI4 write address -------------------------------------------------
    output reg  [ID_WIDTH-1:0]       M_AXI_AWID,
    output reg  [ADDR_WIDTH-1:0]     M_AXI_AWADDR,
    output reg  [7:0]                M_AXI_AWLEN,
    output reg  [2:0]                M_AXI_AWSIZE,
    output reg  [1:0]                M_AXI_AWBURST,
    output wire                      M_AXI_AWLOCK,
    output wire [3:0]                M_AXI_AWCACHE,
    output wire [2:0]                M_AXI_AWPROT,
    output wire [3:0]                M_AXI_AWQOS,
    output reg                       M_AXI_AWVALID,
    input  wire                      M_AXI_AWREADY,

    // ---- AXI4 write data ----------------------------------------------------
    output wire [DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [(DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire                      M_AXI_WLAST,
    output wire                      M_AXI_WVALID,
    input  wire                      M_AXI_WREADY,

    // ---- AXI4 write response ------------------------------------------------
    input  wire [ID_WIDTH-1:0]       M_AXI_BID,
    input  wire [1:0]                M_AXI_BRESP,
    input  wire                      M_AXI_BVALID,
    output reg                       M_AXI_BREADY,

    // ---- AXI4 read address --------------------------------------------------
    output reg  [ID_WIDTH-1:0]       M_AXI_ARID,
    output reg  [ADDR_WIDTH-1:0]     M_AXI_ARADDR,
    output reg  [7:0]                M_AXI_ARLEN,
    output reg  [2:0]                M_AXI_ARSIZE,
    output reg  [1:0]                M_AXI_ARBURST,
    output wire                      M_AXI_ARLOCK,
    output wire [3:0]                M_AXI_ARCACHE,
    output wire [2:0]                M_AXI_ARPROT,
    output wire [3:0]                M_AXI_ARQOS,
    output reg                       M_AXI_ARVALID,
    input  wire                      M_AXI_ARREADY,

    // ---- AXI4 read data -----------------------------------------------------
    input  wire [ID_WIDTH-1:0]       M_AXI_RID,
    input  wire [DATA_WIDTH-1:0]     M_AXI_RDATA,
    input  wire [1:0]                M_AXI_RRESP,
    input  wire                      M_AXI_RLAST,
    input  wire                      M_AXI_RVALID,
    output wire                      M_AXI_RREADY
);

    // Attribute signals are part of AXI4 but unused here: tied to zero.
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_AWCACHE = 4'b0000;
    assign M_AXI_AWPROT  = 3'b000;
    assign M_AXI_AWQOS   = 4'b0000;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_ARCACHE = 4'b0000;
    assign M_AXI_ARPROT  = 3'b000;
    assign M_AXI_ARQOS   = 4'b0000;

    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_WRITE = 3'd1,   // AW and W
                     ST_B     = 3'd2,   // waiting for the write response
                     ST_RADDR = 3'd3,   // AR
                     ST_RDATA = 3'd4;   // R beats

    reg [2:0] state;
    reg       aw_done;                  // AW handshake already retired
    reg       w_done;                   // WLAST already accepted
    reg [7:0] wbeat;                    // index of the beat on the W channel
    reg [7:0] len_q;                    // AxLEN of the burst in flight

    // Write data: host stream to the W channel while in the WRITE state.
    wire w_open = (state == ST_WRITE) && !w_done;

    assign M_AXI_WDATA  = hw_data;
    assign M_AXI_WSTRB  = hw_strb;
    assign M_AXI_WVALID = hw_valid & w_open;
    assign M_AXI_WLAST  = (wbeat == len_q);
    assign hw_ready     = M_AXI_WREADY & w_open;

    // Read data: R channel to the host stream while in the RDATA state.
    wire r_open = (state == ST_RDATA);

    assign hr_data      = M_AXI_RDATA;
    assign hr_valid     = M_AXI_RVALID & r_open;
    assign M_AXI_RREADY = hr_ready & r_open;

    wire aw_hs = M_AXI_AWVALID & M_AXI_AWREADY;
    wire w_hs  = M_AXI_WVALID  & M_AXI_WREADY;
    wire aw_ok = aw_done || aw_hs;
    wire w_ok  = w_done  || (w_hs && M_AXI_WLAST);

    always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN) begin
        if (!M_AXI_ARESETN) begin
            state         <= ST_IDLE;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            wbeat         <= 8'd0;
            len_q         <= 8'd0;

            M_AXI_AWID    <= {ID_WIDTH{1'b0}};
            M_AXI_AWADDR  <= {ADDR_WIDTH{1'b0}};
            M_AXI_AWLEN   <= 8'd0;
            M_AXI_AWSIZE  <= 3'd0;
            M_AXI_AWBURST <= 2'b01;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_BREADY  <= 1'b0;

            M_AXI_ARID    <= {ID_WIDTH{1'b0}};
            M_AXI_ARADDR  <= {ADDR_WIDTH{1'b0}};
            M_AXI_ARLEN   <= 8'd0;
            M_AXI_ARSIZE  <= 3'd0;
            M_AXI_ARBURST <= 2'b01;
            M_AXI_ARVALID <= 1'b0;

            cmd_done      <= 1'b0;
            cmd_resp      <= 2'b00;
        end else begin
            cmd_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (cmd_start_write) begin
                        M_AXI_AWID    <= cmd_id;
                        M_AXI_AWADDR  <= cmd_addr;
                        M_AXI_AWLEN   <= cmd_len;
                        M_AXI_AWSIZE  <= cmd_size;
                        M_AXI_AWBURST <= cmd_burst;
                        M_AXI_AWVALID <= 1'b1;
                        len_q         <= cmd_len;
                        wbeat         <= 8'd0;
                        aw_done       <= 1'b0;
                        w_done        <= 1'b0;
                        state         <= ST_WRITE;
                    end else if (cmd_start_read) begin
                        M_AXI_ARID    <= cmd_id;
                        M_AXI_ARADDR  <= cmd_addr;
                        M_AXI_ARLEN   <= cmd_len;
                        M_AXI_ARSIZE  <= cmd_size;
                        M_AXI_ARBURST <= cmd_burst;
                        M_AXI_ARVALID <= 1'b1;
                        state         <= ST_RADDR;
                    end
                end

                // AW and W are independent channels; either may finish first.
                ST_WRITE: begin
                    if (aw_hs) M_AXI_AWVALID <= 1'b0;
                    if (w_hs && !M_AXI_WLAST) wbeat <= wbeat + 8'd1;

                    if (aw_ok && w_ok) begin
                        aw_done      <= 1'b0;
                        w_done       <= 1'b0;
                        M_AXI_BREADY <= 1'b1;
                        state        <= ST_B;
                    end else begin
                        aw_done <= aw_ok;
                        w_done  <= w_ok;
                    end
                end

                ST_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        cmd_resp     <= M_AXI_BRESP;
                        M_AXI_BREADY <= 1'b0;
                        cmd_done     <= 1'b1;
                        state        <= ST_IDLE;
                    end
                end

                ST_RADDR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        state         <= ST_RDATA;
                    end
                end

                // Stream beats to the host; the burst ends on RLAST.
                ST_RDATA: begin
                    if (M_AXI_RVALID && M_AXI_RREADY && M_AXI_RLAST) begin
                        cmd_resp <= M_AXI_RRESP;
                        cmd_done <= 1'b1;
                        state    <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
