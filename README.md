# AMBA AXI4 manager and subordinate in Verilog

A plain AXI4 implementation: a burst-capable manager and a burst-capable
memory subordinate, wired directly together. Protocol only, no extras.

All three test suites pass: **156 checks, 0 failures** (simulated with
Icarus Verilog).

## Files

```
rtl/
  axi4_master.v   AXI4 manager with a minimal host interface
  axi4_slave.v    AXI4 subordinate: a 4 KiB burst-capable memory
  axi4_top.v      manager wired directly to subordinate
sim/
  tb_axi4_slave.v    Level 1: subordinate alone                (38 checks)
  tb_axi4_master.v   Level 2: manager against a mock subordinate (46 checks)
  tb_axi4_top.v      Level 3: whole system                     (72 checks)
results/            logs and waveforms from the passing runs
run_tests.ps1       Windows test runner
Makefile            same targets for GNU make
```

## Run

```powershell
.\run_tests.ps1                  # all three suites and a summary
.\run_tests.ps1 -Suite slave     # slave | master | top
.\run_tests.ps1 -Suite top -Wave # then open the waveform in GTKWave
```

## What is implemented

**All five AXI4 channels:** AW, W, B, AR, R, each with VALID and READY.

**Bursts:** 1 to 256 beats (`AxLEN` = beats minus 1), with `AxSIZE`,
`AxBURST` (FIXED, INCR, WRAP), `WLAST` and `RLAST`.

**IDs:** `BID` echoes `AWID`, and `RID` echoes `ARID`.

**Byte strobes:** `WSTRB` selects which bytes of a word are written.

**Attribute signals:** `AxLOCK`, `AxCACHE`, `AxPROT` and `AxQOS` are present
on the ports. The manager ties them to zero and the subordinate ignores them.

### The subordinate

* Two independent state machines, one for writes and one for reads.
* Write: accept the address, then accept beats until `WLAST`, then send one
  `B` response.
* Read: the first beat is fetched on the `AR` handshake and each following
  beat on the previous beat's `R` handshake, so beats stream one per clock.
* Every response is OKAY. There is no address or request checking, so an
  address beyond the memory simply wraps inside it.

### The manager

Host side:

| Signal | Meaning |
|---|---|
| `cmd_start_write`, `cmd_start_read` | begin a burst (only taken when idle; write wins if both are high) |
| `cmd_id`, `cmd_addr`, `cmd_len`, `cmd_size`, `cmd_burst` | the burst description, copied into registers at the start |
| `hw_data`, `hw_strb`, `hw_valid`, `hw_ready` | write data in, a plain valid/ready stream |
| `hr_data`, `hr_valid`, `hr_ready` | read data out, a plain valid/ready stream |
| `cmd_done` | one-cycle pulse when the burst has finished |
| `cmd_resp` | `BRESP` for a write, `RRESP` of the last beat for a read |

States: IDLE, WRITE (AW and W together), B, RADDR, RDATA. The manager
generates `WLAST` from its own beat counter and ends a read on `RLAST`.

## What is deliberately not here

Multiple outstanding transactions and ID reordering, exclusive access
(`EXOKAY`), error responses, any behaviour for `AxCACHE`/`AxPROT`/`AxQOS`,
and any protocol checking inside the RTL.

## Known properties

* Master and subordinate are connected directly. The manager's host data
  streams pass straight through to the W and R channels with only a state
  gate, so those are combinational host-to-bus paths.
* One burst per direction at a time. The IDs are echoed but never used to
  reorder anything.
* Reset is active low and asynchronous. It clears all state machines and
  handshake registers; the memory contents are not cleared.
* A 32-beat burst takes 35 cycles (write) and 34 cycles (read), measured in
  `tb_axi4_top.v`. That is one beat per clock plus a few cycles of fixed
  address and response overhead.
