//=============================================================================
// tb_axi4_top.v  --  the whole system:  in DFF -> master -> slave -> out DFF
//
// The testbench plays the person at the switches:
//   1. load an address and four words into the input flip-flops
//   2. raise start
//   3. wait for done, then look at the output flip-flops and the slave memory
//
// What it checks
//   1  the master does nothing until start is raised
//   2  the input flip-flops hold what was loaded
//   3  the master finishes (done), pass is 1, the output flip-flops hold the
//      four words that were written
//   4  the four words really are in the slave's memory at the address loaded
//   5  every B and R response is OKAY and carries the right ID
//   6  the protocol rule: once VALID is high, VALID and the payload stay put
//      until READY (checked on AW, W and AR)
//   7  a second run with a different address and different words works
//      (the data really comes from the flip-flops, not from inside the master)
//   8  pass drops to 0 if the loaded words stop matching what was read back
//   9  reset in the middle of the sequence clears the flip-flops, and after a
//      reload the sequence runs again and passes
//=============================================================================

`timescale 1ns / 1ps

module tb_axi4_top;

    localparam CLK_PERIOD = 10;

    reg         clk       = 1'b0;
    reg         resetn    = 1'b0;
    reg         load      = 1'b0;
    reg  [2:0]  load_sel  = 3'd0;
    reg  [31:0] load_data = 32'd0;
    reg         start     = 1'b0;
    wire        done, pass;
    wire [31:0] rd0, rd1, rd2, rd3;

    always #(CLK_PERIOD/2) clk = ~clk;

    axi4_top uut (
        .clk(clk), .resetn(resetn),
        .load(load), .load_sel(load_sel), .load_data(load_data),
        .start(start), .done(done), .pass(pass),
        .rd0(rd0), .rd1(rd1), .rd2(rd2), .rd3(rd3)
    );

    integer errors = 0;
    integer checks = 0;
    integer cycles;

    task fail(input [8*56-1:0] msg);
        begin
            errors = errors + 1;
            $display("  [FAIL] %0s  (t=%0t)", msg, $time);
        end
    endtask

    task check(input [8*40-1:0] name, input cond);
        begin
            checks = checks + 1;
            if (!cond) begin
                errors = errors + 1;
                $display("  [FAIL] %0s", name);
            end else $display("  [ ok ] %0s", name);
        end
    endtask

    task check32(input [8*40-1:0] name, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  [FAIL] %0s : got 0x%08h expected 0x%08h", name, got, exp);
            end else $display("  [ ok ] %0s = 0x%08h", name, got);
        end
    endtask

    //-------------------------------------------------------------------------
    // Always-on monitors on the wires between master and slave
    //-------------------------------------------------------------------------
    // Responses must be OKAY and carry the master's ID (1).
    always @(posedge clk) begin
        if (resetn) begin
            if (uut.bvalid && uut.bready) begin
                if (uut.bresp !== 2'b00) fail("BRESP is not OKAY");
                if (uut.bid   !== 4'd1)  fail("BID is not the ID that was sent");
            end
            if (uut.rvalid && uut.rready) begin
                if (uut.rresp !== 2'b00) fail("RRESP is not OKAY");
                if (uut.rid   !== 4'd1)  fail("RID is not the ID that was sent");
            end
        end
    end

    // Once VALID is high, VALID and the payload must not change until READY.
    reg        aw_pend = 1'b0, w_pend = 1'b0, ar_pend = 1'b0;
    reg [43:0] aw_hold = 44'd0;
    reg [36:0] w_hold  = 37'd0;
    reg [43:0] ar_hold = 44'd0;
    always @(posedge clk) begin
        if (!resetn) begin
            aw_pend <= 1'b0; w_pend <= 1'b0; ar_pend <= 1'b0;
        end else begin
            if (aw_pend && (!uut.awvalid ||
                            {uut.awid, uut.awaddr, uut.awlen} !== aw_hold))
                fail("AW changed or dropped before AWREADY");
            if (w_pend && (!uut.wvalid ||
                           {uut.wdata, uut.wstrb, uut.wlast} !== w_hold))
                fail("W changed or dropped before WREADY");
            if (ar_pend && (!uut.arvalid ||
                            {uut.arid, uut.araddr, uut.arlen} !== ar_hold))
                fail("AR changed or dropped before ARREADY");

            aw_pend <= uut.awvalid && !uut.awready;
            w_pend  <= uut.wvalid  && !uut.wready;
            ar_pend <= uut.arvalid && !uut.arready;
            aw_hold <= {uut.awid, uut.awaddr, uut.awlen};
            w_hold  <= {uut.wdata, uut.wstrb, uut.wlast};
            ar_hold <= {uut.arid, uut.araddr, uut.arlen};
        end
    end

    //-------------------------------------------------------------------------
    // Helpers
    //-------------------------------------------------------------------------
    // store one value into one input flip-flop (one clock)
    task load_reg(input [2:0] sel, input [31:0] value);
        begin
            @(posedge clk);
            #1 load = 1'b1; load_sel = sel; load_data = value;
            @(posedge clk);
            #1 load = 1'b0;
        end
    endtask

    task load_all(input [31:0] a, input [31:0] w0, input [31:0] w1,
                  input [31:0] w2, input [31:0] w3);
        begin
            load_reg(3'd0, a);
            load_reg(3'd1, w0);
            load_reg(3'd2, w1);
            load_reg(3'd3, w2);
            load_reg(3'd4, w3);
        end
    endtask

    // raise start and wait for done (start stays high)
    task run_start(input integer limit);
        begin
            @(posedge clk);
            #1 start = 1'b1;
            cycles = 0;
            while (!done && cycles < limit) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task release_start;
        begin
            @(posedge clk);
            #1 start = 1'b0;
            repeat (2) @(posedge clk);
        end
    endtask

    task check_readback(input [31:0] w0, input [31:0] w1,
                        input [31:0] w2, input [31:0] w3);
        begin
            check32("output DFF rd0", rd0, w0);
            check32("output DFF rd1", rd1, w1);
            check32("output DFF rd2", rd2, w2);
            check32("output DFF rd3", rd3, w3);
        end
    endtask

    //-------------------------------------------------------------------------
    integer i;
    initial begin
        $dumpfile("tb_axi4_top.vcd");
        $dumpvars(0, tb_axi4_top);

        $display("\n==== tb_axi4_top : in DFF -> master -> slave -> out DFF ====");

        repeat (5) @(posedge clk);
        #1 resetn = 1'b1;

        //---------------------------------------------------------------------
        $display("\n-- nothing happens until start is raised");
        repeat (10) @(posedge clk);
        check("idle: done is 0",          done === 1'b0);
        check("idle: no write address",   uut.awvalid === 1'b0);
        check("idle: no read address",    uut.arvalid === 1'b0);

        //---------------------------------------------------------------------
        $display("\n-- load the input flip-flops");
        load_all(32'h0000_0010, 32'hA5A5_0001, 32'h5A5A_0002,
                 32'hDEAD_BEEF, 32'h0BAD_F00D);
        check32("input DFF addr",  uut.addr, 32'h0000_0010);
        check32("input DFF data0", uut.d0,   32'hA5A5_0001);
        check32("input DFF data3", uut.d3,   32'h0BAD_F00D);

        //---------------------------------------------------------------------
        $display("\n-- start: write four words, read them back");
        run_start(2000);
        check("master finished (done)", done === 1'b1);
        check("data read back matches (pass)", pass === 1'b1);
        $display("  the whole sequence took %0d clock cycles", cycles);
        check_readback(32'hA5A5_0001, 32'h5A5A_0002, 32'hDEAD_BEEF, 32'h0BAD_F00D);
        check32("memory[0x10]", uut.u_slave.mem[4], 32'hA5A5_0001);
        check32("memory[0x14]", uut.u_slave.mem[5], 32'h5A5A_0002);
        check32("memory[0x18]", uut.u_slave.mem[6], 32'hDEAD_BEEF);
        check32("memory[0x1C]", uut.u_slave.mem[7], 32'h0BAD_F00D);

        // pass must drop if the loaded words no longer match what came back
        load_reg(3'd2, 32'h1234_5678);
        @(posedge clk); #1;
        check("pass drops when a loaded word differs", pass === 1'b0);
        load_reg(3'd2, 32'hDEAD_BEEF);

        release_start;
        check("done clears when start is released", done === 1'b0);

        //---------------------------------------------------------------------
        $display("\n-- second run: a different address and different words");
        load_all(32'h0000_0040, 32'h1111_1111, 32'h2222_2222,
                 32'h3333_3333, 32'h4444_4444);
        run_start(2000);
        check("finished again (done)", done === 1'b1);
        check("passes again (pass)",   pass === 1'b1);
        check_readback(32'h1111_1111, 32'h2222_2222, 32'h3333_3333, 32'h4444_4444);
        check32("memory[0x40]", uut.u_slave.mem[16], 32'h1111_1111);
        check32("memory[0x44]", uut.u_slave.mem[17], 32'h2222_2222);
        check32("memory[0x48]", uut.u_slave.mem[18], 32'h3333_3333);
        check32("memory[0x4C]", uut.u_slave.mem[19], 32'h4444_4444);
        check32("memory[0x10] untouched", uut.u_slave.mem[4], 32'hA5A5_0001);
        release_start;

        //---------------------------------------------------------------------
        $display("\n-- reset in the middle of a sequence");
        load_all(32'h0000_0080, 32'hCAFE_0001, 32'hCAFE_0002,
                 32'hCAFE_0003, 32'hCAFE_0004);
        @(posedge clk);
        #1 start = 1'b1;
        repeat (6) @(posedge clk);            // part-way through the write
        check("not done yet, mid-sequence", done === 1'b0);
        #1 start = 1'b0;
        resetn = 1'b0;
        repeat (3) @(posedge clk);
        #1 resetn = 1'b1;
        repeat (3) @(posedge clk);
        check32("reset cleared input DFF addr",  uut.addr, 32'd0);
        check32("reset cleared input DFF data0", uut.d0,   32'd0);
        check32("reset cleared output DFF rd0",  rd0,      32'd0);
        check("reset: done is 0",        done === 1'b0);
        check("reset: master is idle",   uut.awvalid === 1'b0 && uut.wvalid === 1'b0);

        $display("\n-- reload and run again after the reset");
        load_all(32'h0000_0020, 32'h0000_000A, 32'h0000_000B,
                 32'h0000_000C, 32'h0000_000D);
        run_start(2000);
        check("finished after the reset (done)", done === 1'b1);
        check("passes after the reset (pass)",   pass === 1'b1);
        check_readback(32'h0000_000A, 32'h0000_000B, 32'h0000_000C, 32'h0000_000D);
        check32("memory[0x20]", uut.u_slave.mem[8],  32'h0000_000A);
        check32("memory[0x2C]", uut.u_slave.mem[11], 32'h0000_000D);
        release_start;

        //---------------------------------------------------------------------
        repeat (5) @(posedge clk);
        $display("\n==== result : %0d checks, %0d failure(s) ====", checks, errors);
        if (errors == 0) $display("TEST PASSED\n");
        else             $display("TEST FAILED\n");
        $finish;
    end

    initial begin
        #500000;
        $display("\n[FAIL] timed out -- possible deadlock");
        $display("TEST FAILED\n");
        $finish;
    end

endmodule
