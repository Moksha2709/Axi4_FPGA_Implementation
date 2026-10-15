//=============================================================================
// axi4_master.v  --  AXI4 manager: takes its data from the input flip-flops,
//                    writes it to the slave, reads it back
//
//   input DFFs --> master --AXI4--> slave --> (read data) --> output DFFs
//
// When start goes high the master runs one sequence:
//
//   write the four words (one burst of 4 beats)  ->  wait for the response
//   read the same four words back (one burst)    ->  hand each beat to the
//                                                    output flip-flops
//
// done goes high when the sequence has finished and stays high until start
// goes low again, so the sequence can be run again.
//
// The master itself holds no data.  The address and the four words are
// inputs (they come from axi4_in_dff and must not change while it runs); the
// words that come back leave on rd_valid / rd_idx / rd_data.
//
// The sequence is one state machine, one step per channel:
//   S_IDLE -> S_AW -> S_W -> S_B -> S_AR -> S_R -> S_DONE
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_master (
    input  wire        clk,
    input  wire        resetn,             // active low

    // ---- control ------------------------------------------------------------
    input  wire        start,              // 1 = run the sequence
    output reg         done,

    // ---- from the input flip-flops -----------------------------------------
    input  wire [31:0] addr_in,
    input  wire [31:0] data_in0,
    input  wire [31:0] data_in1,
    input  wire [31:0] data_in2,
    input  wire [31:0] data_in3,

    // ---- to the output flip-flops ------------------------------------------
    output wire        rd_valid,           // a read beat has arrived
    output wire [1:0]  rd_idx,             // which one (0..3)
    output wire [31:0] rd_data,

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
    output reg         M_AXI_RREADY
);

    reg [1:0] beat;                        // which of the 4 beats we are on

    // The burst is always 4 beats of 4 bytes, so AxLEN is 3.
    assign M_AXI_AWID    = 4'd1;
    assign M_AXI_AWADDR  = addr_in;
    assign M_AXI_AWLEN   = 8'd3;
    assign M_AXI_ARID    = 4'd1;
    assign M_AXI_ARADDR  = addr_in;
    assign M_AXI_ARLEN   = 8'd3;

    // Write data comes from the input flip-flops, one word per beat.
    assign M_AXI_WDATA = (beat == 2'd0) ? data_in0 :
                         (beat == 2'd1) ? data_in1 :
                         (beat == 2'd2) ? data_in2 : data_in3;
    assign M_AXI_WSTRB = 4'b1111;
    assign M_AXI_WLAST = (beat == 2'd3);

    // Every accepted read beat goes to the output flip-flops.
    assign rd_valid = M_AXI_RVALID && M_AXI_RREADY;
    assign rd_idx   = beat;
    assign rd_data  = M_AXI_RDATA;

    //-------------------------------------------------------------------------
    // The sequence
    //-------------------------------------------------------------------------
    localparam S_IDLE = 3'd0,
               S_AW   = 3'd1,    // send the write address
               S_W    = 3'd2,    // send the four data beats
               S_B    = 3'd3,    // wait for the write response
               S_AR   = 3'd4,    // send the read address
               S_R    = 3'd5,    // take the four data beats
               S_DONE = 3'd6;

    reg [2:0] state;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= S_IDLE;
            beat          <= 2'd0;
            done          <= 1'b0;
            M_AXI_AWVALID <= 1'b0;
            M_AXI_WVALID  <= 1'b0;
            M_AXI_BREADY  <= 1'b0;
            M_AXI_ARVALID <= 1'b0;
            M_AXI_RREADY  <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (start) begin
                        M_AXI_AWVALID <= 1'b1;
                        state         <= S_AW;
                    end
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
                    // hold done until start is released, then be ready to run again
                    if (!start) begin
                        done  <= 1'b0;
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
