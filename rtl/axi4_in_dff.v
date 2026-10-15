//=============================================================================
// axi4_in_dff.v  --  the input D flip-flops: what the master will write
//
// Five 32-bit registers.  The testbench loads them one at a time; the master
// reads their outputs.
//
//   load_sel 0 : addr   the address to write to
//   load_sel 1 : data0  first word
//   load_sel 2 : data1
//   load_sel 3 : data2
//   load_sel 4 : data3  last word
//
// A value is stored on the clock edge where load = 1.  Reset clears them to 0.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_in_dff (
    input  wire        clk,
    input  wire        resetn,          // active low

    input  wire        load,            // 1 = store load_data into register load_sel
    input  wire [2:0]  load_sel,
    input  wire [31:0] load_data,

    output reg  [31:0] addr,
    output reg  [31:0] data0,
    output reg  [31:0] data1,
    output reg  [31:0] data2,
    output reg  [31:0] data3
);

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            addr  <= 32'd0;
            data0 <= 32'd0;
            data1 <= 32'd0;
            data2 <= 32'd0;
            data3 <= 32'd0;
        end else if (load) begin
            case (load_sel)
                3'd0: addr  <= load_data;
                3'd1: data0 <= load_data;
                3'd2: data1 <= load_data;
                3'd3: data2 <= load_data;
                3'd4: data3 <= load_data;
                default: ;
            endcase
        end
    end

endmodule

`default_nettype wire
