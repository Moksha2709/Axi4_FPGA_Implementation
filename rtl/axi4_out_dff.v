//=============================================================================
// axi4_out_dff.v  --  the output D flip-flops: what the master read back
//
// Four 32-bit registers.  Each read beat that arrives from the slave is
// stored in the register for its position (rd_idx).  The testbench looks at
// q0..q3 to see what came back.
//
// A value is stored on the clock edge where rd_valid = 1.  Reset clears them.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_out_dff (
    input  wire        clk,
    input  wire        resetn,          // active low

    input  wire        rd_valid,        // 1 = a read beat is arriving
    input  wire [1:0]  rd_idx,          // which beat (0..3)
    input  wire [31:0] rd_data,

    output reg  [31:0] q0,
    output reg  [31:0] q1,
    output reg  [31:0] q2,
    output reg  [31:0] q3
);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            q0 <= 32'd0;
            q1 <= 32'd0;
            q2 <= 32'd0;
            q3 <= 32'd0;
        end else if (rd_valid) begin
            case (rd_idx)
                2'd0: q0 <= rd_data;
                2'd1: q1 <= rd_data;
                2'd2: q2 <= rd_data;
                2'd3: q3 <= rd_data;
            endcase
        end
    end

endmodule

`default_nettype wire
