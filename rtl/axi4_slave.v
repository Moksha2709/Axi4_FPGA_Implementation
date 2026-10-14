//=============================================================================
// axi4_slave.v
//
// AMBA AXI4 subordinate: a burst-capable memory.  Protocol only, no extras.
//
//   * Bursts of 1..256 beats (AxLEN = beats - 1)
//   * FIXED, INCR and WRAP burst address arithmetic
//   * Narrow beats through AxSIZE, byte merging through WSTRB
//   * BID echoes AWID, RID echoes ARID
//   * Every response is OKAY.  No address or request checking.
//
// One write burst and one read burst may be in flight at the same time, but
// only one of each.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_slave #(
    parameter ID_WIDTH      = 4,
    parameter ADDR_WIDTH    = 32,
    parameter DATA_WIDTH    = 32,
    parameter MEM_ADDR_BITS = 12          // 2^12 = 4 KiB of memory
) (
    input  wire                      S_AXI_ACLK,
    input  wire                      S_AXI_ARESETN,

    // ---- Write address ------------------------------------------------------
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

    // ---- Write data ---------------------------------------------------------
    input  wire [DATA_WIDTH-1:0]     S_AXI_WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] S_AXI_WSTRB,
    input  wire                      S_AXI_WLAST,
    input  wire                      S_AXI_WVALID,
    output reg                       S_AXI_WREADY,

    // ---- Write response -----------------------------------------------------
    output reg  [ID_WIDTH-1:0]       S_AXI_BID,
    output wire [1:0]                S_AXI_BRESP,
    output reg                       S_AXI_BVALID,
    input  wire                      S_AXI_BREADY,

    // ---- Read address -------------------------------------------------------
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

    // ---- Read data ----------------------------------------------------------
    output reg  [ID_WIDTH-1:0]       S_AXI_RID,
    output reg  [DATA_WIDTH-1:0]     S_AXI_RDATA,
    output wire [1:0]                S_AXI_RRESP,
    output reg                       S_AXI_RLAST,
    output reg                       S_AXI_RVALID,
    input  wire                      S_AXI_RREADY
);

    function integer clogb2;
        input integer value;
        integer v;
        begin
            v = value - 1;
            for (clogb2 = 0; v > 0; clogb2 = clogb2 + 1) v = v >> 1;
        end
    endfunction

    localparam STRB_WIDTH = DATA_WIDTH/8;
    localparam ADDR_LSB   = clogb2(STRB_WIDTH);
    localparam MEM_IDX_W  = MEM_ADDR_BITS - ADDR_LSB;
    localparam MEM_WORDS  = (32'd1 << MEM_IDX_W);

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_WRAP  = 2'b10;

    localparam [ADDR_WIDTH-1:0] ONE_A = {{(ADDR_WIDTH-1){1'b0}}, 1'b1};

    // Every transfer completes OKAY.
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    reg [DATA_WIDTH-1:0] mem [0:MEM_WORDS-1];

    integer mi;
    initial begin
        for (mi = 0; mi < MEM_WORDS; mi = mi + 1) mem[mi] = {DATA_WIDTH{1'b0}};
    end

    //=========================================================================
    // Burst address arithmetic, computed once per burst from the address
    // channel.  A WRAP burst loops inside a window of (bytes per beat x beats),
    // which is 2, 4, 8 or 16 beats.
    //=========================================================================
    wire [ADDR_WIDTH-1:0] aw_nbytes  = ONE_A << S_AXI_AWSIZE;
    wire [2:0]            aw_wshift  = (S_AXI_AWLEN == 8'd1) ? 3'd1 :
                                       (S_AXI_AWLEN == 8'd3) ? 3'd2 :
                                       (S_AXI_AWLEN == 8'd7) ? 3'd3 : 3'd4;
    wire [ADDR_WIDTH-1:0] aw_total   = aw_nbytes << aw_wshift;
    wire [ADDR_WIDTH-1:0] aw_wrap_lo = S_AXI_AWADDR & ~(aw_total - ONE_A);
    wire [ADDR_WIDTH-1:0] aw_wrap_hi = aw_wrap_lo + aw_total;

    wire [ADDR_WIDTH-1:0] ar_nbytes  = ONE_A << S_AXI_ARSIZE;
    wire [2:0]            ar_wshift  = (S_AXI_ARLEN == 8'd1) ? 3'd1 :
                                       (S_AXI_ARLEN == 8'd3) ? 3'd2 :
                                       (S_AXI_ARLEN == 8'd7) ? 3'd3 : 3'd4;
    wire [ADDR_WIDTH-1:0] ar_total   = ar_nbytes << ar_wshift;
    wire [ADDR_WIDTH-1:0] ar_wrap_lo = S_AXI_ARADDR & ~(ar_total - ONE_A);
    wire [ADDR_WIDTH-1:0] ar_wrap_hi = ar_wrap_lo + ar_total;

    // Address of the second read beat (the first is fetched on the AR handshake)
    wire [ADDR_WIDTH-1:0] ar_incr0   = (S_AXI_ARADDR & ~(ar_nbytes - ONE_A)) + ar_nbytes;
    wire [ADDR_WIDTH-1:0] ar_next0   =
            (S_AXI_ARBURST == BURST_FIXED) ? S_AXI_ARADDR :
            (S_AXI_ARBURST == BURST_WRAP ) ? ((ar_incr0 == ar_wrap_hi) ? ar_wrap_lo : ar_incr0) :
                                             ar_incr0;

    //=========================================================================
    // Write channel group:  AW -> W beats until WLAST -> one B response
    //=========================================================================
    localparam [1:0] WST_IDLE = 2'd0,
                     WST_DATA = 2'd1,
                     WST_RESP = 2'd2;

    reg [1:0]            wstate;
    reg [ID_WIDTH-1:0]   awid_q;
    reg [ADDR_WIDTH-1:0] waddr_q;
    reg [2:0]            awsize_q;
    reg [1:0]            awburst_q;
    reg [ADDR_WIDTH-1:0] wwrap_lo, wwrap_hi;

    wire [ADDR_WIDTH-1:0] w_nbytes = ONE_A << awsize_q;
    wire [ADDR_WIDTH-1:0] w_incr   = (waddr_q & ~(w_nbytes - ONE_A)) + w_nbytes;
    wire [ADDR_WIDTH-1:0] w_next   =
            (awburst_q == BURST_FIXED) ? waddr_q :
            (awburst_q == BURST_WRAP ) ? ((w_incr == wwrap_hi) ? wwrap_lo : w_incr) :
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
            awid_q        <= {ID_WIDTH{1'b0}};
            waddr_q       <= {ADDR_WIDTH{1'b0}};
            awsize_q      <= 3'd0;
            awburst_q     <= 2'b01;
            wwrap_lo      <= {ADDR_WIDTH{1'b0}};
            wwrap_hi      <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (wstate)
                WST_IDLE: begin
                    S_AXI_AWREADY <= 1'b1;
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        S_AXI_AWREADY <= 1'b0;
                        awid_q        <= S_AXI_AWID;
                        waddr_q       <= S_AXI_AWADDR;
                        awsize_q      <= S_AXI_AWSIZE;
                        awburst_q     <= S_AXI_AWBURST;
                        wwrap_lo      <= aw_wrap_lo;
                        wwrap_hi      <= aw_wrap_hi;
                        S_AXI_WREADY  <= 1'b1;
                        wstate        <= WST_DATA;
                    end
                end

                WST_DATA: begin
                    if (w_hs) begin
                        for (wb = 0; wb < STRB_WIDTH; wb = wb + 1) begin
                            if (S_AXI_WSTRB[wb])
                                mem[w_index][wb*8 +: 8] <= S_AXI_WDATA[wb*8 +: 8];
                        end
                        waddr_q <= w_next;

                        if (S_AXI_WLAST) begin
                            S_AXI_WREADY <= 1'b0;
                            S_AXI_BID    <= awid_q;
                            S_AXI_BVALID <= 1'b1;
                            wstate       <= WST_RESP;
                        end
                    end
                end

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
    // Read channel group:  AR -> ARLEN+1 beats, RLAST on the final one
    //=========================================================================
    localparam RST_IDLE = 1'b0,
               RST_DATA = 1'b1;

    reg                  rstate;
    reg [ADDR_WIDTH-1:0] raddr_q;        // address of the NEXT beat to fetch
    reg [2:0]            arsize_q;
    reg [1:0]            arburst_q;
    reg [7:0]            rbeats_left;    // beats still to send after the current one
    reg [ADDR_WIDTH-1:0] rwrap_lo, rwrap_hi;

    wire [ADDR_WIDTH-1:0] r_nbytes = ONE_A << arsize_q;
    wire [ADDR_WIDTH-1:0] r_incr   = (raddr_q & ~(r_nbytes - ONE_A)) + r_nbytes;
    wire [ADDR_WIDTH-1:0] r_next   =
            (arburst_q == BURST_FIXED) ? raddr_q :
            (arburst_q == BURST_WRAP ) ? ((r_incr == rwrap_hi) ? rwrap_lo : r_incr) :
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
            raddr_q       <= {ADDR_WIDTH{1'b0}};
            arsize_q      <= 3'd0;
            arburst_q     <= 2'b01;
            rbeats_left   <= 8'd0;
            rwrap_lo      <= {ADDR_WIDTH{1'b0}};
            rwrap_hi      <= {ADDR_WIDTH{1'b0}};
        end else begin
            case (rstate)
                RST_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        S_AXI_ARREADY <= 1'b0;

                        S_AXI_RID    <= S_AXI_ARID;
                        S_AXI_RDATA  <= mem[ar_index];
                        S_AXI_RLAST  <= (S_AXI_ARLEN == 8'd0);
                        S_AXI_RVALID <= 1'b1;

                        raddr_q      <= ar_next0;
                        arsize_q     <= S_AXI_ARSIZE;
                        arburst_q    <= S_AXI_ARBURST;
                        rwrap_lo     <= ar_wrap_lo;
                        rwrap_hi     <= ar_wrap_hi;
                        rbeats_left  <= S_AXI_ARLEN;
                        rstate       <= RST_DATA;
                    end
                end

                RST_DATA: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        if (rbeats_left == 8'd0) begin
                            S_AXI_RVALID <= 1'b0;
                            S_AXI_RLAST  <= 1'b0;
                            rstate       <= RST_IDLE;
                        end else begin
                            S_AXI_RDATA <= mem[r_index];
                            S_AXI_RLAST <= (rbeats_left == 8'd1);
                            raddr_q     <= r_next;
                            rbeats_left <= rbeats_left - 8'd1;
                        end
                    end
                end

                default: rstate <= RST_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
