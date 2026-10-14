//=============================================================================
// axi4_reg_stage.v  --  one D flip-flop stage for one AXI channel
//
// It holds ONE beat in flip-flops.
//
//   empty : in_ready = 1, so the sender may hand over a beat.
//   full  : in_ready = 0, so the sender must wait.  The beat is offered on
//           out_valid until the next side takes it (out_ready = 1).
//
// in_ready comes straight from a flip-flop (out_valid), so a late READY can
// never cause a beat to be lost or sent twice.
// Cost: a beat sits in the stage for a clock, so one beat moves every two
// clocks through a stage.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_reg_stage #(
    parameter WIDTH = 32
) (
    input  wire              clk,
    input  wire              resetn,         // active low

    input  wire [WIDTH-1:0]  in_data,
    input  wire              in_valid,
    output wire              in_ready,

    output reg  [WIDTH-1:0]  out_data,
    output reg               out_valid,
    input  wire              out_ready
);

    assign in_ready = ~out_valid;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            out_data  <= {WIDTH{1'b0}};
            out_valid <= 1'b0;
        end else if (in_valid && in_ready) begin
            out_data  <= in_data;            // take the beat
            out_valid <= 1'b1;
        end else if (out_valid && out_ready) begin
            out_valid <= 1'b0;               // beat was taken, stage is empty
        end
    end

endmodule

`default_nettype wire
