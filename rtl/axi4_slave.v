//=============================================================================
// axi4_slave.v  --  AXI4 subordinate: a 4 KiB memory
//
// Five channels, nothing else.
//   * Bursts of 1 to 256 beats (AxLEN = beats - 1).
//   * Every beat is one 32-bit word.  The address counts up by 4 each beat.
//   * WSTRB picks which bytes of a word are written.
//   * BID repeats AWID and RID repeats ARID.
//   * Every response is OKAY.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_slave (
    input  wire        S_AXI_ACLK,
    input  wire        S_AXI_ARESETN,       // active low

    // ---- AW : write address -------------------------------------------------
    input  wire [3:0]  S_AXI_AWID,
    input  wire [31:0] S_AXI_AWADDR,
    input  wire [7:0]  S_AXI_AWLEN,
    input  wire        S_AXI_AWVALID,
    output reg         S_AXI_AWREADY,

    // ---- W : write data -----------------------------------------------------
    input  wire [31:0] S_AXI_WDATA,
    input  wire [3:0]  S_AXI_WSTRB,
    input  wire        S_AXI_WLAST,
    input  wire        S_AXI_WVALID,
    output reg         S_AXI_WREADY,

    // ---- B : write response -------------------------------------------------
    output reg  [3:0]  S_AXI_BID,
    output wire [1:0]  S_AXI_BRESP,
    output reg         S_AXI_BVALID,
    input  wire        S_AXI_BREADY,

    // ---- AR : read address --------------------------------------------------
    input  wire [3:0]  S_AXI_ARID,
    input  wire [31:0] S_AXI_ARADDR,
    input  wire [7:0]  S_AXI_ARLEN,
    input  wire        S_AXI_ARVALID,
    output reg         S_AXI_ARREADY,

    // ---- R : read data ------------------------------------------------------
    output reg  [3:0]  S_AXI_RID,
    output reg  [31:0] S_AXI_RDATA,
    output wire [1:0]  S_AXI_RRESP,
    output reg         S_AXI_RLAST,
    output reg         S_AXI_RVALID,
    input  wire        S_AXI_RREADY
);

    // Every transfer completes OKAY.
    assign S_AXI_BRESP = 2'b00;
    assign S_AXI_RRESP = 2'b00;

    // 1024 words x 32 bits = 4 KiB.  The word index is address bits [11:2].
    reg [31:0] mem [0:1023];

    integer i;
    initial begin
        for (i = 0; i < 1024; i = i + 1) mem[i] = 32'h0;
    end

    //=========================================================================
    // Write side:  AW  ->  W beats until WLAST  ->  B
    //=========================================================================
    localparam W_IDLE = 2'd0,    // waiting for an address
               W_DATA = 2'd1,    // taking data beats
               W_RESP = 2'd2;    // holding the response until it is taken

    reg [1:0]  wstate;
    reg [3:0]  wid;
    reg [31:0] waddr;

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            wstate        <= W_IDLE;
            S_AXI_AWREADY <= 1'b0;
            S_AXI_WREADY  <= 1'b0;
            S_AXI_BVALID  <= 1'b0;
            S_AXI_BID     <= 4'd0;
            wid           <= 4'd0;
            waddr         <= 32'd0;
        end else begin
            case (wstate)
                W_IDLE: begin
                    S_AXI_AWREADY <= 1'b1;
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        S_AXI_AWREADY <= 1'b0;
                        wid           <= S_AXI_AWID;
                        waddr         <= S_AXI_AWADDR;
                        S_AXI_WREADY  <= 1'b1;
                        wstate        <= W_DATA;
                    end
                end

                W_DATA: begin
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        if (S_AXI_WSTRB[0]) mem[waddr[11:2]][7:0]   <= S_AXI_WDATA[7:0];
                        if (S_AXI_WSTRB[1]) mem[waddr[11:2]][15:8]  <= S_AXI_WDATA[15:8];
                        if (S_AXI_WSTRB[2]) mem[waddr[11:2]][23:16] <= S_AXI_WDATA[23:16];
                        if (S_AXI_WSTRB[3]) mem[waddr[11:2]][31:24] <= S_AXI_WDATA[31:24];
                        waddr <= waddr + 32'd4;

                        if (S_AXI_WLAST) begin
                            S_AXI_WREADY <= 1'b0;
                            S_AXI_BID    <= wid;
                            S_AXI_BVALID <= 1'b1;
                            wstate       <= W_RESP;
                        end
                    end
                end

                W_RESP: begin
                    if (S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        wstate       <= W_IDLE;
                    end
                end

                default: wstate <= W_IDLE;
            endcase
        end
    end

    //=========================================================================
    // Read side:  AR  ->  ARLEN + 1 beats on R, RLAST on the final one
    //=========================================================================
    localparam R_IDLE = 1'b0,
               R_DATA = 1'b1;

    reg        rstate;
    reg [31:0] raddr;      // address of the NEXT beat to fetch
    reg [7:0]  rleft;      // beats still to send after the one on the bus

    always @(posedge S_AXI_ACLK or negedge S_AXI_ARESETN) begin
        if (!S_AXI_ARESETN) begin
            rstate        <= R_IDLE;
            S_AXI_ARREADY <= 1'b0;
            S_AXI_RVALID  <= 1'b0;
            S_AXI_RLAST   <= 1'b0;
            S_AXI_RID     <= 4'd0;
            S_AXI_RDATA   <= 32'd0;
            raddr         <= 32'd0;
            rleft         <= 8'd0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    S_AXI_ARREADY <= 1'b1;
                    if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        S_AXI_ARREADY <= 1'b0;
                        S_AXI_RID     <= S_AXI_ARID;
                        S_AXI_RDATA   <= mem[S_AXI_ARADDR[11:2]];   // first beat
                        S_AXI_RLAST   <= (S_AXI_ARLEN == 8'd0);
                        S_AXI_RVALID  <= 1'b1;
                        raddr         <= S_AXI_ARADDR + 32'd4;
                        rleft         <= S_AXI_ARLEN;
                        rstate        <= R_DATA;
                    end
                end

                R_DATA: begin
                    if (S_AXI_RVALID && S_AXI_RREADY) begin
                        if (rleft == 8'd0) begin                    // that was the last
                            S_AXI_RVALID <= 1'b0;
                            S_AXI_RLAST  <= 1'b0;
                            rstate       <= R_IDLE;
                        end else begin                              // fetch the next
                            S_AXI_RDATA <= mem[raddr[11:2]];
                            S_AXI_RLAST <= (rleft == 8'd1);
                            raddr       <= raddr + 32'd4;
                            rleft       <= rleft - 8'd1;
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
