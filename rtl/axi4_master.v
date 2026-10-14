//=============================================================================
// axi4_master.v
//
// Full AMBA AXI4 Manager -- burst engine with a streaming host interface.
//
// Reference : ARM IHI 0022, Chapter A3 (channels / handshakes, A2.3 stability),
//             A3.4 (bursts), A10 (responses).
// Language  : Verilog-2001, pure synthesisable.
//
// Host interface, in three parts
//
//  1) Command port.  One burst descriptor at a time:
//       cmd_start_write / cmd_start_read   accepted only while cmd_busy == 0
//       cmd_id    transaction identifier, echoed back by the subordinate
//       cmd_addr  byte address of the FIRST beat
//       cmd_len   beats - 1  (so 8'd0 = 1 beat, 8'd255 = 256 beats)
//       cmd_size  log2(bytes per beat)
//       cmd_burst 2'b00 FIXED, 2'b01 INCR, 2'b10 WRAP
//     If both start inputs are high on an idle cycle, the write wins.
//     The whole descriptor is registered on the accepting cycle, so every AXI
//     address-channel output is a flip-flop and is bit-stable for the entire
//     burst no matter how long the subordinate stalls (IHI 0022 A2.3).
//
//  2) Write data port (hw_*).  A plain valid/ready stream the manager drains
//     onto the W channel, one host beat per AXI beat.  WLAST is generated here
//     from the beat counter, so the host never has to track it.  The host must
//     hold hw_data / hw_strb stable while hw_valid is high and hw_ready is low
//     -- the ordinary valid/ready contract -- because those two feed WDATA and
//     WSTRB directly.
//
//  3) Read data port (hr_*).  The R channel presented to the host as a stream,
//     with hr_last marking the final beat and hr_resp carrying that beat's
//     RRESP.  Back-pressure from hr_ready is passed straight to RREADY.
//
// Completion
//   cmd_done is a one-cycle strobe: at the B handshake for a write, at the
//   RLAST handshake for a read.  On that cycle cmd_resp holds the response
//   (for a read, the worst response seen across the burst), cmd_rid/cmd_bid
//   holds the identifier the subordinate echoed, and cmd_last_err flags a
//   subordinate whose RLAST did not line up with the requested cmd_len.
//
// Only one burst is outstanding at a time.  That is fully AXI4 compliant: it
// simply means this manager never needs ID-based reordering logic.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_master #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32,
    // Static attribute values driven on the address channels.
    parameter [3:0] CACHE_VAL = 4'b0011,   // Normal, non-cacheable, bufferable
    parameter [2:0] PROT_VAL  = 3'b000,    // unprivileged, secure, data
    parameter [3:0] QOS_VAL   = 4'b0000    // no QoS preference
) (
    // ---- Global ------------------------------------------------------------
    input  wire                      M_AXI_ACLK,
    input  wire                      M_AXI_ARESETN,

    // ---- Host command port -------------------------------------------------
    input  wire                      cmd_start_write,
    input  wire                      cmd_start_read,
    input  wire [ID_WIDTH-1:0]       cmd_id,
    input  wire [ADDR_WIDTH-1:0]     cmd_addr,
    input  wire [7:0]                cmd_len,
    input  wire [2:0]                cmd_size,
    input  wire [1:0]                cmd_burst,
    output wire                      cmd_busy,
    output reg                       cmd_done,
    output reg  [1:0]                cmd_resp,
    output reg  [ID_WIDTH-1:0]       cmd_resp_id,
    output reg                       cmd_last_err,

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
    input  wire                      hr_ready,

    // ---- Write Address channel (AW) ---------------------------------------
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

    // ---- Write Data channel (W) -------------------------------------------
    output wire [DATA_WIDTH-1:0]     M_AXI_WDATA,
    output wire [(DATA_WIDTH/8)-1:0] M_AXI_WSTRB,
    output wire                      M_AXI_WLAST,
    output wire                      M_AXI_WVALID,
    input  wire                      M_AXI_WREADY,

    // ---- Write Response channel (B) ---------------------------------------
    input  wire [ID_WIDTH-1:0]       M_AXI_BID,
    input  wire [1:0]                M_AXI_BRESP,
    input  wire                      M_AXI_BVALID,
    output reg                       M_AXI_BREADY,

    // ---- Read Address channel (AR) ----------------------------------------
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

    // ---- Read Data channel (R) --------------------------------------------
    input  wire [ID_WIDTH-1:0]       M_AXI_RID,
    input  wire [DATA_WIDTH-1:0]     M_AXI_RDATA,
    input  wire [1:0]                M_AXI_RRESP,
    input  wire                      M_AXI_RLAST,
    input  wire                      M_AXI_RVALID,
    output wire                      M_AXI_RREADY
);

    localparam [1:0] RESP_OKAY = 2'b00;

    // Static attributes.  AXI4 keeps AxLOCK as a single bit and this manager
    // never issues exclusive accesses, so it is tied low.
    assign M_AXI_AWLOCK  = 1'b0;
    assign M_AXI_ARLOCK  = 1'b0;
    assign M_AXI_AWCACHE = CACHE_VAL;
    assign M_AXI_ARCACHE = CACHE_VAL;
    assign M_AXI_AWPROT  = PROT_VAL;
    assign M_AXI_ARPROT  = PROT_VAL;
    assign M_AXI_AWQOS   = QOS_VAL;
    assign M_AXI_ARQOS   = QOS_VAL;

    //-------------------------------------------------------------------------
    localparam [2:0] ST_IDLE  = 3'd0,
                     ST_WRITE = 3'd1,   // AW outstanding and/or W streaming
                     ST_B     = 3'd2,   // waiting for the write response
                     ST_RADDR = 3'd3,   // AR outstanding
                     ST_RDATA = 3'd4;   // R burst streaming to the host

    reg [2:0] state;
    reg       aw_done;                  // AW handshake already retired
    reg       w_done;                   // WLAST already accepted
    reg [7:0] wbeat;                    // index of the beat on the W channel
    reg [7:0] rbeat;                    // index of the beat on the R channel
    reg [7:0] len_q;                    // beats-1 for the burst in flight

    assign cmd_busy = (state != ST_IDLE);

    //-------------------------------------------------------------------------
    // Write data channel: host stream in, W channel out.
    // Gated by state only (a flip-flop), so no AXI input reaches an AXI output
    // combinationally.
    //-------------------------------------------------------------------------
    wire w_phase_open = (state == ST_WRITE) && !w_done;

    assign M_AXI_WDATA  = hw_data;
    assign M_AXI_WSTRB  = hw_strb;
    assign M_AXI_WVALID = hw_valid & w_phase_open;
    assign M_AXI_WLAST  = (wbeat == len_q);
    assign hw_ready     = M_AXI_WREADY & w_phase_open;

    //-------------------------------------------------------------------------
    // Read data channel: R channel in, host stream out.
    //-------------------------------------------------------------------------
    wire r_phase_open = (state == ST_RDATA);

    assign hr_data      = M_AXI_RDATA;
    assign hr_resp      = M_AXI_RRESP;
    assign hr_last      = M_AXI_RLAST;
    assign hr_valid     = M_AXI_RVALID & r_phase_open;
    assign M_AXI_RREADY = hr_ready     & r_phase_open;

    // Handshake detect
    wire aw_hs = M_AXI_AWVALID & M_AXI_AWREADY;
    wire w_hs  = M_AXI_WVALID  & M_AXI_WREADY;
    wire r_hs  = M_AXI_RVALID  & M_AXI_RREADY;

    // "Retired by the end of this cycle" view, so the write phase can finish
    // on the same edge as its final handshake.
    wire aw_ok = aw_done || aw_hs;
    wire w_ok  = w_done  || (w_hs && M_AXI_WLAST);

    //-------------------------------------------------------------------------
    always @(posedge M_AXI_ACLK or negedge M_AXI_ARESETN) begin
        if (!M_AXI_ARESETN) begin
            state         <= ST_IDLE;
            aw_done       <= 1'b0;
            w_done        <= 1'b0;
            wbeat         <= 8'd0;
            rbeat         <= 8'd0;
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
            cmd_resp      <= RESP_OKAY;
            cmd_resp_id   <= {ID_WIDTH{1'b0}};
            cmd_last_err  <= 1'b0;
        end else begin
            cmd_done <= 1'b0;                 // one-cycle strobe by default

            case (state)

                //-------------------------------------------------------------
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
                        cmd_resp      <= RESP_OKAY;
                        cmd_last_err  <= 1'b0;
                        state         <= ST_WRITE;
                    end else if (cmd_start_read) begin
                        M_AXI_ARID    <= cmd_id;
                        M_AXI_ARADDR  <= cmd_addr;
                        M_AXI_ARLEN   <= cmd_len;
                        M_AXI_ARSIZE  <= cmd_size;
                        M_AXI_ARBURST <= cmd_burst;
                        M_AXI_ARVALID <= 1'b1;

                        len_q         <= cmd_len;
                        rbeat         <= 8'd0;
                        cmd_resp      <= RESP_OKAY;
                        cmd_last_err  <= 1'b0;
                        state         <= ST_RADDR;
                    end
                end

                //-------------------------------------------------------------
                // AW and W are independent channels; either may finish first.
                //-------------------------------------------------------------
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

                //-------------------------------------------------------------
                ST_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        cmd_resp     <= M_AXI_BRESP;
                        cmd_resp_id  <= M_AXI_BID;
                        M_AXI_BREADY <= 1'b0;
                        cmd_done     <= 1'b1;
                        state        <= ST_IDLE;
                    end
                end

                //-------------------------------------------------------------
                ST_RADDR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        state         <= ST_RDATA;
                    end
                end

                //-------------------------------------------------------------
                // Stream the burst to the host, keeping the worst response.
                //-------------------------------------------------------------
                ST_RDATA: begin
                    if (r_hs) begin
                        if (M_AXI_RRESP != RESP_OKAY) cmd_resp <= M_AXI_RRESP;

                        if (M_AXI_RLAST) begin
                            cmd_resp_id  <= M_AXI_RID;
                            // RLAST should arrive on beat index len_q exactly.
                            cmd_last_err <= (rbeat != len_q);
                            cmd_done     <= 1'b1;
                            state        <= ST_IDLE;
                        end else if (rbeat == len_q) begin
                            // More beats than requested: stop and report it.
                            cmd_resp_id  <= M_AXI_RID;
                            cmd_last_err <= 1'b1;
                            cmd_done     <= 1'b1;
                            state        <= ST_IDLE;
                        end else begin
                            rbeat <= rbeat + 8'd1;
                        end
                    end
                end

                //-------------------------------------------------------------
                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
