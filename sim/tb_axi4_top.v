//=============================================================================
// tb_axi4_top.v  --  the whole system: master, D flip-flop stages, slave
//
// There is nothing to drive.  The master starts the transactions itself, so
// the testbench only supplies the clock and the reset, then watches.
//
// What it checks
//   1  the master finishes (done) in a sensible time
//   2  the master's own comparison says pass
//   3  the four words really are in the slave's memory at 0x10..0x1C
//   4  every B and R response is OKAY and carries the right ID
//   5  the protocol rule: once VALID is high, VALID and the payload stay put
//      until READY (checked on AW, W and AR, at the master)
//   6  reset in the middle of the sequence, then it runs again and passes
//=============================================================================

`timescale 1ns / 1ps

module tb_axi4_top;

    localparam CLK_PERIOD = 10;

    reg  clk    = 1'b0;
    reg  resetn = 1'b0;
    wire done, pass;

    always #(CLK_PERIOD/2) clk = ~clk;

    axi4_top uut (.clk(clk), .resetn(resetn), .done(done), .pass(pass));

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
    // Always-on monitors on the master's own ports
    //-------------------------------------------------------------------------
    // Responses must be OKAY and carry the master's ID (1).
    always @(posedge clk) begin
        if (resetn) begin
            if (uut.m_bvalid && uut.m_bready) begin
                if (uut.m_bresp !== 2'b00) fail("BRESP is not OKAY");
                if (uut.m_bid   !== 4'd1)  fail("BID is not the ID that was sent");
            end
            if (uut.m_rvalid && uut.m_rready) begin
                if (uut.m_rresp !== 2'b00) fail("RRESP is not OKAY");
                if (uut.m_rid   !== 4'd1)  fail("RID is not the ID that was sent");
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
            if (aw_pend && (!uut.m_awvalid ||
                            {uut.m_awid, uut.m_awaddr, uut.m_awlen} !== aw_hold))
                fail("AW changed or dropped before AWREADY");
            if (w_pend && (!uut.m_wvalid ||
                           {uut.m_wdata, uut.m_wstrb, uut.m_wlast} !== w_hold))
                fail("W changed or dropped before WREADY");
            if (ar_pend && (!uut.m_arvalid ||
                            {uut.m_arid, uut.m_araddr, uut.m_arlen} !== ar_hold))
                fail("AR changed or dropped before ARREADY");

            aw_pend <= uut.m_awvalid && !uut.m_awready;
            w_pend  <= uut.m_wvalid  && !uut.m_wready;
            ar_pend <= uut.m_arvalid && !uut.m_arready;
            aw_hold <= {uut.m_awid, uut.m_awaddr, uut.m_awlen};
            w_hold  <= {uut.m_wdata, uut.m_wstrb, uut.m_wlast};
            ar_hold <= {uut.m_arid, uut.m_araddr, uut.m_arlen};
        end
    end

    //-------------------------------------------------------------------------
    task wait_done(input integer limit);
        begin
            cycles = 0;
            while (!done && cycles < limit) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
        end
    endtask

    task check_memory;
        begin
            check32("memory[0x10]", uut.u_slave.mem[4], 32'hA5A5_0001);
            check32("memory[0x14]", uut.u_slave.mem[5], 32'h5A5A_0002);
            check32("memory[0x18]", uut.u_slave.mem[6], 32'hDEAD_BEEF);
            check32("memory[0x1C]", uut.u_slave.mem[7], 32'h0BAD_F00D);
        end
    endtask

    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_axi4_top.vcd");
        $dumpvars(0, tb_axi4_top);

        $display("\n==== tb_axi4_top : master + D flip-flop stages + slave ====");

        repeat (5) @(posedge clk);
        #1 resetn = 1'b1;

        //---------------------------------------------------------------------
        $display("\n-- the master writes four words, reads them back, compares");
        wait_done(2000);
        check("master finished (done)", done === 1'b1);
        check("data read back matches (pass)", pass === 1'b1);
        $display("  the whole sequence took %0d clock cycles", cycles);
        check_memory;

        //---------------------------------------------------------------------
        $display("\n-- reset in the middle of the sequence, then it runs again");
        @(posedge clk);
        #1 resetn = 1'b0;
        repeat (3) @(posedge clk);
        #1 resetn = 1'b1;
        repeat (12) @(posedge clk);          // part-way through the first write
        check("not done yet, mid-sequence", done === 1'b0);
        #1 resetn = 1'b0;                    // reset again, mid-sequence
        uut.u_slave.mem[4] = 32'd0;          // clear the four words, so the
        uut.u_slave.mem[5] = 32'd0;          // second run has to write them again
        uut.u_slave.mem[6] = 32'd0;
        uut.u_slave.mem[7] = 32'd0;
        repeat (3) @(posedge clk);
        #1 resetn = 1'b1;
        wait_done(2000);
        check("finished again after the reset", done === 1'b1);
        check("passes again after the reset", pass === 1'b1);
        check_memory;

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
