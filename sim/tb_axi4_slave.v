//=============================================================================
// tb_axi4_slave.v  --  Level 1 : AXI4 subordinate unit testbench
//
// The testbench acts as the manager and drives all five channels directly, so
// channel skew and per-beat back-pressure can be forced -- which is exactly
// what a real manager will not do on demand.
//
// Timing convention
//   10 ns clock.  Every stimulus change and every sample happens 1 ns after a
//   rising edge, so a value observed at that moment is precisely the value the
//   DUT will sample at the NEXT rising edge.  That makes the handshake loops
//   race free.
//
// Tests
//   A1  single beat write + read
//   A2  INCR burst, 5 beats, write then read back
//   A3  WRAP burst, 4 beats, address folds at the wrap boundary
//   A4  FIXED burst, 4 beats, every beat hits the same address
//   A5  WSTRB byte merging inside a burst
//   A6  per-beat RREADY back-pressure with payload stability checks
//   A7  BREADY stall with response stability checks
//   A8  DECERR for an address outside the decoded region
//   A9  BID echoes AWID and RID echoes ARID
//   A10 SLVERR for a reserved burst type and for an illegal WRAP length
//   A11 narrow transfers: four 1-byte beats assemble into one word
//=============================================================================

`timescale 1ns / 1ps

module tb_axi4_slave;

    localparam CLK_PERIOD    = 10;
    localparam ID_WIDTH      = 4;
    localparam ADDR_WIDTH    = 32;
    localparam DATA_WIDTH    = 32;
    localparam MEM_ADDR_BITS = 12;         // 4 KiB decoded region

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    //-------------------------------------------------------------------------
    reg ACLK    = 1'b0;
    reg ARESETn = 1'b0;

    reg  [ID_WIDTH-1:0]   AWID    = 0;
    reg  [ADDR_WIDTH-1:0] AWADDR  = 0;
    reg  [7:0]            AWLEN   = 0;
    reg  [2:0]            AWSIZE  = 3'd2;
    reg  [1:0]            AWBURST = BURST_INCR;
    reg                   AWLOCK  = 0;
    reg  [3:0]            AWCACHE = 4'b0011;
    reg  [2:0]            AWPROT  = 0;
    reg  [3:0]            AWQOS   = 0;
    reg                   AWVALID = 0;
    wire                  AWREADY;

    reg  [DATA_WIDTH-1:0]     WDATA  = 0;
    reg  [(DATA_WIDTH/8)-1:0] WSTRB  = 0;
    reg                       WLAST  = 0;
    reg                       WVALID = 0;
    wire                      WREADY;

    wire [ID_WIDTH-1:0] BID;
    wire [1:0]          BRESP;
    wire                BVALID;
    reg                 BREADY = 0;

    reg  [ID_WIDTH-1:0]   ARID    = 0;
    reg  [ADDR_WIDTH-1:0] ARADDR  = 0;
    reg  [7:0]            ARLEN   = 0;
    reg  [2:0]            ARSIZE  = 3'd2;
    reg  [1:0]            ARBURST = BURST_INCR;
    reg                   ARLOCK  = 0;
    reg  [3:0]            ARCACHE = 4'b0011;
    reg  [2:0]            ARPROT  = 0;
    reg  [3:0]            ARQOS   = 0;
    reg                   ARVALID = 0;
    wire                  ARREADY;

    wire [ID_WIDTH-1:0]   RID;
    wire [DATA_WIDTH-1:0] RDATA;
    wire [1:0]            RRESP;
    wire                  RLAST;
    wire                  RVALID;
    reg                   RREADY = 0;

    //-------------------------------------------------------------------------
    // Scoreboard and beat buffers
    //-------------------------------------------------------------------------
    integer errors = 0;
    integer checks = 0;

    reg [DATA_WIDTH-1:0]     wbuf [0:255];   // beats to drive on W
    reg [(DATA_WIDTH/8)-1:0] sbuf [0:255];   // strobes to drive on W
    reg [DATA_WIDTH-1:0]     rbuf [0:255];   // beats captured from R

    reg [1:0]          cap_bresp;
    reg [ID_WIDTH-1:0] cap_bid;
    reg [1:0]          cap_rresp;
    reg [ID_WIDTH-1:0] cap_rid;

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    //-------------------------------------------------------------------------
    axi4_slave #(
        .ID_WIDTH      (ID_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_ADDR_BITS (MEM_ADDR_BITS)
    ) uut (
        .S_AXI_ACLK    (ACLK),
        .S_AXI_ARESETN (ARESETn),

        .S_AXI_AWID    (AWID),
        .S_AXI_AWADDR  (AWADDR),
        .S_AXI_AWLEN   (AWLEN),
        .S_AXI_AWSIZE  (AWSIZE),
        .S_AXI_AWBURST (AWBURST),
        .S_AXI_AWLOCK  (AWLOCK),
        .S_AXI_AWCACHE (AWCACHE),
        .S_AXI_AWPROT  (AWPROT),
        .S_AXI_AWQOS   (AWQOS),
        .S_AXI_AWVALID (AWVALID),
        .S_AXI_AWREADY (AWREADY),

        .S_AXI_WDATA   (WDATA),
        .S_AXI_WSTRB   (WSTRB),
        .S_AXI_WLAST   (WLAST),
        .S_AXI_WVALID  (WVALID),
        .S_AXI_WREADY  (WREADY),

        .S_AXI_BID     (BID),
        .S_AXI_BRESP   (BRESP),
        .S_AXI_BVALID  (BVALID),
        .S_AXI_BREADY  (BREADY),

        .S_AXI_ARID    (ARID),
        .S_AXI_ARADDR  (ARADDR),
        .S_AXI_ARLEN   (ARLEN),
        .S_AXI_ARSIZE  (ARSIZE),
        .S_AXI_ARBURST (ARBURST),
        .S_AXI_ARLOCK  (ARLOCK),
        .S_AXI_ARCACHE (ARCACHE),
        .S_AXI_ARPROT  (ARPROT),
        .S_AXI_ARQOS   (ARQOS),
        .S_AXI_ARVALID (ARVALID),
        .S_AXI_ARREADY (ARREADY),

        .S_AXI_RID     (RID),
        .S_AXI_RDATA   (RDATA),
        .S_AXI_RRESP   (RRESP),
        .S_AXI_RLAST   (RLAST),
        .S_AXI_RVALID  (RVALID),
        .S_AXI_RREADY  (RREADY)
    );

    //-------------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------------
    task step;
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

    task chk2(input [8*32-1:0] name, input [1:0] got, input [1:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got 2'b%02b expected 2'b%02b", name, got, exp);
            end else $display("  [ ok ] %0s = 2'b%02b", name, got);
        end
    endtask

    //-------------------------------------------------------------------------
    // Channel drivers
    //-------------------------------------------------------------------------
    task aw_drive(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                  input [7:0] len, input [2:0] size, input [1:0] burst,
                  input integer delay);
        integer i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            AWID    = id;
            AWADDR  = addr;
            AWLEN   = len;
            AWSIZE  = size;
            AWBURST = burst;
            AWVALID = 1'b1;
            while (!AWREADY) step;
            step;
            AWVALID = 1'b0;
        end
    endtask

    // Drives len+1 beats from wbuf/sbuf, optionally inserting `gap` idle
    // cycles between beats to exercise a bubbly manager.
    task w_drive(input [7:0] len, input integer delay, input integer gap);
        integer b, i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            for (b = 0; b <= len; b = b + 1) begin
                WDATA  = wbuf[b];
                WSTRB  = sbuf[b];
                WLAST  = (b == len);
                WVALID = 1'b1;
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

    // Waits for BVALID, holds BREADY low for `stall` cycles while proving the
    // response is stable, then accepts it.
    task b_accept(input integer stall);
        integer i;
        reg [1:0]          f_resp;
        reg [ID_WIDTH-1:0] f_id;
        begin
            while (!BVALID) step;
            f_resp = BRESP;
            f_id   = BID;
            for (i = 0; i < stall; i = i + 1) begin
                step;
                if (!BVALID)         fail("BVALID dropped before BREADY");
                if (BRESP !== f_resp) fail("BRESP changed while stalled");
                if (BID   !== f_id)   fail("BID changed while stalled");
            end
            cap_bresp = BRESP;
            cap_bid   = BID;
            BREADY    = 1'b1;
            step;
            BREADY    = 1'b0;
        end
    endtask

    task ar_drive(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                  input [7:0] len, input [2:0] size, input [1:0] burst,
                  input integer delay);
        integer i;
        begin
            for (i = 0; i < delay; i = i + 1) step;
            ARID    = id;
            ARADDR  = addr;
            ARLEN   = len;
            ARSIZE  = size;
            ARBURST = burst;
            ARVALID = 1'b1;
            while (!ARREADY) step;
            step;
            ARVALID = 1'b0;
        end
    endtask

    // Collects exp_len+1 beats into rbuf.  stall == 0 keeps RREADY high for
    // the whole burst (full-throughput check); stall > 0 deasserts RREADY for
    // that many cycles before each beat and verifies the payload holds.
    task r_accept(input [7:0] exp_len, input integer stall);
        integer b, i;
        reg [DATA_WIDTH-1:0] f_data;
        reg [1:0]            f_resp;
        reg                  f_last;
        reg [ID_WIDTH-1:0]   f_id;
        begin
            RREADY = (stall == 0);
            for (b = 0; b <= exp_len; b = b + 1) begin
                if (stall > 0) begin
                    RREADY = 1'b0;
                    while (!RVALID) step;
                    f_data = RDATA;  f_resp = RRESP;
                    f_last = RLAST;  f_id   = RID;
                    for (i = 0; i < stall; i = i + 1) begin
                        step;
                        if (!RVALID)           fail("RVALID dropped before RREADY");
                        if (RDATA !== f_data)  fail("RDATA changed while stalled");
                        if (RRESP !== f_resp)  fail("RRESP changed while stalled");
                        if (RLAST !== f_last)  fail("RLAST changed while stalled");
                        if (RID   !== f_id)    fail("RID changed while stalled");
                    end
                    RREADY = 1'b1;
                end else begin
                    while (!RVALID) step;
                end

                rbuf[b]   = RDATA;
                cap_rresp = RRESP;
                cap_rid   = RID;

                if (RLAST && (b != exp_len)) fail("RLAST asserted too early");
                if (!RLAST && (b == exp_len)) fail("RLAST missing on final beat");

                step;                       // the handshake happens here
                if (stall > 0) RREADY = 1'b0;
            end
            RREADY = 1'b0;
        end
    endtask

    //-------------------------------------------------------------------------
    // Composite burst transactions
    //-------------------------------------------------------------------------
    task burst_write(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                     input [7:0] len, input [2:0] size, input [1:0] burst,
                     input integer aw_delay, input integer w_delay,
                     input integer gap, input integer b_stall);
        begin
            fork
                aw_drive(id, addr, len, size, burst, aw_delay);
                w_drive(len, w_delay, gap);
                b_accept(b_stall);
            join
        end
    endtask

    task burst_read(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                    input [7:0] len, input [2:0] size, input [1:0] burst,
                    input integer ar_delay, input integer r_stall);
        begin
            fork
                ar_drive(id, addr, len, size, burst, ar_delay);
                r_accept(len, r_stall);
            join
        end
    endtask

    // Fill wbuf with an incrementing pattern and full strobes.
    task fill_pattern(input [7:0] len, input [31:0] seed);
        integer b;
        begin
            for (b = 0; b <= len; b = b + 1) begin
                wbuf[b] = seed + (b * 32'h0101_0101);
                sbuf[b] = {(DATA_WIDTH/8){1'b1}};
            end
        end
    endtask

    integer b;

    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_axi4_slave.vcd");
        $dumpvars(0, tb_axi4_slave);

        $display("\n==== Level 1 : axi4_slave unit test ====");

        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK);
        #1;
        ARESETn = 1'b1;
        step;

        //=====================================================================
        $display("\n-- A1 : single-beat write and read at 0x000");
        wbuf[0] = 32'hDEAD_BEEF;  sbuf[0] = 4'b1111;
        burst_write(4'h1, 32'h0000_0000, 8'd0, 3'd2, BURST_INCR, 0, 0, 0, 0);
        chk2("A1 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'h1, 32'h0000_0000, 8'd0, 3'd2, BURST_INCR, 0, 0);
        chk32("A1 RDATA", rbuf[0], 32'hDEAD_BEEF);
        chk2 ("A1 RRESP", cap_rresp, RESP_OKAY);

        //=====================================================================
        $display("\n-- A2 : INCR burst of 5 beats at 0x100");
        fill_pattern(8'd4, 32'h1000_0001);
        burst_write(4'h2, 32'h0000_0100, 8'd4, 3'd2, BURST_INCR, 0, 0, 0, 0);
        chk2("A2 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'h2, 32'h0000_0100, 8'd4, 3'd2, BURST_INCR, 0, 0);
        for (b = 0; b <= 4; b = b + 1)
            chk32("A2 beat", rbuf[b], 32'h1000_0001 + (b * 32'h0101_0101));

        //=====================================================================
        // WRAP, 4 beats of 4 bytes => a 16-byte window starting at 0x200.
        // Starting at 0x208 the beat addresses are 0x208, 0x20C, 0x200, 0x204.
        $display("\n-- A3 : WRAP burst of 4 beats starting mid-window (0x208)");
        wbuf[0] = 32'hAAAA_0000; sbuf[0] = 4'b1111;
        wbuf[1] = 32'hBBBB_1111; sbuf[1] = 4'b1111;
        wbuf[2] = 32'hCCCC_2222; sbuf[2] = 4'b1111;
        wbuf[3] = 32'hDDDD_3333; sbuf[3] = 4'b1111;
        burst_write(4'h3, 32'h0000_0208, 8'd3, 3'd2, BURST_WRAP, 0, 0, 0, 0);
        chk2("A3 BRESP", cap_bresp, RESP_OKAY);
        // Read the window back linearly: 0x200,0x204,0x208,0x20C
        burst_read (4'h3, 32'h0000_0200, 8'd3, 3'd2, BURST_INCR, 0, 0);
        chk32("A3 mem[0x200]", rbuf[0], 32'hCCCC_2222);
        chk32("A3 mem[0x204]", rbuf[1], 32'hDDDD_3333);
        chk32("A3 mem[0x208]", rbuf[2], 32'hAAAA_0000);
        chk32("A3 mem[0x20C]", rbuf[3], 32'hBBBB_1111);
        // And read it back as a WRAP burst from the same start address.
        burst_read (4'h3, 32'h0000_0208, 8'd3, 3'd2, BURST_WRAP, 0, 0);
        chk32("A3 wrap beat0", rbuf[0], 32'hAAAA_0000);
        chk32("A3 wrap beat1", rbuf[1], 32'hBBBB_1111);
        chk32("A3 wrap beat2", rbuf[2], 32'hCCCC_2222);
        chk32("A3 wrap beat3", rbuf[3], 32'hDDDD_3333);

        //=====================================================================
        $display("\n-- A4 : FIXED burst of 4 beats, all to 0x300");
        wbuf[0] = 32'h0000_00E0; sbuf[0] = 4'b1111;
        wbuf[1] = 32'h0000_00E1; sbuf[1] = 4'b1111;
        wbuf[2] = 32'h0000_00E2; sbuf[2] = 4'b1111;
        wbuf[3] = 32'h0000_00E3; sbuf[3] = 4'b1111;
        burst_write(4'h4, 32'h0000_0300, 8'd3, 3'd2, BURST_FIXED, 0, 0, 0, 0);
        chk2("A4 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'h4, 32'h0000_0300, 8'd0, 3'd2, BURST_INCR, 0, 0);
        chk32("A4 last beat wins", rbuf[0], 32'h0000_00E3);
        burst_read (4'h4, 32'h0000_0304, 8'd0, 3'd2, BURST_INCR, 0, 0);
        chk32("A4 next word untouched", rbuf[0], 32'h0000_0000);

        //=====================================================================
        $display("\n-- A5 : WSTRB byte merging inside a burst");
        wbuf[0] = 32'hFFFF_FFFF; sbuf[0] = 4'b1111;
        wbuf[1] = 32'hFFFF_FFFF; sbuf[1] = 4'b1111;
        burst_write(4'h5, 32'h0000_0400, 8'd1, 3'd2, BURST_INCR, 0, 0, 0, 0);
        wbuf[0] = 32'h1122_3344; sbuf[0] = 4'b0001;   // byte 0 only
        wbuf[1] = 32'h5566_7788; sbuf[1] = 4'b1100;   // bytes 2 and 3
        burst_write(4'h5, 32'h0000_0400, 8'd1, 3'd2, BURST_INCR, 0, 0, 0, 0);
        chk2("A5 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'h5, 32'h0000_0400, 8'd1, 3'd2, BURST_INCR, 0, 0);
        chk32("A5 mem[0x400]", rbuf[0], 32'hFFFF_FF44);
        chk32("A5 mem[0x404]", rbuf[1], 32'h5566_FFFF);

        //=====================================================================
        $display("\n-- A6 : RREADY deasserted 3 cycles before every beat");
        burst_read(4'h6, 32'h0000_0100, 8'd4, 3'd2, BURST_INCR, 0, 3);
        for (b = 0; b <= 4; b = b + 1)
            chk32("A6 beat", rbuf[b], 32'h1000_0001 + (b * 32'h0101_0101));

        //=====================================================================
        $display("\n-- A7 : BREADY held low for 5 cycles, W beats bubbly");
        fill_pattern(8'd3, 32'h7000_0007);
        burst_write(4'h7, 32'h0000_0500, 8'd3, 3'd2, BURST_INCR, 0, 2, 2, 5);
        chk2("A7 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'h7, 32'h0000_0500, 8'd3, 3'd2, BURST_INCR, 0, 0);
        for (b = 0; b <= 3; b = b + 1)
            chk32("A7 beat", rbuf[b], 32'h7000_0007 + (b * 32'h0101_0101));

        //=====================================================================
        $display("\n-- A8 : address 0x2000 is outside the 4 KiB region -> DECERR");
        fill_pattern(8'd2, 32'hBAD0_0000);
        burst_write(4'h8, 32'h0000_2000, 8'd2, 3'd2, BURST_INCR, 0, 0, 0, 0);
        chk2("A8 BRESP", cap_bresp, RESP_DECERR);
        burst_read (4'h8, 32'h0000_2000, 8'd2, 3'd2, BURST_INCR, 0, 0);
        chk2 ("A8 RRESP", cap_rresp, RESP_DECERR);
        chk32("A8 RDATA zeroed", rbuf[0], 32'h0000_0000);

        //=====================================================================
        $display("\n-- A9 : identifier echo");
        wbuf[0] = 32'h9999_9999; sbuf[0] = 4'b1111;
        burst_write(4'hA, 32'h0000_0600, 8'd0, 3'd2, BURST_INCR, 0, 0, 0, 0);
        chk32("A9 BID echoes AWID", {28'd0, cap_bid}, 32'h0000_000A);
        burst_read (4'h5, 32'h0000_0600, 8'd0, 3'd2, BURST_INCR, 0, 0);
        chk32("A9 RID echoes ARID", {28'd0, cap_rid}, 32'h0000_0005);

        //=====================================================================
        $display("\n-- A10 : unsupported requests -> SLVERR");
        fill_pattern(8'd1, 32'h5A5A_0000);
        burst_write(4'hB, 32'h0000_0700, 8'd1, 3'd2, 2'b11, 0, 0, 0, 0);
        chk2("A10 reserved burst type (write)", cap_bresp, RESP_SLVERR);
        burst_read (4'hB, 32'h0000_0700, 8'd1, 3'd2, 2'b11, 0, 0);
        chk2("A10 reserved burst type (read)", cap_rresp, RESP_SLVERR);
        // WRAP must be 2, 4, 8 or 16 beats; 5 beats is illegal.
        fill_pattern(8'd4, 32'h5A5A_1111);
        burst_write(4'hB, 32'h0000_0700, 8'd4, 3'd2, BURST_WRAP, 0, 0, 0, 0);
        chk2("A10 illegal WRAP length", cap_bresp, RESP_SLVERR);
        // AxSIZE of 8 bytes is wider than this 32-bit data bus.
        fill_pattern(8'd0, 32'h5A5A_2222);
        burst_write(4'hB, 32'h0000_0700, 8'd0, 3'd3, BURST_INCR, 0, 0, 0, 0);
        chk2("A10 AxSIZE wider than bus", cap_bresp, RESP_SLVERR);

        //=====================================================================
        // Narrow transfers: AxSIZE = 0 means one byte per beat, and the active
        // byte lane follows the address.  Four beats from 0x800 therefore fill
        // the four lanes of a single 32-bit word.
        $display("\n-- A11 : narrow 1-byte beats assemble one word at 0x800");
        wbuf[0] = 32'h0000_0011; sbuf[0] = 4'b0001;   // lane 0 <- 0x11
        wbuf[1] = 32'h0000_2200; sbuf[1] = 4'b0010;   // lane 1 <- 0x22
        wbuf[2] = 32'h0033_0000; sbuf[2] = 4'b0100;   // lane 2 <- 0x33
        wbuf[3] = 32'h4400_0000; sbuf[3] = 4'b1000;   // lane 3 <- 0x44
        burst_write(4'hC, 32'h0000_0800, 8'd3, 3'd0, BURST_INCR, 0, 0, 0, 0);
        chk2("A11 BRESP", cap_bresp, RESP_OKAY);
        burst_read (4'hC, 32'h0000_0800, 8'd0, 3'd2, BURST_INCR, 0, 0);
        chk32("A11 assembled word", rbuf[0], 32'h4433_2211);

        //=====================================================================
        repeat (5) step;
        $display("\n==== Level 1 result : %0d checks, %0d failure(s) ====",
                 checks, errors);
        if (errors == 0) $display("TEST PASSED\n");
        else             $display("TEST FAILED\n");
        $finish;
    end

    initial begin
        #200000;
        $display("\n[FAIL] tb_axi4_slave timed out -- possible deadlock");
        $display("TEST FAILED\n");
        $finish;
    end

endmodule
