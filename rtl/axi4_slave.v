//=============================================================================
// axi4_slave.v
//
// Full AMBA AXI4 Subordinate -- burst-capable memory-mapped SRAM.
//
// Reference : ARM IHI 0022, Chapter A3 (channels / handshakes), A3.4 (bursts),
//             A3.4.1 (burst address rules), A10 (response signalling).
// Language  : Verilog-2001, pure synthesisable.
//
// What this supports, i.e. what makes it AXI4 and not AXI4-Lite
//   * Bursts of 1..256 beats (AWLEN/ARLEN = beats-1).
//   * All three burst types: FIXED (2'b00), INCR (2'b01), WRAP (2'b10),
//     with the full A3.4.1 address arithmetic including wrap boundaries.
//   * Narrow transfers via AWSIZE/ARSIZE (bytes per beat = 2^AxSIZE).
//   * Transaction identifiers: BID echoes AWID, RID echoes ARID.
//   * WLAST on the write data channel, RLAST generated on read data.
//   * AxCACHE / AxPROT / AxQOS / AxLOCK are accepted (this subordinate has no
//     cache and no exclusive-access monitor, so they carry no behaviour).
//
// Simplifications, all legal for an AXI4 subordinate
//   * One write burst and one read burst in flight at a time.  Read and write
//     do proceed concurrently, since they are independent channel groups.
//   * Because only one burst is outstanding per direction, responses are
//     necessarily returned in order and no ID reordering buffer is needed.
//   * WREADY is asserted only after the matching AW has been captured, i.e.
//     write data that arrives before its address is held on the bus.  A
//     manager is not allowed to require the opposite, so this cannot deadlock.
//   * EXOKAY is never returned (no exclusive access support), as permitted.
//
// Error responses
//   DECERR (2'b11)  address outside the decoded 2^MEM_ADDR_BITS byte region.
//   SLVERR (2'b10)  unsupported request: reserved burst type 2'b11, AxSIZE
//                   wider than the data bus, an illegal WRAP length, or a
//                   WLAST that does not line up with AWLEN.
//   For a read, the chosen response is repeated on every beat of the burst and
//   RLAST is still asserted on the final beat, so the manager never hangs.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_slave #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_ADDR_BITS = 12          // decoded region = 2^12 = 4 KiB
) (
    // ---- Global ------------------------------------------------------------
    input  wire                      S_AXI_ACLK,
    input  wire                      S_AXI_ARESETN,

    // ---- Write Address channel (AW) ---------------------------------------
    input  wire [ID_WIDTH-1:0]       S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  wire [7:0]                S_AXI_AWLEN,
    input  wire [2:0]                S_AXI_AWSIZE,
    input  wire [1:0]                S_AXI_AWBURST,
    input  wire                      S_AXI_AWLOCK,
    input  wire [3:0]                S_AXI_AWCACHE,
    input  wire [2:0]                S_AXI_AWPROT,
    input  wire [3:0]                S_AXI_AWQOS,
    input  wire                      S_AXI_AWVALID,
    output reg                       S_AXI_AWREADY,

    // ---- Write Data channel (W) -------------------------------------------
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WLAST,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    // ---- Write Response channel (B) ---------------------------------------
    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output reg  [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // ---- Read Address channel (AR) ----------------------------------------
    input  wire [ID_WIDTH-1:0]       S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  wire [7:0]                S_AXI_ARLEN,
    input  wire [2:0]                S_AXI_ARSIZE,
    input  wire [1:0]                S_AXI_ARBURST,
    input  wire                      S_AXI_ARLOCK,
    input  wire [3:0]                S_AXI_ARCACHE,
    input  wire [2:0]                S_AXI_ARPROT,
    input  wire [3:0]                S_AXI_ARQOS,
    input  wire                      S_AXI_ARVALID,
    output reg                       S_AXI_ARREADY,

    // ---- Read Data channel (R) --------------------------------------------
    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output reg  [1:0]                S_AXI_RRESP,
    output reg                       S_AXI_RLAST,
    output reg                       S_AXI_RVALID,
    input  wire                      S_AXI_RREADY
);

    //-------------------------------------------------------------------------
    // ceil(log2(x)) as a Verilog-2001 constant function
    //-------------------------------------------------------------------------
    function integer clogb2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clogb2 = 0; v > 0; clogb2 = clogb2 + 1) v = v >> 1;
        end
    endfunction

    localparam STRB_WIDTH = DATA_WIDTH/8;
    localparam ADDR_LSB   = clogb2(STRB_WIDTH);               // 2 for 32-bit
    localparam MEM_IDX_W  = MEM_ADDR_BITS - ADDR_LSB;
    localparam MEM_WORDS  = (32'd1 << MEM_IDX_W);

    // Response encodings (IHI 0022 Table A10-1 / A10-2)
    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_EXOKAY = 2'b01;   // unused: no exclusive access
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;

    // Burst types (IHI 0022 Table A3-3)
    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    // A handy ADDR_WIDTH-wide constant 1
    localparam [ADDR_WIDTH-1:0] ONE_A = {{(ADDR_WIDTH-1){1'b0}}, 1'b1};

    //-------------------------------------------------------------------------
    // Storage
    //-------------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    integer mi;
    initial begin
        for (mi = 0; mi < MEM_WORDS; mi = mi + 1) mem[mi] = {DATA_WIDTH{1'b0}};
    end

    //=========================================================================
    // Request qualification, shared shape for AW and AR
    //
    // A WRAP burst must have 2, 4, 8 or 16 beats (IHI 0022 A3.4.1), AxSIZE may
    // not exceed the data bus width, and 2'b11 is reserved.
    //=========================================================================
    wire aw_in_range = (S_AXI_AWADDR[ADDR_WIDTH-1:MEM_ADDR_BITS] ==
                        {(ADDR_WIDTH-MEM_ADDR_BITS){1'b0}});
    wire ar_in_range = (S_AXI_ARADDR[ADDR_WIDTH-1:MEM_ADDR_BITS] ==
                        {(ADDR_WIDTH-MEM_ADDR_BITS){1'b0}});

    wire aw_len_wrap_ok = (S_AXI_AWLEN == 8'd1)  || (S_AXI_AWLEN == 8'd3) ||
                          (S_AXI_AWLEN == 8'd7)  || (S_AXI_AWLEN == 8'd15);
    wire ar_len_wrap_ok = (S_AXI_ARLEN == 8'd1)  || (S_AXI_ARLEN == 8'd3) ||
                          (S_AXI_ARLEN == 8'd7)  || (S_AXI_ARLEN == 8'd15);

    wire aw_supported = (S_AXI_AWBURST != 2'b11) &&
                        (S_AXI_AWSIZE <= ADDR_LSB[2:0]) &&
                        ((S_AXI_AWBURST != BURST_WRAP) || aw_len_wrap_ok);
    wire ar_supported = (S_AXI_ARBURST != 2'b11) &&
                        (S_AXI_ARSIZE <= ADDR_LSB[2:0]) &&
                        ((S_AXI_ARBURST != BURST_WRAP) || ar_len_wrap_ok);

    wire [1:0] aw_resp = !aw_in_range  ? RESP_DECERR :
                         !aw_supported ? RESP_SLVERR : RESP_OKAY;
    wire [1:0] ar_resp = !ar_in_range  ? RESP_DECERR :
                         !ar_supported ? RESP_SLVERR : RESP_OKAY;

    //=========================================================================
    // Burst address arithmetic (IHI 0022 A3.4.1)
    //
    //   bytes per beat   = 2^AxSIZE
    //   first beat       = AxADDR exactly (may be unaligned)
    //   later beats      = align(previous) + bytes_per_beat
    //   WRAP             = as INCR, but folded back to the wrap boundary once
    //                      the top of the 2^N byte window is reached
    //   FIXED            = address never moves
    //=========================================================================

    // ---- combinational helpers for the incoming AW request -----------------
    wire [ADDR_WIDTH-1:0] aw_nbytes  = ONE_A << S_AXI_AWSIZE;
    wire [2:0]            aw_wshift  = (S_AXI_AWLEN == 8'd1)  ? 3'd1 :
                                       (S_AXI_AWLEN == 8'd3)  ? 3'd2 :
                                       (S_AXI_AWLEN == 8'd7)  ? 3'd3 : 3'd4;
    wire [ADDR_WIDTH-1:0] aw_total   = aw_nbytes << aw_wshift;
    wire [ADDR_WIDTH-1:0] aw_wrap_lo = S_AXI_AWADDR & ~(aw_total - ONE_A);
    wire [ADDR_WIDTH-1:0] aw_wrap_hi = aw_wrap_lo + aw_total;

    // ---- combinational helpers for the incoming AR request -----------------
    wire [ADDR_WIDTH-1:0] ar_nbytes  = ONE_A << S_AXI_ARSIZE;
    wire [2:0]            ar_wshift  = (S_AXI_ARLEN == 8'd1)  ? 3'd1 :
                                       (S_AXI_ARLEN == 8'd3)  ? 3'd2 :
                                       (S_AXI_ARLEN == 8'd7)  ? 3'd3 : 3'd4;
    wire [ADDR_WIDTH-1:0] ar_total   = ar_nbytes << ar_wshift;
    wire [ADDR_WIDTH-1:0] ar_wrap_lo = S_AXI_ARADDR & ~(ar_total - ONE_A);
    wire [ADDR_WIDTH-1:0] ar_wrap_hi = ar_wrap_lo + ar_total;

    // Address of the SECOND beat of the incoming read burst, needed because
    // the first beat is launched straight off the AR handshake.
    wire [ADDR_WIDTH-1:0] ar_incr0   = (S_AXI_ARADDR & ~(ar_nbytes - ONE_A))
                                       + ar_nbytes;
    wire [ADDR_WIDTH-1:0] ar_next0   =
            (S_AXI_ARBURST == BURST_FIXED) ? S_AXI_ARADDR :
            (S_AXI_ARBURST == BURST_WRAP ) ? ((ar_incr0 == ar_wrap_hi)
                                              ? ar_wrap_lo : ar_incr0) :
                                             ar_incr0;

    //=========================================================================
    // Write channel group
    //=========================================================================
    localparam [1:0] WST_IDLE = 2'd0,
                     WST_DATA = 2'd1,
                     WST_RESP = 2'd2;

    reg [1:0]            wstate;
    reg [ID_WIDTH-1:0]   awid_q;
    reg [ADDR_WIDTH-1:0] waddr_q;        // address of the beat being written
    reg [2:0]            awsize_q;
    reg [1:0]            awburst_q;
    reg [7:0]            wbeats_left;    // beats still to come AFTER this one
    reg [ADDR_WIDTH-1:0] wwrap_lo, wwrap_hi;
    reg [1:0]            wresp_q;

    wire [ADDR_WIDTH-1:0] w_nbytes = ONE_A << awsize_q;
    wire [ADDR_WIDTH-1:0] w_incr   = (waddr_q & ~(w_nbytes - ONE_A)) + w_nbytes;
    wire [ADDR_WIDTH-1:0] w_next   =
            (awburst_q == BURST_FIXED) ? waddr_q :
            (awburst_q == BURST_WRAP ) ? ((w_incr == wwrap_hi) ? wwrap_lo
                                                               : w_incr) :
                                         w_incr;

    wire [MEM_IDX_W-1:0] w_index = waddr_q[MEM_ADDR_BITS-1:ADDR_LSB];
    wire                 w_hs    = S_AXI_WVALID & S_AXI_WREADY;

    integer wb;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            wstate        <= WST_IDLE;
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BID     <= {ID_WIDTH{1'b0}};
            S_AXI_BRESP   <= RESP_OKAY;
            awid_q        <= {ID_WIDTH{1'b0}};
            waddr_q       <= {ADDR_WIDTH{1'b0}};
            awsize_q      <= 3'd0;
            awburst_q     <= BURST_INCR;
            wbeats_left   <= 8'd0;
            wwrap_lo      <= {ADDR_WIDTH{1'b0}};
            wwrap_hi      <= {ADDR_WIDTH{1'b0}};
            wresp_q       <= RESP_OKAY;
        end else begin
            case (wstate)

                //-------------------------------------------------------------
                // Wait for a write address, then open the data phase.
                //-------------------------------------------------------------
                WST_IDLE: begin
                    S_AXI_AWREADY <= 1'b1;

                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        S_AXI_AWREADY <= 1'b0;
                        awid_q        <= S_AXI_AWID;
                        waddr_q       <= S_AXI_AWADDR;
                        awsize_q      <= S_AXI_AWSIZE;
                        awburst_q     <= S_AXI_AWBURST;
                        wbeats_left   <= S_AXI_AWLEN;
                        wwrap_lo      <= aw_wrap_lo;
                        wwrap_hi      <= aw_wrap_hi;
                        wresp_q       <= aw_resp;
                        S_AXI_WREADY  <= 1'b1;
                        wstate        <= WST_DATA;
                    end
                end

                //-------------------------------------------------------------
                // Consume exactly AWLEN+1 beats.  An erroring burst is still
                // drained in full; only the memory update is suppressed.
                //-------------------------------------------------------------
                WST_DATA: begin
                    if (w_hs) begin
                        if (wresp_q == RESP_OKAY) begin
                            for (wb = 0; wb < STRB_WIDTH; wb = wb + 1) begin
                                if (S_AXI_WSTRB[wb])
                                    mem[w_index][wb*8 +: 8] <= S_AXI_WDATA[wb*8 +: 8];
                            end
                        end

                        waddr_q <= w_next;

                        if (S_AXI_WLAST || (wbeats_left == 8'd0)) begin
                            // Burst ends here.  Flag a manager that got the
                            // beat count wrong, otherwise report the decode.
                            S_AXI_WREADY <= 1'b0;
                            S_AXI_BID    <= awid_q;
                            S_AXI_BRESP  <= (S_AXI_WLAST && (wbeats_left == 8'd0))
                                            ? wresp_q : RESP_SLVERR;
                            S_AXI_BVALID <= 1'b1;
                            wstate       <= WST_RESP;
                        end else begin
                            wbeats_left <= wbeats_left - 8'd1;
                        end
                    end
                end

                //-------------------------------------------------------------
                // One response per burst, held until the manager takes it.
                //-------------------------------------------------------------
                WST_RESP: begin
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wstate       <= WST_IDLE;
                    end
                end

                default: wstate <= WST_IDLE;
            endcase
        end
    end

    //=========================================================================
    // Read channel group
    //
    // The first beat is fetched on the AR handshake itself, and every later
    // beat is fetched on the R handshake that retires the previous one, so the
    // burst streams at one beat per clock with no bubbles.
    //=========================================================================
    localparam RST_IDLE = 1'b0,
               RST_DATA = 1'b1;

    reg                  rstate;
    reg [ADDR_WIDTH-1:0] raddr_q;        // address of the NEXT beat to fetch
    reg [2:0]            arsize_q;
    reg [1:0]            arburst_q;
    reg [7:0]            rbeats_left;    // beats still to send after the
                                         // one currently on the R channel
    reg [ADDR_WIDTH-1:0] rwrap_lo, rwrap_hi;
    reg [1:0]            rresp_q;

    wire [ADDR_WIDTH-1:0] r_nbytes = ONE_A << arsize_q;
    wire [ADDR_WIDTH-1:0] r_incr   = (raddr_q & ~(r_nbytes - ONE_A)) + r_nbytes;
    wire [ADDR_WIDTH-1:0] r_next   =
            (arburst_q == BURST_FIXED) ? raddr_q :
            (arburst_q == BURST_WRAP ) ? ((r_incr == rwrap_hi) ? rwrap_lo
                                                               : r_incr) :
                                         r_incr;

    wire [MEM_IDX_W-1:0] r_index  = raddr_q[MEM_ADDR_BITS-1:ADDR_LSB];
    wire [MEM_IDX_W-1:0] ar_index = S_AXI_ARADDR[MEM_ADDR_BITS-1:ADDR_LSB];

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            rstate        <= RST_IDLE;
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RLAST   <= 1'b0;
            S_AXI_RID     <= {ID_WIDTH{1'b0}};
            S_AXI_RDATA   <= {DATA_WIDTH{1'b0}};
            S_AXI_RRESP   <= RESP_OKAY;
            raddr_q       <= {ADDR_WIDTH{1'b0}};
            arsize_q      <= 3'd0;
            arburst_q     <= BURST_INCR;
            rbeats_left   <= 8'd0;
            rwrap_lo      <= {ADDR_WIDTH{1'b0}};
            rwrap_hi      <= {ADDR_WIDTH{1'b0}};
            rresp_q       <= RESP_OKAY;
        end else begin
            case (rstate)

                //-------------------------------------------------------------
                RST_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;

                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        S_AXI_ARREADY <= 1'b0;

                        S_AXI_RID   <= S_AXI_ARID;
                        S_AXI_RRESP <= ar_resp;
                        S_AXI_RDATA <= (ar_resp == RESP_OKAY)
                                       ? mem[ar_index] : {DATA_WIDTH{1'b0}};
                        S_AXI_RLAST <= (S_AXI_ARLEN == 8'd0);
                        S_AXI_RVALID<= 1'b1;

                        raddr_q     <= ar_next0;
                        arsize_q    <= S_AXI_ARSIZE;
                        arburst_q   <= S_AXI_ARBURST;
                        rwrap_lo    <= ar_wrap_lo;
                        rwrap_hi    <= ar_wrap_hi;
                        rresp_q     <= ar_resp;
                        rbeats_left <= S_AXI_ARLEN;

                        rstate      <= RST_DATA;
                    end
                end

                //-------------------------------------------------------------
                RST_DATA: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        if (rbeats_left == 8'd0) begin
                            // RLAST has just been accepted: burst complete.
                            S_AXI_RVALID <= 1'b0;
                            S_AXI_RLAST  <= 1'b0;
                            rstate       <= RST_IDLE;
                        end else begin
                            S_AXI_RDATA  <= (rresp_q == RESP_OKAY)
                                            ? mem[r_index] : {DATA_WIDTH{1'b0}};
                            S_AXI_RLAST  <= (rbeats_left == 8'd1);
                            raddr_q      <= r_next;
                            rbeats_left  <= rbeats_left - 8'd1;
                        end
                    end
                end

                default: rstate <= RST_IDLE;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // Attributes this subordinate accepts but does not act on.  Referenced so
    // lint tools do not report them as dangling inputs.
    //-------------------------------------------------------------------------
    wire _unused_attr = S_AXI_AWLOCK | S_AXI_ARLOCK |
                        (|S_AXI_AWCACHE) | (|S_AXI_ARCACHE) |
                        (|S_AXI_AWPROT)  | (|S_AXI_ARPROT)  |
                        (|S_AXI_AWQOS)   | (|S_AXI_ARQOS);

endmodule

`default_nettype wire
