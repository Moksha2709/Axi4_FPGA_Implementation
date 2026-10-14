//=============================================================================
// tb_axi4_master.v  --  Level 2 : AXI4 manager unit testbench
//
// The manager is driven from its host ports and answered by a programmable
// mock subordinate whose per-channel READY latency and response latency can be
// dialled independently.  That is what makes the payload-stability rule
// testable: a cooperative subordinate accepts too quickly to prove anything.
//
// Three always-on protocol monitors watch AW, W and AR for the whole run and
// flag any violation of ARM IHI 0022 section A2.3:
//   * VALID must not be withdrawn before the handshake completes.
//   * The payload (including WLAST) must not change while VALID is high and
//     READY is low.
//
// Tests
//   M1 AWREADY stalled 4 cycles, 5-beat write, data/order/WLAST checked
//   M2 WREADY stalled 3 cycles per beat plus host bubbles
//   M3 ARREADY stalled 5 cycles, 5-beat read streamed to the host
//   M4 BVALID and RVALID delayed 6 cycles, cmd_busy must hold
//   M5 cmd_start_write hammered while a read burst is in flight
//   M6 a SLVERR read beat is reported through cmd_resp
//   M7 a subordinate whose RLAST comes early is caught by cmd_last_err
//   M8 back-to-back 16-beat write with no stalls, one beat per clock
//=============================================================================

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Programmable mock AXI4 subordinate.
//
// All write-side logic lives in one always block and all read-side logic in
// another, so no signal has two drivers.  One burst per direction at a time,
// which matches the manager under test.
//-----------------------------------------------------------------------------
module mock_axi4_slave #(
    parameter ID_WIDTH   = 4,
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  wire                      ACLK,
    input  wire                      ARESETn,

    // ---- Behaviour controls ------------------------------------------------
    input  wire [7:0]                aw_ready_delay,
    input  wire [7:0]                w_ready_delay,
    input  wire [7:0]                ar_ready_delay,
    input  wire [7:0]                b_valid_delay,
    input  wire [7:0]                r_valid_delay,
    input  wire [1:0]                b_resp_val,
    input  wire [1:0]                r_resp_val,
    input  wire                      r_len_force_en,  // lie about the burst
    input  wire [7:0]                r_len_force,     // length, to test RLAST

    // ---- AXI4 subordinate interface ---------------------------------------
    input  wire [ID_WIDTH-1:0]       AWID,
    input  wire [ADDR_WIDTH-1:0]     AWADDR,
    input  wire [7:0]                AWLEN,
    input  wire [2:0]                AWSIZE,
    input  wire [1:0]                AWBURST,
    input  wire                      AWLOCK,
    input  wire [3:0]                AWCACHE,
    input  wire [2:0]                AWPROT,
    input  wire [3:0]                AWQOS,
    input  wire                      AWVALID,
    output reg                       AWREADY,

    input  wire [DATA_WIDTH-1:0]     WDATA,
    input  wire [(DATA_WIDTH/8)-1:0] WSTRB,
    input  wire                      WLAST,
    input  wire                      WVALID,
    output reg                       WREADY,

    output reg  [ID_WIDTH-1:0]       BID,
    output reg  [1:0]                BRESP,
    output reg                       BVALID,
    input  wire                      BREADY,

    input  wire [ID_WIDTH-1:0]       ARID,
    input  wire [ADDR_WIDTH-1:0]     ARADDR,
    input  wire [7:0]                ARLEN,
    input  wire [2:0]                ARSIZE,
    input  wire [1:0]                ARBURST,
    input  wire                      ARLOCK,
    input  wire [3:0]                ARCACHE,
    input  wire [2:0]                ARPROT,
    input  wire [3:0]                ARQOS,
    input  wire                      ARVALID,
    output reg                       ARREADY,

    output reg  [ID_WIDTH-1:0]       RID,
    output reg  [DATA_WIDTH-1:0]     RDATA,
    output reg  [1:0]                RRESP,
    output reg                       RLAST,
    output reg                       RVALID,
    input  wire                      RREADY
);

    // Observation storage, read hierarchically by the testbench.
    reg [DATA_WIDTH-1:0]     mw_data [0:255];
    reg [(DATA_WIDTH/8)-1:0] mw_strb [0:255];
    reg [7:0]                w_cnt;        // beats received so far
    reg [7:0]                w_last_idx;   // beat index that carried WLAST
    reg                      w_last_seen;

    reg [ID_WIDTH-1:0]   awid_l;
    reg [ADDR_WIDTH-1:0] awaddr_l;
    reg [7:0]            awlen_l;
    reg                  aw_seen;
    reg [7:0]            aw_dly, w_dly, b_dly;

    //-------------------------------------------------------------------------
    // Write side
    //-------------------------------------------------------------------------
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            AWREADY     <= 1'b0;
            WREADY      <= 1'b0;
            BVALID      <= 1'b0;
            BID         <= {ID_WIDTH{1'b0}};
            BRESP       <= 2'b00;
            aw_dly      <= 8'd0;
            w_dly       <= 8'd0;
            b_dly       <= 8'd0;
            w_cnt       <= 8'd0;
            w_last_idx  <= 8'd0;
            w_last_seen <= 1'b0;
            aw_seen     <= 1'b0;
            awid_l      <= {ID_WIDTH{1'b0}};
            awaddr_l    <= {ADDR_WIDTH{1'b0}};
            awlen_l     <= 8'd0;
        end else begin
            // ---- AW channel ----------------------------------------------
            if (AWVALID && AWREADY) begin
                AWREADY     <= 1'b0;
                aw_dly      <= 8'd0;
                awid_l      <= AWID;
                awaddr_l    <= AWADDR;
                awlen_l     <= AWLEN;
                aw_seen     <= 1'b1;
                w_cnt       <= 8'd0;
                w_last_seen <= 1'b0;
            end else if (AWVALID && !AWREADY && !aw_seen) begin
                if (aw_dly >= aw_ready_delay) AWREADY <= 1'b1;
                else                          aw_dly  <= aw_dly + 8'd1;
            end

            // ---- W channel : only after the address, like a real slave ----
            if (WVALID && WREADY) begin
                mw_data[w_cnt] <= WDATA;
                mw_strb[w_cnt] <= WSTRB;
                w_cnt          <= w_cnt + 8'd1;
                if (WLAST) begin
                    w_last_seen <= 1'b1;
                    w_last_idx  <= w_cnt;
                    WREADY      <= 1'b0;
                end else if (w_ready_delay != 8'd0) begin
                    WREADY <= 1'b0;       // re-insert the stall for next beat
                    w_dly  <= 8'd0;
                end
                // delay == 0 keeps WREADY high, so beats go back to back
            end else if (WVALID && !WREADY && aw_seen && !w_last_seen) begin
                if (w_dly >= w_ready_delay) WREADY <= 1'b1;
                else                        w_dly  <= w_dly + 8'd1;
            end

            // ---- B channel -----------------------------------------------
            if (BVALID && BREADY) begin
                BVALID      <= 1'b0;
                b_dly       <= 8'd0;
                aw_seen     <= 1'b0;
                w_last_seen <= 1'b0;
            end else if (!BVALID && aw_seen && w_last_seen) begin
                if (b_dly >= b_valid_delay) begin
                    BVALID <= 1'b1;
                    BID    <= awid_l;
                    BRESP  <= b_resp_val;
                end else begin
                    b_dly <= b_dly + 8'd1;
                end
            end
        end
    end

    //-------------------------------------------------------------------------
    // Read side.  Beat n returns ARADDR + (n << 8), so the testbench can
    // predict every beat from the address alone.
    //-------------------------------------------------------------------------
    reg [ID_WIDTH-1:0]   arid_l;
    reg [ADDR_WIDTH-1:0] araddr_l;
    reg [7:0]            arlen_l;
    reg                  ar_seen;
    reg [7:0]            ar_dly, r_dly, r_cnt;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            ARREADY  <= 1'b0;
            RVALID   <= 1'b0;
            RLAST    <= 1'b0;
            RID      <= {ID_WIDTH{1'b0}};
            RDATA    <= {DATA_WIDTH{1'b0}};
            RRESP    <= 2'b00;
            ar_dly   <= 8'd0;
            r_dly    <= 8'd0;
            r_cnt    <= 8'd0;
            ar_seen  <= 1'b0;
            arid_l   <= {ID_WIDTH{1'b0}};
            araddr_l <= {ADDR_WIDTH{1'b0}};
            arlen_l  <= 8'd0;
        end else begin
            // ---- AR channel ----------------------------------------------
            if (ARVALID && ARREADY) begin
                ARREADY  <= 1'b0;
                ar_dly   <= 8'd0;
                arid_l   <= ARID;
                araddr_l <= ARADDR;
                arlen_l  <= r_len_force_en ? r_len_force : ARLEN;
                ar_seen  <= 1'b1;
                r_cnt    <= 8'd0;
                r_dly    <= 8'd0;
            end else if (ARVALID && !ARREADY && !ar_seen) begin
                if (ar_dly >= ar_ready_delay) ARREADY <= 1'b1;
                else                          ar_dly  <= ar_dly + 8'd1;
            end

            // ---- R channel -----------------------------------------------
            if (RVALID && RREADY) begin
                if (RLAST) begin
                    RVALID  <= 1'b0;
                    RLAST   <= 1'b0;
                    ar_seen <= 1'b0;
                    r_dly   <= 8'd0;
                end else begin
                    RDATA <= araddr_l + {16'd0, (r_cnt + 8'd1), 8'd0};
                    RLAST <= ((r_cnt + 8'd1) == arlen_l);
                    RID   <= arid_l;
                    RRESP <= r_resp_val;
                    r_cnt <= r_cnt + 8'd1;
                end
            end else if (!RVALID && ar_seen) begin
                if (r_dly >= r_valid_delay) begin
                    RDATA  <= araddr_l + {16'd0, r_cnt, 8'd0};
                    RLAST  <= (r_cnt == arlen_l);
                    RID    <= arid_l;
                    RRESP  <= r_resp_val;
                    RVALID <= 1'b1;
                end else begin
                    r_dly <= r_dly + 8'd1;
                end
            end
        end
    end

    wire _unused = AWLOCK | ARLOCK | (|AWCACHE) | (|ARCACHE) |
                   (|AWPROT) | (|ARPROT) | (|AWQOS) | (|ARQOS) |
                   (|AWSIZE) | (|ARSIZE) | (|AWBURST) | (|ARBURST) |
                   (|awaddr_l) | (|awlen_l);

endmodule


//-----------------------------------------------------------------------------
module tb_axi4_master;

    localparam CLK_PERIOD = 10;
    localparam ID_WIDTH   = 4;
    localparam ADDR_WIDTH = 32;
    localparam DATA_WIDTH = 32;

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;
    localparam [1:0] BURST_INCR  = 2'b01;

    reg ACLK    = 1'b0;
    reg ARESETn = 1'b0;

    // ---- Host command port -------------------------------------------------
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

    // ---- Host data streams -------------------------------------------------
    reg  [DATA_WIDTH-1:0]     hw_data  = 0;
    reg  [(DATA_WIDTH/8)-1:0] hw_strb  = 0;
    reg                       hw_valid = 0;
    wire                      hw_ready;

    wire [DATA_WIDTH-1:0] hr_data;
    wire [1:0]            hr_resp;
    wire                  hr_last;
    wire                  hr_valid;
    reg                   hr_ready = 0;

    // ---- Mock controls -----------------------------------------------------
    reg [7:0] aw_ready_delay = 0;
    reg [7:0] w_ready_delay  = 0;
    reg [7:0] ar_ready_delay = 0;
    reg [7:0] b_valid_delay  = 0;
    reg [7:0] r_valid_delay  = 0;
    reg [1:0] b_resp_val     = RESP_OKAY;
    reg [1:0] r_resp_val     = RESP_OKAY;
    reg       r_len_force_en = 0;
    reg [7:0] r_len_force    = 0;

    // ---- AXI nets ----------------------------------------------------------
    wire [ID_WIDTH-1:0]   AWID;
    wire [ADDR_WIDTH-1:0] AWADDR;
    wire [7:0]            AWLEN;
    wire [2:0]            AWSIZE;
    wire [1:0]            AWBURST;
    wire                  AWLOCK;
    wire [3:0]            AWCACHE;
    wire [2:0]            AWPROT;
    wire [3:0]            AWQOS;
    wire                  AWVALID, AWREADY;

    wire [DATA_WIDTH-1:0]     WDATA;
    wire [(DATA_WIDTH/8)-1:0] WSTRB;
    wire                      WLAST, WVALID, WREADY;

    wire [ID_WIDTH-1:0] BID;
    wire [1:0]          BRESP;
    wire                BVALID, BREADY;

    wire [ID_WIDTH-1:0]   ARID;
    wire [ADDR_WIDTH-1:0] ARADDR;
    wire [7:0]            ARLEN;
    wire [2:0]            ARSIZE;
    wire [1:0]            ARBURST;
    wire                  ARLOCK;
    wire [3:0]            ARCACHE;
    wire [2:0]            ARPROT;
    wire [3:0]            ARQOS;
    wire                  ARVALID, ARREADY;

    wire [ID_WIDTH-1:0]   RID;
    wire [DATA_WIDTH-1:0] RDATA;
    wire [1:0]            RRESP;
    wire                  RLAST, RVALID, RREADY;

    integer errors = 0;
    integer checks = 0;

    reg [DATA_WIDTH-1:0]     wbuf [0:255];
    reg [(DATA_WIDTH/8)-1:0] sbuf [0:255];
    reg [DATA_WIDTH-1:0]     rbuf [0:255];

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    //-------------------------------------------------------------------------
    axi4_master #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) uut (
        .M_AXI_ACLK      (ACLK),
        .M_AXI_ARESETN   (ARESETn),

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
        .hr_ready        (hr_ready),

        .M_AXI_AWID      (AWID),
        .M_AXI_AWADDR    (AWADDR),
        .M_AXI_AWLEN     (AWLEN),
        .M_AXI_AWSIZE    (AWSIZE),
        .M_AXI_AWBURST   (AWBURST),
        .M_AXI_AWLOCK    (AWLOCK),
        .M_AXI_AWCACHE   (AWCACHE),
        .M_AXI_AWPROT    (AWPROT),
        .M_AXI_AWQOS     (AWQOS),
        .M_AXI_AWVALID   (AWVALID),
        .M_AXI_AWREADY   (AWREADY),

        .M_AXI_WDATA     (WDATA),
        .M_AXI_WSTRB     (WSTRB),
        .M_AXI_WLAST     (WLAST),
        .M_AXI_WVALID    (WVALID),
        .M_AXI_WREADY    (WREADY),

        .M_AXI_BID       (BID),
        .M_AXI_BRESP     (BRESP),
        .M_AXI_BVALID    (BVALID),
        .M_AXI_BREADY    (BREADY),

        .M_AXI_ARID      (ARID),
        .M_AXI_ARADDR    (ARADDR),
        .M_AXI_ARLEN     (ARLEN),
        .M_AXI_ARSIZE    (ARSIZE),
        .M_AXI_ARBURST   (ARBURST),
        .M_AXI_ARLOCK    (ARLOCK),
        .M_AXI_ARCACHE   (ARCACHE),
        .M_AXI_ARPROT    (ARPROT),
        .M_AXI_ARQOS     (ARQOS),
        .M_AXI_ARVALID   (ARVALID),
        .M_AXI_ARREADY   (ARREADY),

        .M_AXI_RID       (RID),
        .M_AXI_RDATA     (RDATA),
        .M_AXI_RRESP     (RRESP),
        .M_AXI_RLAST     (RLAST),
        .M_AXI_RVALID    (RVALID),
        .M_AXI_RREADY    (RREADY)
    );

    mock_axi4_slave #(
        .ID_WIDTH   (ID_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH)
    ) mock (
        .ACLK           (ACLK),
        .ARESETn        (ARESETn),
        .aw_ready_delay (aw_ready_delay),
        .w_ready_delay  (w_ready_delay),
        .ar_ready_delay (ar_ready_delay),
        .b_valid_delay  (b_valid_delay),
        .r_valid_delay  (r_valid_delay),
        .b_resp_val     (b_resp_val),
        .r_resp_val     (r_resp_val),
        .r_len_force_en (r_len_force_en),
        .r_len_force    (r_len_force),

        .AWID (AWID), .AWADDR (AWADDR), .AWLEN (AWLEN), .AWSIZE (AWSIZE),
        .AWBURST (AWBURST), .AWLOCK (AWLOCK), .AWCACHE (AWCACHE),
        .AWPROT (AWPROT), .AWQOS (AWQOS),
        .AWVALID (AWVALID), .AWREADY (AWREADY),

        .WDATA (WDATA), .WSTRB (WSTRB), .WLAST (WLAST),
        .WVALID (WVALID), .WREADY (WREADY),

        .BID (BID), .BRESP (BRESP), .BVALID (BVALID), .BREADY (BREADY),

        .ARID (ARID), .ARADDR (ARADDR), .ARLEN (ARLEN), .ARSIZE (ARSIZE),
        .ARBURST (ARBURST), .ARLOCK (ARLOCK), .ARCACHE (ARCACHE),
        .ARPROT (ARPROT), .ARQOS (ARQOS),
        .ARVALID (ARVALID), .ARREADY (ARREADY),

        .RID (RID), .RDATA (RDATA), .RRESP (RRESP), .RLAST (RLAST),
        .RVALID (RVALID), .RREADY (RREADY)
    );

    //-------------------------------------------------------------------------
    // Reporting
    //-------------------------------------------------------------------------
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
    // Always-on payload-stability monitors (IHI 0022 A2.3)
    //-------------------------------------------------------------------------
    localparam AX_W = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2;
    localparam W_W  = DATA_WIDTH + (DATA_WIDTH/8) + 1;

    reg            aw_pend = 1'b0;
    reg [AX_W-1:0] aw_hold = 0;
    always @(posedge ACLK) begin
        if (!ARESETn) aw_pend <= 1'b0;
        else begin
            if (aw_pend) begin
                if (!AWVALID)
                    fail("AWVALID withdrawn before AWREADY");
                else if ({AWID, AWADDR, AWLEN, AWSIZE, AWBURST} !== aw_hold)
                    fail("AW payload changed while stalled");
            end
            if (AWVALID && AWREADY) aw_pend <= 1'b0;
            else if (AWVALID) begin
                aw_pend <= 1'b1;
                aw_hold <= {AWID, AWADDR, AWLEN, AWSIZE, AWBURST};
            end
        end
    end

    reg           w_pend = 1'b0;
    reg [W_W-1:0] w_hold = 0;
    always @(posedge ACLK) begin
        if (!ARESETn) w_pend <= 1'b0;
        else begin
            if (w_pend) begin
                if (!WVALID)
                    fail("WVALID withdrawn before WREADY");
                else if ({WDATA, WSTRB, WLAST} !== w_hold)
                    fail("W payload changed while stalled");
            end
            if (WVALID && WREADY) w_pend <= 1'b0;
            else if (WVALID) begin
                w_pend <= 1'b1;
                w_hold <= {WDATA, WSTRB, WLAST};
            end
        end
    end

    reg            ar_pend = 1'b0;
    reg [AX_W-1:0] ar_hold = 0;
    always @(posedge ACLK) begin
        if (!ARESETn) ar_pend <= 1'b0;
        else begin
            if (ar_pend) begin
                if (!ARVALID)
                    fail("ARVALID withdrawn before ARREADY");
                else if ({ARID, ARADDR, ARLEN, ARSIZE, ARBURST} !== ar_hold)
                    fail("AR payload changed while stalled");
            end
            if (ARVALID && ARREADY) ar_pend <= 1'b0;
            else if (ARVALID) begin
                ar_pend <= 1'b1;
                ar_hold <= {ARID, ARADDR, ARLEN, ARSIZE, ARBURST};
            end
        end
    end

    //-------------------------------------------------------------------------
    // Host drivers
    //-------------------------------------------------------------------------
    task step;
        begin
            @(posedge ACLK);
            #1;
        end
    endtask

    integer busy_cycles;

    // Issues a write burst and streams len+1 beats from wbuf/sbuf.
    // `gap` idle cycles are inserted between host beats.
    task host_write(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                    input [7:0] len, input [2:0] size, input [1:0] burst,
                    input integer gap);
        integer b, i;
        begin
            while (cmd_busy) step;
            cmd_id          = id;
            cmd_addr        = addr;
            cmd_len         = len;
            cmd_size        = size;
            cmd_burst       = burst;
            cmd_start_write = 1'b1;
            step;
            cmd_start_write = 1'b0;

            busy_cycles = 0;
            for (b = 0; b <= len; b = b + 1) begin
                hw_data  = wbuf[b];
                hw_strb  = sbuf[b];
                hw_valid = 1'b1;
                while (!hw_ready) begin
                    busy_cycles = busy_cycles + 1;
                    step;
                end
                step;
                busy_cycles = busy_cycles + 1;
                if (gap > 0) begin
                    hw_valid = 1'b0;
                    for (i = 0; i < gap; i = i + 1) step;
                end
            end
            hw_valid = 1'b0;

            while (!cmd_done) begin
                if (!cmd_busy) fail("cmd_busy low before cmd_done");
                busy_cycles = busy_cycles + 1;
                step;
            end
        end
    endtask

    // Issues a read burst and collects exactly len+1 beats into rbuf.
    task host_read(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                   input [7:0] len, input [2:0] size, input [1:0] burst,
                   input integer stall);
        integer b, i;
        begin
            while (cmd_busy) step;
            cmd_id         = id;
            cmd_addr       = addr;
            cmd_len        = len;
            cmd_size       = size;
            cmd_burst      = burst;
            cmd_start_read = 1'b1;
            step;
            cmd_start_read = 1'b0;

            busy_cycles = 0;
            hr_ready    = (stall == 0);
            for (b = 0; b <= len; b = b + 1) begin
                if (stall > 0) begin
                    hr_ready = 1'b0;
                    while (!hr_valid) begin busy_cycles = busy_cycles + 1; step; end
                    for (i = 0; i < stall; i = i + 1) begin
                        busy_cycles = busy_cycles + 1;
                        step;
                    end
                    hr_ready = 1'b1;
                end else begin
                    while (!hr_valid) begin busy_cycles = busy_cycles + 1; step; end
                end

                rbuf[b] = hr_data;
                if (hr_last && (b != len))  fail("hr_last asserted too early");
                if (!hr_last && (b == len)) fail("hr_last missing on final beat");

                step;
                busy_cycles = busy_cycles + 1;
                if (stall > 0) hr_ready = 1'b0;
            end
            hr_ready = 1'b0;

            while (!cmd_done) begin
                if (!cmd_busy) fail("cmd_busy low before cmd_done");
                busy_cycles = busy_cycles + 1;
                step;
            end
        end
    endtask

    task fill_pattern(input [7:0] len, input [31:0] seed);
        integer b;
        begin
            for (b = 0; b <= len; b = b + 1) begin
                wbuf[b] = seed + (b * 32'h0001_0001);
                sbuf[b] = {(DATA_WIDTH/8){1'b1}};
            end
        end
    endtask

    integer b;
    integer t0;

    //-------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_axi4_master.vcd");
        $dumpvars(0, tb_axi4_master);

        $display("\n==== Level 2 : axi4_master unit test ====");

        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK);
        #1;
        ARESETn = 1'b1;
        step;

        //=====================================================================
        $display("\n-- M1 : AWREADY stalled 4 cycles, 5-beat INCR write");
        aw_ready_delay = 8'd4;  w_ready_delay = 8'd0;
        b_valid_delay  = 8'd0;
        fill_pattern(8'd4, 32'h1111_0000);
        host_write(4'h3, 32'h0000_0040, 8'd4, 3'd2, BURST_INCR, 0);
        chk2 ("M1 BRESP", cmd_resp, RESP_OKAY);
        chk32("M1 BID echoed", {28'd0, cmd_resp_id}, 32'h0000_0003);
        chk_int("M1 beats received", mock.w_cnt, 5);
        chk_int("M1 WLAST beat index", mock.w_last_idx, 4);
        for (b = 0; b <= 4; b = b + 1)
            chk32("M1 beat as seen by slave", mock.mw_data[b],
                  32'h1111_0000 + (b * 32'h0001_0001));

        //=====================================================================
        $display("\n-- M2 : WREADY stalled 3 cycles per beat, host bubbles too");
        aw_ready_delay = 8'd0;  w_ready_delay = 8'd3;
        fill_pattern(8'd3, 32'h2222_0000);
        host_write(4'h4, 32'h0000_0080, 8'd3, 3'd2, BURST_INCR, 2);
        chk2("M2 BRESP", cmd_resp, RESP_OKAY);
        chk_int("M2 beats received", mock.w_cnt, 4);
        for (b = 0; b <= 3; b = b + 1)
            chk32("M2 beat as seen by slave", mock.mw_data[b],
                  32'h2222_0000 + (b * 32'h0001_0001));

        //=====================================================================
        $display("\n-- M3 : ARREADY stalled 5 cycles, 5-beat INCR read");
        ar_ready_delay = 8'd5;  r_valid_delay = 8'd0;
        host_read(4'h7, 32'h0000_0100, 8'd4, 3'd2, BURST_INCR, 0);
        chk2 ("M3 RRESP", cmd_resp, RESP_OKAY);
        chk32("M3 RID echoed", {28'd0, cmd_resp_id}, 32'h0000_0007);
        chk32("M3 last_err clear", {31'd0, cmd_last_err}, 32'h0);
        for (b = 0; b <= 4; b = b + 1)
            chk32("M3 beat", rbuf[b], 32'h0000_0100 + (b << 8));

        //=====================================================================
        $display("\n-- M4 : BVALID and RVALID delayed 6 cycles");
        aw_ready_delay = 8'd0;  w_ready_delay = 8'd0;  ar_ready_delay = 8'd0;
        b_valid_delay  = 8'd6;  r_valid_delay = 8'd6;

        fill_pattern(8'd1, 32'h4444_0000);
        host_write(4'h1, 32'h0000_0200, 8'd1, 3'd2, BURST_INCR, 0);
        $display("  write occupied the manager for %0d cycles", busy_cycles);
        if (busy_cycles < 6) fail("write finished before BVALID could appear");
        chk2("M4 BRESP", cmd_resp, RESP_OKAY);

        host_read(4'h1, 32'h0000_0300, 8'd1, 3'd2, BURST_INCR, 0);
        $display("  read occupied the manager for %0d cycles", busy_cycles);
        if (busy_cycles < 6) fail("read finished before RVALID could appear");
        chk32("M4 read beat0", rbuf[0], 32'h0000_0300);
        chk32("M4 read beat1", rbuf[1], 32'h0000_0400);

        //=====================================================================
        $display("\n-- M5 : cmd_start_write hammered during a read burst");
        aw_ready_delay = 8'd0;  w_ready_delay = 8'd0;
        ar_ready_delay = 8'd3;  r_valid_delay = 8'd3;
        b_valid_delay  = 8'd0;

        while (cmd_busy) step;
        cmd_id         = 4'h9;
        cmd_addr       = 32'h0000_0500;
        cmd_len        = 8'd3;
        cmd_size       = 3'd2;
        cmd_burst      = BURST_INCR;
        cmd_start_read = 1'b1;
        step;
        cmd_start_read = 1'b0;

        // Change the command inputs to values that would corrupt the burst if
        // the manager were not registering them, and demand a write as well.
        cmd_id          = 4'hF;
        cmd_addr        = 32'hDEAD_0000;
        cmd_len         = 8'd0;
        cmd_start_write = 1'b1;
        hw_data         = 32'hBAD0_BAD0;
        hw_strb         = 4'b1111;
        hw_valid        = 1'b1;

        hr_ready = 1'b1;
        b        = 0;
        while (!cmd_done) begin
            if (!cmd_busy) fail("cmd_busy low before cmd_done during M5");
            if (AWVALID)   fail("manager issued a write while busy");
            if (hr_valid) begin
                rbuf[b] = hr_data;
                b       = b + 1;
            end
            step;
        end
        cmd_start_write = 1'b0;
        hw_valid        = 1'b0;
        hr_ready        = 1'b0;

        chk_int("M5 beats delivered", b, 4);
        chk32 ("M5 beat0 kept original address", rbuf[0], 32'h0000_0500);
        chk32 ("M5 beat3", rbuf[3], 32'h0000_0800);
        chk32 ("M5 RID still 0x9", {28'd0, cmd_resp_id}, 32'h0000_0009);

        //=====================================================================
        $display("\n-- M6 : SLVERR on the read beats is reported to the host");
        ar_ready_delay = 8'd0;  r_valid_delay = 8'd0;
        r_resp_val     = RESP_SLVERR;
        host_read(4'h2, 32'h0000_0900, 8'd2, 3'd2, BURST_INCR, 0);
        chk2("M6 cmd_resp", cmd_resp, RESP_SLVERR);
        r_resp_val = RESP_OKAY;

        //=====================================================================
        $display("\n-- M7 : subordinate sends RLAST early -> cmd_last_err");
        r_len_force_en = 1'b1;
        r_len_force    = 8'd1;            // slave ends the burst after 2 beats
        while (cmd_busy) step;
        cmd_id         = 4'h6;
        cmd_addr       = 32'h0000_0A00;
        cmd_len        = 8'd4;            // host asked for 5 beats
        cmd_start_read = 1'b1;
        step;
        cmd_start_read = 1'b0;
        hr_ready = 1'b1;
        b        = 0;
        while (!cmd_done) begin
            if (hr_valid) b = b + 1;
            step;
        end
        hr_ready = 1'b0;
        chk_int("M7 beats delivered", b, 2);
        chk32 ("M7 cmd_last_err set", {31'd0, cmd_last_err}, 32'h1);
        r_len_force_en = 1'b0;

        //=====================================================================
        $display("\n-- M8 : 16-beat write with no stalls, one beat per clock");
        aw_ready_delay = 8'd0;  w_ready_delay = 8'd0;  b_valid_delay = 8'd0;
        fill_pattern(8'd15, 32'h8888_0000);
        while (cmd_busy) step;
        t0 = $time;
        host_write(4'h8, 32'h0000_0B00, 8'd15, 3'd2, BURST_INCR, 0);
        $display("  16 beats + response took %0d ns", $time - t0);
        chk2   ("M8 BRESP", cmd_resp, RESP_OKAY);
        chk_int("M8 beats received", mock.w_cnt, 16);
        chk_int("M8 WLAST beat index", mock.w_last_idx, 15);
        for (b = 0; b <= 15; b = b + 1)
            chk32("M8 beat", mock.mw_data[b],
                  32'h8888_0000 + (b * 32'h0001_0001));
        // 16 data beats cannot take fewer than 16 clocks; allow a small fixed
        // overhead for the command, the AW handshake and the B response.
        if (($time - t0) > (16 + 8) * CLK_PERIOD)
            fail("16-beat burst was not streaming at one beat per clock");

        //=====================================================================
        repeat (5) step;
        $display("\n==== Level 2 result : %0d checks, %0d failure(s) ====",
                 checks, errors);
        if (errors == 0) $display("TEST PASSED\n");
        else             $display("TEST FAILED\n");
        $finish;
    end

    initial begin
        #200000;
        $display("\n[FAIL] tb_axi4_master timed out -- possible deadlock");
        $display("TEST FAILED\n");
        $finish;
    end

endmodule
