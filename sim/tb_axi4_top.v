//=============================================================================
// tb_axi4_top.v  --  Level 3 : integrated AXI4 system testbench
//
// Drives axi4_top, which is the manager wired to the subordinate through the
// five D-flip-flop (skid buffer) channel stages.  Everything is exercised from
// the host ports only, exactly as real logic in the fabric would use it.
//
// The parameter PIPE_STAGE is forwarded to the DUT so the same testbench can
// be run with the registered channels (the default, 1) or with the modules
// wired directly (0):
//     iverilog -Ptb_axi4_top.PIPE_STAGE=0 ...
// The reported cycle counts then show what the pipeline stages cost: latency
// goes up by a fixed handful of clocks, throughput does not change.
//
// Tests
//   I1 8-beat INCR write then read back
//   I2 WRAP burst written, then read back linearly
//   I3 FIXED burst: every beat lands on the same address
//   I4 WSTRB byte merging across a burst
//   I5 DECERR from an out-of-range address, reported at the host
//   I6 read back-pressure from the host mid-burst
//   I7 asynchronous reset in the middle of a write burst, then recovery
//   I8 32-beat write and read, used to measure sustained throughput
//=============================================================================

`timescale 1ns / 1ps

module tb_axi4_top;

    parameter PIPE_STAGE = 1;              // overridable from the command line

    localparam CLK_PERIOD    = 10;
    localparam ID_WIDTH      = 4;
    localparam ADDR_WIDTH    = 32;
    localparam DATA_WIDTH    = 32;
    localparam MEM_ADDR_BITS = 12;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_DECERR = 2'b11;

    localparam [1:0] BURST_FIXED = 2'b00;
    localparam [1:0] BURST_INCR  = 2'b01;
    localparam [1:0] BURST_WRAP  = 2'b10;

    //-------------------------------------------------------------------------
    reg ACLK    = 1'b0;
    reg ARESETn = 1'b0;

    reg  [ID_WIDTH-1:0]   cmd_id          = 0;
    reg  [ADDR_WIDTH-1:0] cmd_addr        = 0;
    reg  [7:0]            cmd_len         = 0;
    reg  [2:0]            cmd_size        = 3'd2;
    reg  [1:0]            cmd_burst       = BURST_INCR;
    reg                   cmd_start_write = 0;
    reg                   cmd_start_read  = 0;
    wire                  cmd_busy;
    wire                  cmd_done;
    wire [1:0]            cmd_resp;
    wire [ID_WIDTH-1:0]   cmd_resp_id;
    wire                  cmd_last_err;

    reg  [DATA_WIDTH-1:0]     hw_data  = 0;
    reg  [(DATA_WIDTH/8)-1:0] hw_strb  = 0;
    reg                       hw_valid = 0;
    wire                      hw_ready;

    wire [DATA_WIDTH-1:0] hr_data;
    wire [1:0]            hr_resp;
    wire                  hr_last;
    wire                  hr_valid;
    reg                   hr_ready = 0;

    integer errors = 0;
    integer checks = 0;

    reg [DATA_WIDTH-1:0]     wbuf [0:255];
    reg [(DATA_WIDTH/8)-1:0] sbuf [0:255];
    reg [DATA_WIDTH-1:0]     rbuf [0:255];

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    //-------------------------------------------------------------------------
    axi4_top #(
        .ID_WIDTH      (ID_WIDTH),
        .ADDR_WIDTH    (ADDR_WIDTH),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_ADDR_BITS (MEM_ADDR_BITS),
        .PIPE_STAGE    (PIPE_STAGE)
    ) uut (
        .ACLK            (ACLK),
        .ARESETn         (ARESETn),

        .cmd_start_write (cmd_start_write),
        .cmd_start_read  (cmd_start_read),
        .cmd_id          (cmd_id),
        .cmd_addr        (cmd_addr),
        .cmd_len         (cmd_len),
        .cmd_size        (cmd_size),
        .cmd_burst       (cmd_burst),
        .cmd_busy        (cmd_busy),
        .cmd_done        (cmd_done),
        .cmd_resp        (cmd_resp),
        .cmd_resp_id     (cmd_resp_id),
        .cmd_last_err    (cmd_last_err),

        .hw_data         (hw_data),
        .hw_strb         (hw_strb),
        .hw_valid        (hw_valid),
        .hw_ready        (hw_ready),

        .hr_data         (hr_data),
        .hr_resp         (hr_resp),
        .hr_last         (hr_last),
        .hr_valid        (hr_valid),
        .hr_ready        (hr_ready)
    );

    //-------------------------------------------------------------------------
    // Reporting
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

    task chk_int(input [8*32-1:0] name, input integer got, input integer exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got %0d expected %0d", name, got, exp);
            end else $display("  [ ok ] %0s = %0d", name, got);
        end
    endtask

    //-------------------------------------------------------------------------
    // Host drivers
    //-------------------------------------------------------------------------
    integer cycles_used;

    task host_write(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                    input [7:0] len, input [2:0] size, input [1:0] burst,
                    input integer gap);
        integer b, i, t0;
        begin
            while (cmd_busy) step;
            t0              = $time;
            cmd_id          = id;
            cmd_addr        = addr;
            cmd_len         = len;
            cmd_size        = size;
            cmd_burst       = burst;
            cmd_start_write = 1'b1;
            step;
            cmd_start_write = 1'b0;

            for (b = 0; b <= len; b = b + 1) begin
                hw_data  = wbuf[b];
                hw_strb  = sbuf[b];
                hw_valid = 1'b1;
                while (!hw_ready) step;
                step;
                if (gap > 0) begin
                    hw_valid = 1'b0;
                    for (i = 0; i < gap; i = i + 1) step;
                end
            end
            hw_valid = 1'b0;

            while (!cmd_done) begin
                if (!cmd_busy) fail("cmd_busy low before cmd_done");
                step;
            end
            cycles_used = ($time - t0) / CLK_PERIOD;
        end
    endtask

    task host_read(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                   input [7:0] len, input [2:0] size, input [1:0] burst,
                   input integer stall);
        integer b, i, t0;
        begin
            while (cmd_busy) step;
            t0             = $time;
            cmd_id         = id;
            cmd_addr       = addr;
            cmd_len        = len;
            cmd_size       = size;
            cmd_burst      = burst;
            cmd_start_read = 1'b1;
            step;
            cmd_start_read = 1'b0;

            hr_ready = (stall == 0);
            for (b = 0; b <= len; b = b + 1) begin
                if (stall > 0) begin
                    hr_ready = 1'b0;
                    while (!hr_valid) step;
                    for (i = 0; i < stall; i = i + 1) step;
                    hr_ready = 1'b1;
                end else begin
                    while (!hr_valid) step;
                end

                rbuf[b] = hr_data;
                if (hr_resp !== RESP_OKAY && hr_resp !== cmd_resp) begin
                    // non-OKAY beats are legal; cmd_resp accumulates them
                end
                if (hr_last && (b != len))  fail("hr_last asserted too early");
                if (!hr_last && (b == len)) fail("hr_last missing on final beat");

                step;
                if (stall > 0) hr_ready = 1'b0;
            end
            hr_ready = 1'b0;

            while (!cmd_done) begin
                if (!cmd_busy) fail("cmd_busy low before cmd_done");
                step;
            end
            cycles_used = ($time - t0) / CLK_PERIOD;
        end
    endtask

    task fill_pattern(input [7:0] len, input [31:0] seed);
        integer b;
        begin
            for (b = 0; b <= len; b = b + 1) begin
                wbuf[b] = seed + (b * 32'h0010_0001);
                sbuf[b] = {(DATA_WIDTH/8){1'b1}};
            end
        end
    endtask

    integer b;
    integer wr_cycles_32;
    integer rd_cycles_32;

    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_axi4_top.vcd");
        $dumpvars(0, tb_axi4_top);

        $display("\n==== Level 3 : axi4_top integration test  (PIPE_STAGE = %0d) ====",
                 PIPE_STAGE);
        if (PIPE_STAGE != 0)
            $display("     all five channels pass through a D-flip-flop stage");
        else
            $display("     manager wired directly to subordinate (no FF stage)");

        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK);
        #1;
        ARESETn = 1'b1;
        step;

        //=====================================================================
        $display("\n-- I1 : 8-beat INCR write at 0x100, then read it back");
        fill_pattern(8'd7, 32'h1100_0000);
        host_write(4'h1, 32'h0000_0100, 8'd7, 3'd2, BURST_INCR, 0);
        chk2 ("I1 BRESP", cmd_resp, RESP_OKAY);
        chk32("I1 BID echoed", {28'd0, cmd_resp_id}, 32'h0000_0001);
        $display("  write took %0d cycles", cycles_used);

        host_read(4'h1, 32'h0000_0100, 8'd7, 3'd2, BURST_INCR, 0);
        chk2("I1 RRESP", cmd_resp, RESP_OKAY);
        $display("  read took %0d cycles", cycles_used);
        for (b = 0; b <= 7; b = b + 1)
            chk32("I1 beat", rbuf[b], 32'h1100_0000 + (b * 32'h0010_0001));

        //=====================================================================
        // 4 beats x 4 bytes = a 16-byte wrap window based at 0x200.
        // Starting at 0x208 the beats go 0x208, 0x20C, 0x200, 0x204.
        $display("\n-- I2 : WRAP burst from 0x208, then linear read of the window");
        wbuf[0] = 32'h2000_AAAA; sbuf[0] = 4'b1111;
        wbuf[1] = 32'h2000_BBBB; sbuf[1] = 4'b1111;
        wbuf[2] = 32'h2000_CCCC; sbuf[2] = 4'b1111;
        wbuf[3] = 32'h2000_DDDD; sbuf[3] = 4'b1111;
        host_write(4'h2, 32'h0000_0208, 8'd3, 3'd2, BURST_WRAP, 0);
        chk2("I2 BRESP", cmd_resp, RESP_OKAY);

        host_read(4'h2, 32'h0000_0200, 8'd3, 3'd2, BURST_INCR, 0);
        chk32("I2 mem[0x200]", rbuf[0], 32'h2000_CCCC);
        chk32("I2 mem[0x204]", rbuf[1], 32'h2000_DDDD);
        chk32("I2 mem[0x208]", rbuf[2], 32'h2000_AAAA);
        chk32("I2 mem[0x20C]", rbuf[3], 32'h2000_BBBB);

        //=====================================================================
        $display("\n-- I3 : FIXED burst, 4 beats, all to 0x300");
        wbuf[0] = 32'h3000_0001; sbuf[0] = 4'b1111;
        wbuf[1] = 32'h3000_0002; sbuf[1] = 4'b1111;
        wbuf[2] = 32'h3000_0003; sbuf[2] = 4'b1111;
        wbuf[3] = 32'h3000_0004; sbuf[3] = 4'b1111;
        host_write(4'h3, 32'h0000_0300, 8'd3, 3'd2, BURST_FIXED, 0);
        chk2("I3 BRESP", cmd_resp, RESP_OKAY);
        host_read(4'h3, 32'h0000_0300, 8'd1, 3'd2, BURST_INCR, 0);
        chk32("I3 last beat wins", rbuf[0], 32'h3000_0004);
        chk32("I3 next word untouched", rbuf[1], 32'h0000_0000);

        //=====================================================================
        $display("\n-- I4 : WSTRB byte merging across a 4-beat burst");
        fill_pattern(8'd3, 32'hFFFF_FFFF);
        for (b = 0; b <= 3; b = b + 1) wbuf[b] = 32'hFFFF_FFFF;
        host_write(4'h4, 32'h0000_0400, 8'd3, 3'd2, BURST_INCR, 0);

        wbuf[0] = 32'h1111_1111; sbuf[0] = 4'b0001;
        wbuf[1] = 32'h2222_2222; sbuf[1] = 4'b0010;
        wbuf[2] = 32'h3333_3333; sbuf[2] = 4'b0100;
        wbuf[3] = 32'h4444_4444; sbuf[3] = 4'b1000;
        host_write(4'h4, 32'h0000_0400, 8'd3, 3'd2, BURST_INCR, 0);
        chk2("I4 BRESP", cmd_resp, RESP_OKAY);

        host_read(4'h4, 32'h0000_0400, 8'd3, 3'd2, BURST_INCR, 0);
        chk32("I4 mem[0x400]", rbuf[0], 32'hFFFF_FF11);
        chk32("I4 mem[0x404]", rbuf[1], 32'hFFFF_22FF);
        chk32("I4 mem[0x408]", rbuf[2], 32'hFF33_FFFF);
        chk32("I4 mem[0x40C]", rbuf[3], 32'h44FF_FFFF);

        //=====================================================================
        $display("\n-- I5 : out-of-range address 0x2000 -> DECERR at the host");
        fill_pattern(8'd2, 32'hBAD0_0000);
        host_write(4'h5, 32'h0000_2000, 8'd2, 3'd2, BURST_INCR, 0);
        chk2("I5 write BRESP", cmd_resp, RESP_DECERR);
        host_read(4'h5, 32'h0000_2000, 8'd2, 3'd2, BURST_INCR, 0);
        chk2 ("I5 read RRESP", cmd_resp, RESP_DECERR);
        chk32("I5 read data zeroed", rbuf[0], 32'h0000_0000);
        chk32("I5 last_err clear", {31'd0, cmd_last_err}, 32'h0);

        //=====================================================================
        $display("\n-- I6 : host stalls the read 4 cycles before every beat");
        host_read(4'h6, 32'h0000_0100, 8'd7, 3'd2, BURST_INCR, 4);
        chk2("I6 RRESP", cmd_resp, RESP_OKAY);
        for (b = 0; b <= 7; b = b + 1)
            chk32("I6 beat", rbuf[b], 32'h1100_0000 + (b * 32'h0010_0001));

        //=====================================================================
        $display("\n-- I7 : asynchronous reset in the middle of a write burst");
        fill_pattern(8'd7, 32'h7700_0000);
        while (cmd_busy) step;
        cmd_id          = 4'h7;
        cmd_addr        = 32'h0000_0600;
        cmd_len         = 8'd7;
        cmd_size        = 3'd2;
        cmd_burst       = BURST_INCR;
        cmd_start_write = 1'b1;
        step;
        cmd_start_write = 1'b0;

        // Push two beats, then yank the reset mid-burst.
        for (b = 0; b <= 1; b = b + 1) begin
            hw_data  = wbuf[b];
            hw_strb  = sbuf[b];
            hw_valid = 1'b1;
            while (!hw_ready) step;
            step;
        end
        if (!cmd_busy) fail("manager should still be busy mid-burst");

        ARESETn  = 1'b0;
        hw_valid = 1'b0;
        step;
        if (cmd_busy)  fail("cmd_busy still high during reset");
        if (hr_valid)  fail("hr_valid still high during reset");
        repeat (3) step;
        ARESETn = 1'b1;
        step;
        step;
        chk32("I7 idle after reset", {31'd0, cmd_busy}, 32'h0);

        // The system must now work normally again.
        fill_pattern(8'd3, 32'h7A7A_0000);
        host_write(4'h7, 32'h0000_0700, 8'd3, 3'd2, BURST_INCR, 0);
        chk2("I7 BRESP after recovery", cmd_resp, RESP_OKAY);
        host_read(4'h7, 32'h0000_0700, 8'd3, 3'd2, BURST_INCR, 0);
        for (b = 0; b <= 3; b = b + 1)
            chk32("I7 beat after recovery", rbuf[b],
                  32'h7A7A_0000 + (b * 32'h0010_0001));
        // How much of the aborted burst actually landed is NOT something to
        // assert.  The memory array itself is not reset, but the beats may
        // still have been sitting inside the channel pipeline registers when
        // reset hit, in which case they were discarded.  With PIPE_STAGE = 1
        // both beats are typically lost; with PIPE_STAGE = 0 they typically
        // land.  Either is correct: a burst killed by reset has no defined
        // outcome.  Report it rather than check it.
        host_read(4'h7, 32'h0000_0600, 8'd1, 3'd2, BURST_INCR, 0);
        $display("  aborted burst left mem[0x600] = 0x%08h, mem[0x604] = 0x%08h",
                 rbuf[0], rbuf[1]);
        $display("  (not asserted: beats still inside the channel pipeline when");
        $display("   reset hit are discarded, which is correct)");

        //=====================================================================
        $display("\n-- I8 : 32-beat write and read, sustained throughput");
        fill_pattern(8'd31, 32'h8800_0000);
        host_write(4'h8, 32'h0000_0800, 8'd31, 3'd2, BURST_INCR, 0);
        wr_cycles_32 = cycles_used;
        chk2("I8 BRESP", cmd_resp, RESP_OKAY);

        host_read(4'h8, 32'h0000_0800, 8'd31, 3'd2, BURST_INCR, 0);
        rd_cycles_32 = cycles_used;
        chk2("I8 RRESP", cmd_resp, RESP_OKAY);
        for (b = 0; b <= 31; b = b + 1)
            chk32("I8 beat", rbuf[b], 32'h8800_0000 + (b * 32'h0010_0001));

        $display("\n  32-beat write : %0d cycles  (%0d cycles of fixed overhead)",
                 wr_cycles_32, wr_cycles_32 - 32);
        $display("  32-beat read  : %0d cycles  (%0d cycles of fixed overhead)",
                 rd_cycles_32, rd_cycles_32 - 32);
        $display("  32 beats cannot take fewer than 32 cycles, so the overhead");
        $display("  above is the whole cost of the pipeline; it does not grow");
        $display("  with burst length.");
        if (wr_cycles_32 > 32 + 20) fail("write throughput worse than 1 beat/clock");
        if (rd_cycles_32 > 32 + 20) fail("read throughput worse than 1 beat/clock");

        //=====================================================================
        repeat (5) step;
        $display("\n==== Level 3 result : %0d checks, %0d failure(s) ====",
                 checks, errors);
        if (errors == 0) $display("TEST PASSED\n");
        else             $display("TEST FAILED\n");
        $finish;
    end

    initial begin
        #400000;
        $display("\n[FAIL] tb_axi4_top timed out -- possible deadlock");
        $display("TEST FAILED\n");
        $finish;
    end

endmodule
