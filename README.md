# AMBA AXI4 in pure Verilog — manager, subordinate, and a registered interconnect

A complete, simulated, synthesisable **full AXI4** implementation: bursts,
transaction IDs, `WLAST`/`RLAST`, narrow transfers, and all three burst types.
The manager and the subordinate communicate **only through D-flip-flops** — one
registered pipeline stage per channel, in both directions.

All four test suites pass: **251 checks, 0 failures.**

---

## 1. What is in here

```
FPGA_Project\
├── rtl\
│   ├── axi4_slave.v         AXI4 subordinate: a burst-capable 4 KiB memory
│   ├── axi4_master.v        AXI4 manager: burst engine + streaming host ports
│   ├── axi4_skid_buffer.v   one registered (D-flip-flop) channel stage
│   └── axi4_top.v           manager + subordinate joined by five FF stages
├── sim\
│   ├── tb_axi4_slave.v      Level 1 : subordinate alone      (45 checks)
│   ├── tb_axi4_master.v     Level 2 : manager + mock slave   (52 checks)
│   └── tb_axi4_top.v        Level 3 : whole system           (77 checks x2)
├── run_tests.ps1            Windows test runner (no `make` needed)
└── Makefile                 same targets for GNU make / Linux
```

## 2. How to run it

You have Icarus Verilog at `C:\iverilog`, so from `E:\FPGA_Project`:

```powershell
.\run_tests.ps1                  # all four suites, prints a summary
.\run_tests.ps1 -Suite slave     # just one: slave | master | top | top_direct
.\run_tests.ps1 -Suite top -Wave # run, then open the waveform in GTKWave
```

Logs and `.vcd` waveforms land in `build\`. On Linux the `Makefile` has the
same targets (`make test_all`).

---

## 3. Why AXI4 is more than AXI4-Lite

AXI4-Lite moves **one** 32-bit word per transaction. Full AXI4 moves a **burst**:
one address, then up to 256 data *beats*. A "beat" is a single data transfer —
one `WVALID`/`WREADY` handshake. That one change pulls in everything else:

| Added for AXI4 | What it is | Why it is needed |
|---|---|---|
| `AxLEN` | beats − 1 (`0` = 1 beat, `255` = 256 beats) | the burst length |
| `AxSIZE` | log2(bytes per beat) | lets a beat be narrower than the bus |
| `AxBURST` | `00` FIXED, `01` INCR, `10` WRAP | how the address moves between beats |
| `WLAST`, `RLAST` | marks the final beat | the receiver must know where the burst ends |
| `AxID`, `BID`, `RID` | transaction tag | lets responses be matched to requests |
| `AxCACHE`, `AxPROT`, `AxQOS`, `AxLOCK` | memory/security/priority attributes | part of the AXI4 signal set |

The three burst types, with 4-byte beats:

* **INCR** — the normal case. `0x100, 0x104, 0x108, 0x10C …`
* **FIXED** — the address never moves. Every beat hits the same word, so the
  last beat wins. Used for streaming into a FIFO register.
* **WRAP** — INCR, but folded back inside a power-of-two window. Four beats
  from `0x208` go `0x208, 0x20C, 0x200, 0x204`. This is how a CPU fetches a
  cache line when the word it actually wants sits in the middle of the line.

**Narrow transfers.** If `AxSIZE` says 1 byte but the bus is 4 bytes wide, each
beat uses only one byte lane, and *which* lane follows the address. Four 1-byte
beats from `0x800` therefore fill the four lanes of one 32-bit word — test
`A11` writes `0x11,0x22,0x33,0x44` that way and reads back `0x44332211`.

---

## 4. The subordinate (`axi4_slave.v`)

A 4 KiB memory (1024 × 32-bit words). Addresses `0x000`–`0xFFF` are mapped;
anything above returns `DECERR`.

It has two independent state machines, because the write channels and the read
channels are independent channel groups and must be able to run at the same
time.

**Write side** (`WST_IDLE → WST_DATA → WST_RESP`):

1. Capture `AW`: the ID, address, length, size and burst type go into
   flip-flops, and the wrap window is computed once, up front.
2. Consume exactly `AWLEN+1` beats, applying `WSTRB` byte by byte and stepping
   the address per the burst rules after each beat.
3. Emit **one** `B` response for the whole burst, with `BID` echoing `AWID`.

**Read side** (`RST_IDLE → RST_DATA`): the first beat is fetched on the `AR`
handshake itself, and every later beat is fetched on the `R` handshake that
retires the previous one. That is what keeps the burst streaming at one beat
per clock with no gaps.

**Error handling.** Three things matter here, and all three are tested:

* A bad address gives `DECERR` (`2'b11`); an unsupported request gives
  `SLVERR` (`2'b10`) — a reserved burst type, an `AxSIZE` wider than the bus,
  or a WRAP that is not 2/4/8/16 beats.
* An erroring **write** burst is still drained in full. The subordinate cannot
  simply stop accepting beats, or the manager would hang forever; it accepts
  them and suppresses only the memory update.
* An erroring **read** burst still returns `AxLEN+1` beats and still asserts
  `RLAST` on the last one, for the same reason.

---

## 5. The manager (`axi4_master.v`)

The host side is deliberately simple: a **command port** plus two **valid/ready
data streams**.

```
cmd_start_write / cmd_start_read      accepted only while cmd_busy == 0
cmd_id, cmd_addr, cmd_len,            the burst descriptor
cmd_size, cmd_burst
        ↓
hw_data / hw_strb / hw_valid / hw_ready    you push write beats in here
hr_data / hr_resp / hr_last / hr_valid / hr_ready    read beats come out here
        ↓
cmd_done      one-cycle strobe when the burst finishes
cmd_resp      the response (for a read, the worst beat's response)
cmd_resp_id   the ID the subordinate echoed back
cmd_last_err  set if the subordinate's RLAST did not match cmd_len
```

Two design points are worth calling out, because they are the two rules that
AXI implementations most often get wrong:

**The whole descriptor is registered on the accepting cycle.** AXI section A2.3
says that once `VALID` is high, the payload must not change by even one bit
until the handshake completes. Because `AWADDR`, `AWLEN` and friends are driven
from flip-flops loaded once at the start, the host can change its mind on
`cmd_addr` the very next cycle and the burst in flight is unaffected. Test
`M5` proves this by overwriting `cmd_addr` with `0xDEAD_0000` mid-burst and
confirming the read still comes from the original address.

**`WLAST` is generated here, not by the host.** The manager counts beats and
asserts `WLAST` on beat `cmd_len`, so the host just streams data and never has
to track where the burst ends.

Only one burst is outstanding at a time. That is fully compliant — it simply
means this manager never needs ID-based reordering logic.

---

## 6. The D-flip-flop interconnect (`axi4_skid_buffer.v`)

This is the part you asked for: nothing crosses between the two modules
combinationally. Each of the five channels passes through its own registered
stage.

```
master ──AW──►[FF]──►  slave        forward : AW, W, AR
master ──W───►[FF]──►  slave
master ──AR──►[FF]──►  slave
master ◄──[FF]◄──B───  slave        reverse : B, R
master ◄──[FF]◄──R───  slave
```

### Why a plain D-flip-flop would be a bug

Registering `VALID` and the payload alone is not enough, because then the
upstream `READY` still has to travel back combinationally — which defeats the
point. But if you register `READY` as well, the transmitter sees the old
`READY` for one extra cycle and keeps driving a beat the stage has **already
consumed**. That beat is silently lost.

A **skid buffer** fixes this by holding up to *two* payloads — the output
register plus one spare "skid" slot. That spare slot buys exactly the one cycle
of slack needed to register `READY`:

```
in_ready = ~skid_valid
```

When the output register is blocked, the next incoming beat lands in the skid
slot, which *immediately* drops `in_ready`, so a third beat can never arrive
and nothing is ever overwritten. Payload, `VALID` and `READY` are now all
flip-flop outputs.

### What it costs, measured

The Level 3 testbench runs the identical stimulus twice — once with the stages
(`PIPE_STAGE=1`) and once with the modules wired directly (`PIPE_STAGE=0`):

| 32-beat burst | registered | direct | difference |
|---|---|---|---|
| write | 37 cycles | 35 cycles | +2 |
| read | 36 cycles | 34 cycles | +2 |

32 beats cannot take fewer than 32 cycles, so the overhead column *is* the
entire pipeline cost — and it is a **fixed +2 cycles that does not grow with
burst length**. Latency goes up slightly; throughput is unchanged at one beat
per clock. In exchange, every path between the two modules is now
register-to-register, which is what lets them be placed far apart on the die
and still close timing. This is the same structure Xilinx ships as the
"AXI Register Slice".

Set `PIPE_STAGE = 0` on `axi4_top` to bypass all five stages.

---

## 7. What the tests cover

**Level 1 — subordinate alone (45 checks).** The testbench *is* the manager, so
it can force things a real manager will not: single beats; a 5-beat INCR burst;
a WRAP burst starting mid-window; a FIXED burst; `WSTRB` byte merging inside a
burst; `RREADY` deasserted before every beat with full payload-stability
checking; `BREADY` stalled 5 cycles; `DECERR`; ID echo; all four `SLVERR`
cases; and narrow 1-byte beats assembling into a word.

**Level 2 — manager against a mock subordinate (52 checks).** The mock has
dial-able per-channel `READY` latency and response latency, and can be told to
lie about the burst length. Three **always-on monitors** watch `AW`, `W` and
`AR` for the entire run and fail the test if `VALID` is ever withdrawn before
its handshake or if any payload bit (including `WLAST`) changes while stalled.
Also: `cmd_busy` must stay high until `cmd_done`; a start pulse during a burst
must be ignored; `SLVERR` must reach `cmd_resp`; an early `RLAST` must raise
`cmd_last_err`; and a 16-beat burst must stream at one beat per clock.

**Level 3 — whole system, run twice (77 checks each).** End-to-end bursts of
every type through the flip-flop stages, byte strobes, `DECERR` propagation to
the host, host back-pressure mid-burst, 32-beat throughput measurement, and an
**asynchronous reset asserted in the middle of a write burst** followed by
recovery.

One note on that reset test. How much of an aborted burst actually lands in
memory is *deliberately not asserted*, and this is worth understanding: the
memory array itself is not reset, but beats that were still sitting inside the
channel pipeline registers when reset hit are discarded. The run shows this
plainly — with the FF stages both beats are lost, without them both land. A
burst killed by reset has no defined outcome, so the test reports it instead of
checking it, and asserts only that the system returns cleanly to idle and works
afterwards.

---

## 8. Relationship to the plan document

`axi_lite_architecture_and_implementation_plan.md` in this folder specifies
**AXI4-Lite** — a 4-register bank, single-beat only, no IDs, no bursts. This
implementation is **full AXI4** instead, per the change of direction, so the
following parts of that document no longer describe the code:

* Section 1.1 lists the signals AXI4-Lite *omits* (`AxLEN`, `AxSIZE`,
  `AxBURST`, `AxID`, `WLAST`, `RLAST`, `AxCACHE`, `AxLOCK`). All of them are
  present and functional here.
* Section 3.1's four-register memory map (`REG_CTRL`, `REG_STAT`, `REG_DATA_A`,
  `REG_DATA_B`) is replaced by a 4 KiB burst-addressable memory.
* Section 3.2's two-phase latch-and-execute write engine was a fix for a
  single-beat register write. The AXI4 write engine is a three-state burst
  machine instead.
* Section 4.1's host contract had no `cmd_len` / `cmd_size` / `cmd_burst` and
  no data streams, because a single-beat transaction needs neither.
* The file names in section 6 (`axi_lite_*.v`) are now `axi4_*.v`, and the
  module list gained `axi4_skid_buffer.v`.

What *does* carry over unchanged: the handshake rules in section 1.2, the
payload-stability requirement, the "no combinational path from an interface
input to an interface output" rule, the three-level verification strategy, and
the acceptance criteria in section 7.

## 9. Synthesis notes

Nothing here is simulation-only except the testbenches. Against the plan's
acceptance criteria:

* **No inferred latches** — every `always` block is edge-triggered with a
  complete reset branch.
* **No combinational path between the two AXI modules** — every signal that
  crosses from manager to subordinate, or back, goes through a flip-flop
  stage, and every subordinate output is a flip-flop. One exception to be
  aware of: inside `axi4_master`, the host data streams are wired through to
  the W and R channels with only a state gate (`WVALID = hw_valid & open`,
  `hw_ready = WREADY & open`, `RREADY = hr_ready & open`, and the `hr_*`
  outputs likewise). Those are combinational host-to-bus paths. They are
  safe because the flip-flop stages sit immediately after them, but it is not
  true that every master output is registered.
* **No combinational loops** — the only cross-module paths are through the
  skid-buffer registers.
* The subordinate's `mem` array is written in one block and read in another, so
  it infers a simple dual-port block RAM. The `initial` loop that clears it
  becomes BRAM initialisation data in Vivado.
* `clogb2()` is a Verilog-2001 constant function, used instead of `$clog2()` so
  the RTL stays Verilog-2001 (the `-g2005` flag in the build is for the
  testbenches).
