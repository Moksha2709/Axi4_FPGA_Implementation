//=============================================================================
// axi4_skid_buffer.v
//
// One registered pipeline stage for a single AXI4 valid/ready channel.
// This is the D-flip-flop element used for all communication between the
// manager and the subordinate: no signal crosses the module boundary through
// combinational logic, in either direction.
//
// Why a plain D-flip-flop is not enough
//   Registering VALID and the payload alone is not safe, because the upstream
//   READY would then have to come back combinationally.  Register READY too
//   and the transmitter keeps driving a beat the stage has already consumed,
//   so that beat is lost.  A skid buffer fixes this by holding up to TWO
//   payloads -- the output register plus one spare "skid" slot -- which buys
//   exactly the one cycle of slack needed to register READY as well.
//
// Properties
//   * in_ready, out_valid and the payload are ALL flip-flop outputs, so there
//     is no combinational path from any input to any output
//     (ARM IHI 0022 section A2.1.1).
//   * Latency 1 clock.  Throughput 1 beat per clock, no bubbles, so a 256-beat
//     burst still streams back to back.
//   * out_data never changes while out_valid is high and out_ready is low, so
//     the transmitter stability rule (section A2.3) is preserved downstream.
//
// Flow control
//   in_ready = ~skid_valid.  When the output register is blocked, the first
//   incoming beat lands in the skid slot, which immediately drops in_ready, so
//   a further beat can never arrive and nothing is ever overwritten.
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

module axi4_skid_buffer #(
    parameter WIDTH = 32                 // payload width of this channel
) (
    input  wire              ACLK,
    input  wire              ARESETn,    // active LOW, async

    // ---- Upstream (transmitter side) --------------------------------------
    input  wire [WIDTH-1:0]  in_data,
    input  wire              in_valid,
    output wire              in_ready,

    // ---- Downstream (receiver side) ---------------------------------------
    output reg  [WIDTH-1:0]  out_data,
    output reg               out_valid,
    input  wire              out_ready
);

    reg [WIDTH-1:0] skid_data;
    reg             skid_valid;

    assign in_ready = ~skid_valid;

    wire in_hs = in_valid & in_ready;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            out_data   <= {WIDTH{1'b0}};
            out_valid  <= 1'b0;
            skid_data  <= {WIDTH{1'b0}};
            skid_valid <= 1'b0;
        end else if (skid_valid) begin
            // Slot occupied, in_ready is low, so nothing new can arrive.
            // Wait for the receiver to take the output register, then promote.
            if (out_ready) begin
                out_data   <= skid_data;
                out_valid  <= 1'b1;
                skid_valid <= 1'b0;
            end
        end else begin
            if (out_valid && !out_ready) begin
                // Output register is stuck: park the incoming beat.
                if (in_hs) begin
                    skid_data  <= in_data;
                    skid_valid <= 1'b1;
                end
            end else begin
                // Output register is free, or is being drained this cycle.
                out_valid <= in_hs;
                if (in_hs) out_data <= in_data;
            end
        end
    end

endmodule

`default_nettype wire
