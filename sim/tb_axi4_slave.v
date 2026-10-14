//=============================================================================
// tb_axi4_slave.v  --  testbench for the slave on its own
//
// The testbench plays the AXI master: it drives the five channels directly.
// This tests the slave on its own, so every channel is driven by hand and
// every awkward case can be forced.
//
// Timing: 10 ns clock.  Every drive and every sample happens 1 ns after a
// rising edge, so a value read then is exactly what the DUT sees at the next
// edge.
//
// Tests
//   T1  single-beat write then read
//   T2  5-beat burst
//   T3  address first, data 3 cycles later
//   T4  data first, address 3 cycles later
//   T5  response held off 5 cycles, data beats with gaps
//   T6  read data held off 3 cycles before every beat
//   T7  byte strobes
//   T8  ID comes back on BID and RID
//   T9  longest burst, 256 beats
//   T10 reset in the middle of a burst, then recovery
//=============================================================================

`timescale 1ns / 1ps

`define DUT axi4_slave
`define VCD "tb_axi4_slave.vcd"

module tb_axi4_slave;

    localparam CLK_PERIOD = 10;

    reg         ACLK    = 1'b0;
    reg         ARESETN = 1'b0;

    reg  [3:0]  AWID    = 4'd0;
    reg  [31:0] AWADDR  = 32'd0;
    reg  [7:0]  AWLEN   = 8'd0;
    reg         AWVALID = 1'b0;
    wire        AWREADY;

    reg  [31:0] WDATA   = 32'd0;
    reg  [3:0]  WSTRB   = 4'd0;
    reg         WLAST   = 1'b0;
    reg         WVALID  = 1'b0;
    wire        WREADY;

    wire [3:0]  BID;
    wire [1:0]  BRESP;
    wire        BVALID;
    reg         BREADY  = 1'b0;

    reg  [3:0]  ARID    = 4'd0;
    reg  [31:0] ARADDR  = 32'd0;
    reg  [7:0]  ARLEN   = 8'd0;
    reg         ARVALID = 1'b0;
    wire        ARREADY;

    wire [3:0]  RID;
    wire [31:0] RDATA;
    wire [1:0]  RRESP;
    wire        RLAST;
    wire        RVALID;
    reg         RREADY  = 1'b0;

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    `DUT uut (
        .S_AXI_ACLK    (ACLK),
        .S_AXI_ARESETN (ARESETN),
        .S_AXI_AWID    (AWID),    .S_AXI_AWADDR (AWADDR), .S_AXI_AWLEN (AWLEN),
        .S_AXI_AWVALID (AWVALID), .S_AXI_AWREADY (AWREADY),
        .S_AXI_WDATA   (WDATA),   .S_AXI_WSTRB (WSTRB),   .S_AXI_WLAST (WLAST),
        .S_AXI_WVALID  (WVALID),  .S_AXI_WREADY (WREADY),
        .S_AXI_BID     (BID),     .S_AXI_BRESP (BRESP),
        .S_AXI_BVALID  (BVALID),  .S_AXI_BREADY (BREADY),
        .S_AXI_ARID    (ARID),    .S_AXI_ARADDR (ARADDR), .S_AXI_ARLEN (ARLEN),
        .S_AXI_ARVALID (ARVALID), .S_AXI_ARREADY (ARREADY),
        .S_AXI_RID     (RID),     .S_AXI_RDATA (RDATA),   .S_AXI_RRESP (RRESP),
        .S_AXI_RLAST   (RLAST),   .S_AXI_RVALID (RVALID), .S_AXI_RREADY (RREADY)
    );

    //-------------------------------------------------------------------------
    // Bookkeeping
    //-------------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;

    reg [31:0] wbuf [0:255];       // beats to send
    reg [3:0]  sbuf [0:255];       // strobes to send
    reg [31:0] rbuf [0:255];       // beats received
    reg [1:0]  cap_bresp;
    reg [3:0]  cap_bid;
    reg [3:0]  cap_rid;
    reg [1:0]  cap_rresp;

    task step;                      // one clock, landing 1 ns after the edge
        begin
            @(posedge ACLK);
            #1;
        end
    endtask

    task fail(input [8*48-1:0] msg);
        begin
            errors = errors + 1;
            $display("  [FAIL] %0s  (t=%0t)", msg, $time);
        end
    endtask

    task chk32(input [8*32-1:0] name, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got 0x%08h expected 0x%08h", name, got, exp);
            end else $display("  [ ok ] %0s = 0x%08h", name, got);
        end
    endtask

    //-------------------------------------------------------------------------
    // One task per channel, so channels can be run independently in a fork
    //-------------------------------------------------------------------------
    task aw_drive(input [3:0] id, input [31:0] addr, input [7:0] len, input integer delay);
        integer i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            AWID = id;  AWADDR = addr;  AWLEN = len;  AWVALID = 1'b1;
            while (!AWREADY) step;
            step;
            AWVALID = 1'b0;
        end
    endtask

    task w_drive(input [7:0] len, input integer delay, input integer gap);
        integer b, i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            for (b = 0; b <= len; b = b + 1) begin
                WDATA = wbuf[b];  WSTRB = sbuf[b];  WLAST = (b == len);  WVALID = 1'b1;
                while (!WREADY) step;
                step;
                if (gap > 0) begin
                    WVALID = 1'b0;
                    for (i = 0; i < gap; i = i + 1) step;
                end
            end
            WVALID = 1'b0;
            WLAST  = 1'b0;
        end
    endtask

    // Waits for BVALID, holds BREADY low for `stall` cycles while checking the
    // response does not change, then takes it.
    task b_accept(input integer stall);
        integer i;
        reg [1:0] f_resp;
        reg [3:0] f_id;
        begin
            while (!BVALID) step;
            f_resp = BRESP;  f_id = BID;
            for (i = 0; i < stall; i = i + 1) begin
                step;
                if (!BVALID)          fail("BVALID dropped before BREADY");
                if (BRESP !== f_resp) fail("BRESP changed while held");
                if (BID   !== f_id)   fail("BID changed while held");
            end
            cap_bresp = BRESP;  cap_bid = BID;
            BREADY = 1'b1;
            step;
            BREADY = 1'b0;
        end
    endtask

    task ar_drive(input [3:0] id, input [31:0] addr, input [7:0] len, input integer delay);
        integer i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            ARID = id;  ARADDR = addr;  ARLEN = len;  ARVALID = 1'b1;
            while (!ARREADY) step;
            step;
            ARVALID = 1'b0;
        end
    endtask

    // Collects len+1 beats into rbuf.  stall = 0 keeps RREADY high throughout.
    // stall > 0 holds RREADY low for that many cycles before every beat and
    // checks the beat does not change meanwhile.
    task r_accept(input [7:0] len, input integer stall);
        integer b, i;
        reg [31:0] f_data;
        reg        f_last;
        begin
            RREADY = (stall == 0);
            for (b = 0; b <= len; b = b + 1) begin
                if (stall > 0) begin
                    RREADY = 1'b0;
                    while (!RVALID) step;
                    f_data = RDATA;  f_last = RLAST;
                    for (i = 0; i < stall; i = i + 1) begin
                        step;
                        if (!RVALID)          fail("RVALID dropped before RREADY");
                        if (RDATA !== f_data) fail("RDATA changed while held");
                        if (RLAST !== f_last) fail("RLAST changed while held");
                    end
                    RREADY = 1'b1;
                end else begin
                    while (!RVALID) step;
                end
                rbuf[b] = RDATA;
                cap_rid = RID;
                cap_rresp = RRESP;
                if (RLAST && (b != len))  fail("RLAST arrived too early");
                if (!RLAST && (b == len)) fail("RLAST missing on last beat");
                step;
                if (stall > 0) RREADY = 1'b0;
            end
            RREADY = 1'b0;
        end
    endtask

    task burst_write(input [3:0] id, input [31:0] addr, input [7:0] len,
                     input integer aw_delay, input integer w_delay,
                     input integer gap, input integer b_stall);
        begin
            fork
                aw_drive(id, addr, len, aw_delay);
                w_drive(len, w_delay, gap);
                b_accept(b_stall);
            join
        end
    endtask

    task burst_read(input [3:0] id, input [31:0] addr, input [7:0] len,
                    input integer ar_delay, input integer r_stall);
        begin
            fork
                ar_drive(id, addr, len, ar_delay);
                r_accept(len, r_stall);
            join
        end
    endtask

    task fill(input [7:0] len, input [31:0] seed);
        integer b;
        begin
            for (b = 0; b <= len; b = b + 1) begin
                wbuf[b] = seed + (b * 32'h0101_0101);
                sbuf[b] = 4'b1111;
            end
        end
    endtask

    integer b;

    //-------------------------------------------------------------------------
    initial begin
        $dumpfile(`VCD);
        $dumpvars(0, tb_axi4_slave);

        $display("\n==== tb_axi4_slave : the slave on its own ====");

        ARESETN = 1'b0;
        repeat (5) @(posedge ACLK);
        #1;
        ARESETN = 1'b1;
        step;

        //---------------------------------------------------------------------
        $display("\n-- T1 : single-beat write then read at 0x00");
        wbuf[0] = 32'hDEAD_BEEF;  sbuf[0] = 4'b1111;
        burst_write(4'h1, 32'h0000_0000, 8'd0, 0, 0, 0, 0);
        chk32("T1 BRESP", {30'd0, cap_bresp}, 32'h0);
        burst_read (4'h1, 32'h0000_0000, 8'd0, 0, 0);
        chk32("T1 RDATA", rbuf[0], 32'hDEAD_BEEF);
        chk32("T1 RRESP", {30'd0, cap_rresp}, 32'h0);

        //---------------------------------------------------------------------
        $display("\n-- T2 : 5-beat burst at 0x100");
        fill(8'd4, 32'h1000_0001);
        burst_write(4'h2, 32'h0000_0100, 8'd4, 0, 0, 0, 0);
        burst_read (4'h2, 32'h0000_0100, 8'd4, 0, 0);
        for (b = 0; b <= 4; b = b + 1)
            chk32("T2 beat", rbuf[b], 32'h1000_0001 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T3 : address first, data 3 cycles later");
        fill(8'd2, 32'h3000_0003);
        burst_write(4'h3, 32'h0000_0200, 8'd2, 0, 3, 0, 0);
        burst_read (4'h3, 32'h0000_0200, 8'd2, 0, 0);
        for (b = 0; b <= 2; b = b + 1)
            chk32("T3 beat", rbuf[b], 32'h3000_0003 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T4 : data first, address 3 cycles later");
        fill(8'd2, 32'h4000_0004);
        burst_write(4'h4, 32'h0000_0300, 8'd2, 3, 0, 0, 0);
        burst_read (4'h4, 32'h0000_0300, 8'd2, 0, 0);
        for (b = 0; b <= 2; b = b + 1)
            chk32("T4 beat", rbuf[b], 32'h4000_0004 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T5 : response held off 5 cycles, gaps between data beats");
        fill(8'd3, 32'h5000_0005);
        burst_write(4'h5, 32'h0000_0400, 8'd3, 0, 2, 2, 5);
        burst_read (4'h5, 32'h0000_0400, 8'd3, 0, 0);
        for (b = 0; b <= 3; b = b + 1)
            chk32("T5 beat", rbuf[b], 32'h5000_0005 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T6 : read data held off 3 cycles before every beat");
        burst_read(4'h6, 32'h0000_0400, 8'd3, 0, 3);
        for (b = 0; b <= 3; b = b + 1)
            chk32("T6 beat", rbuf[b], 32'h5000_0005 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T7 : byte strobes");
        wbuf[0] = 32'hFFFF_FFFF;  sbuf[0] = 4'b1111;
        wbuf[1] = 32'hFFFF_FFFF;  sbuf[1] = 4'b1111;
        burst_write(4'h7, 32'h0000_0500, 8'd1, 0, 0, 0, 0);
        wbuf[0] = 32'h1122_3344;  sbuf[0] = 4'b0001;   // byte 0 only
        wbuf[1] = 32'h5566_7788;  sbuf[1] = 4'b1100;   // bytes 2 and 3
        burst_write(4'h7, 32'h0000_0500, 8'd1, 0, 0, 0, 0);
        burst_read (4'h7, 32'h0000_0500, 8'd1, 0, 0);
        chk32("T7 word 0", rbuf[0], 32'hFFFF_FF44);
        chk32("T7 word 1", rbuf[1], 32'h5566_FFFF);

        //---------------------------------------------------------------------
        $display("\n-- T8 : ID comes back on BID and RID");
        wbuf[0] = 32'h8888_8888;  sbuf[0] = 4'b1111;
        burst_write(4'hA, 32'h0000_0600, 8'd0, 0, 0, 0, 0);
        chk32("T8 BID", {28'd0, cap_bid}, 32'h0000_000A);
        burst_read (4'h5, 32'h0000_0600, 8'd0, 0, 0);
        chk32("T8 RID", {28'd0, cap_rid}, 32'h0000_0005);

        //---------------------------------------------------------------------
        $display("\n-- T9 : longest burst, 256 beats at 0x800");
        fill(8'd255, 32'h9000_0000);
        burst_write(4'h9, 32'h0000_0800, 8'd255, 0, 0, 0, 0);
        burst_read (4'h9, 32'h0000_0800, 8'd255, 0, 0);
        chk32("T9 beat   0", rbuf[0],   32'h9000_0000);
        chk32("T9 beat 100", rbuf[100], 32'h9000_0000 + (100 * 32'h0101_0101));
        chk32("T9 beat 255", rbuf[255], 32'h9000_0000 + (255 * 32'h0101_0101));

        //---------------------------------------------------------------------
        $display("\n-- T10 : reset in the middle of a burst, then recovery");
        AWID = 4'hB;  AWADDR = 32'h0000_0700;  AWLEN = 8'd7;  AWVALID = 1'b1;
        while (!AWREADY) step;
        step;
        AWVALID = 1'b0;
        for (b = 0; b < 2; b = b + 1) begin
            WDATA = 32'h7700_0000 + b;  WSTRB = 4'b1111;  WLAST = 1'b0;  WVALID = 1'b1;
            while (!WREADY) step;
            step;
        end
        ARESETN = 1'b0;                   // reset while 6 beats are still owed
        WVALID  = 1'b0;
        repeat (3) step;
        ARESETN = 1'b1;
        repeat (3) step;
        fill(8'd3, 32'h7A7A_0000);
        burst_write(4'hC, 32'h0000_0900, 8'd3, 0, 0, 0, 0);
        burst_read (4'hC, 32'h0000_0900, 8'd3, 0, 0);
        for (b = 0; b <= 3; b = b + 1)
            chk32("T10 beat after reset", rbuf[b], 32'h7A7A_0000 + (b * 32'h0101_0101));

        //---------------------------------------------------------------------
        repeat (5) step;
        $display("\n==== result : %0d checks, %0d failure(s) ====", checks, errors);
        if (errors == 0) $display("TEST PASSED\n");
        else             $display("TEST FAILED\n");
        $finish;
    end

    initial begin
        #2000000;
        $display("\n[FAIL] timed out -- possible deadlock");
        $display("TEST FAILED\n");
        $finish;
    end

endmodule
