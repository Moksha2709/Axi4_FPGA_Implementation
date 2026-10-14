//=============================================================================
// axi4_master.v  --  AXI4 manager that starts the transactions itself
//
// What it sends comes from D flip-flop registers inside the master:
//   addr_reg      the address to use
//   data_reg[0:3] the four words to write
// After reset it runs by itself, with no host interface:
//
//   write the four words (one burst of 4 beats)  ->  wait for the response
//   read the same four words back (one burst)    ->  compare with what it wrote
//
// Outputs:  done = 1 when the whole sequence has finished
//           pass = 1 when what was read back equals what was written
//
// The sequence is one state machine, one step per channel:
//   S_AW -> S_W -> S_B -> S_AR -> S_R -> S_DONE
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_master (
    input  wire        clk,
    input  wire        resetn,             // active low

    // ---- AW : write address -------------------------------------------------
    output wire [3:0]  M_AXI_AWID,
    output wire [31:0] M_AXI_AWADDR,
    output wire [7:0]  M_AXI_AWLEN,
    output reg         M_AXI_AWVALID,
    input  wire        M_AXI_AWREADY,

    // ---- W : write data -----------------------------------------------------
    output wire [31:0] M_AXI_WDATA,
    output wire [3:0]  M_AXI_WSTRB,
    output wire        M_AXI_WLAST,
    output reg         M_AXI_WVALID,
    input  wire        M_AXI_WREADY,

    // ---- B : write response -------------------------------------------------
    input  wire [3:0]  M_AXI_BID,
    input  wire [1:0]  M_AXI_BRESP,
    input  wire        M_AXI_BVALID,
    output reg         M_AXI_BREADY,

    // ---- AR : read address --------------------------------------------------
    output wire [3:0]  M_AXI_ARID,
    output wire [31:0] M_AXI_ARADDR,
    output wire [7:0]  M_AXI_ARLEN,
    output reg         M_AXI_ARVALID,
    input  wire        M_AXI_ARREADY,

    // ---- R : read data ------------------------------------------------------
    input  wire [3:0]  M_AXI_RID,
    input  wire [31:0] M_AXI_RDATA,
    input  wire [1:0]  M_AXI_RRESP,
    input  wire        M_AXI_RLAST,
    input  wire        M_AXI_RVALID,
    output reg         M_AXI_RREADY,

    // ---- result -------------------------------------------------------------
    output reg         done,
    output wire        pass
);

    //-------------------------------------------------------------------------
    // D flip-flop registers: what to write, and where
    //-------------------------------------------------------------------------
    reg [31:0] addr_reg;
    reg [31:0] data_reg0, data_reg1, data_reg2, data_reg3;
    reg [31:0] read_reg0, read_reg1, read_reg2, read_reg3;   // what came back

    reg [1:0]  beat;                       // which of the 4 beats we are on

    // The burst is always 4 beats of 4 bytes, so AxLEN is 3.
    assign M_AXI_AWID    = 4'd1;
    assign M_AXI_AWADDR  = addr_reg;
    assign M_AXI_AWLEN   = 8'd3;
    assign M_AXI_ARID    = 4'd1;
    assign M_AXI_ARADDR  = addr_reg;
    assign M_AXI_ARLEN   = 8'd3;

    // Write data comes out of the data registers, one word per beat.
    assign M_AXI_WDATA = (beat == 2'd0) ? data_reg0 :
                         (beat == 2'd1) ? data_reg1 :
                         (beat == 2'd2) ? data_reg2 : data_reg3;
    assign M_AXI_WSTRB = 4'b1111;
    assign M_AXI_WLAST = (beat == 2'd3);

    assign pass = done &&
                  (read_reg0 == data_reg0) && (read_reg1 == data_reg1) &&
                  (read_reg2 == data_reg2) && (read_reg3 == data_reg3);

    //-------------------------------------------------------------------------
    // The sequence
    //-------------------------------------------------------------------------
    localparam S_START = 3'd0,
               S_AW    = 3'd1,    // send the write address
               S_W     = 3'd2,    // send the four data beats
               S_B     = 3'd3,    // wait for the write response
               S_AR    = 3'd4,    // send the read address
               S_R     = 3'd5,    // take the four data beats
               S_DONE  = 3'd6;

    reg [2:0] state;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= S_START;
            beat          <= 2'd0;
            done          <= 1'b0;

            addr_reg      <= 32'h0000_0010;       // the values we write
            data_reg0     <= 32'hA5A5_0001;
            data_reg1     <= 32'h5A5A_0002;
            data_reg2     <= 32'hDEAD_BEEF;
            data_reg3     <= 32'h0BAD_F00D;
            read_reg0     <= 32'd0;
            read_reg1     <= 32'd0;
            read_reg2     <= 32'd0;
            read_reg3     <= 32'd0;

            M_AXI_AWVALID <= 1'b0;
            M_AXI_WVALID  <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_RREADY  <= 1'b0;
        end else begin
            case (state)
                S_START: begin
                    M_AXI_AWVALID <= 1'b1;
                    state         <= S_AW;
                end

                S_AW: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                        M_AXI_AWVALID <= 1'b0;
                        M_AXI_WVALID  <= 1'b1;
                        beat          <= 2'd0;
                        state         <= S_W;
                    end
                end

                S_W: begin
                    if (M_AXI_WVALID && M_AXI_WREADY) begin
                        if (beat == 2'd3) begin
                            M_AXI_WVALID <= 1'b0;
                            M_AXI_BREADY <= 1'b1;
                            state        <= S_B;
                        end else begin
                            beat <= beat + 2'd1;
                        end
                    end
                end

                S_B: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        M_AXI_BREADY  <= 1'b0;
                        M_AXI_ARVALID <= 1'b1;
                        state         <= S_AR;
                    end
                end

                S_AR: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                        M_AXI_ARVALID <= 1'b0;
                        M_AXI_RREADY  <= 1'b1;
                        beat          <= 2'd0;
                        state         <= S_R;
                    end
                end

                S_R: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        case (beat)
                            2'd0: read_reg0 <= M_AXI_RDATA;
                            2'd1: read_reg1 <= M_AXI_RDATA;
                            2'd2: read_reg2 <= M_AXI_RDATA;
                            2'd3: read_reg3 <= M_AXI_RDATA;
                        endcase
                        if (M_AXI_RLAST) begin
                            M_AXI_RREADY <= 1'b0;
                            done         <= 1'b1;
                            state        <= S_DONE;
                        end else begin
                            beat <= beat + 2'd1;
                        end
                    end
                end

                S_DONE: begin
                    // finished: hold done and pass
                end

                default: state <= S_START;
            endcase
        end
    end

endmodule

`default_nettype wire
