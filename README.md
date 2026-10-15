# AXI4: five channels, a master and a memory

The smallest burst-capable AXI4 design that is still a real AXI4:

```
testbench -> [input DFFs] -> master ==AXI4== slave (memory)
                              |
                              +-> [output DFFs] -> testbench
```

The testbench loads an address and four words into the **input D flip-flops**.
The **master** takes them from there and writes them to the **slave**, then
reads them back. The words that come back are stored in the **output D
flip-flops**. The master and the slave are connected directly: the five AXI4
channels go straight across, with nothing in between.

Both test runs pass: **33 + 43 = 76 checks, 0 failing** (Icarus Verilog).

## Files

```
rtl/
  axi4_in_dff.v     input D flip-flops: address + four words, loaded by the testbench
  axi4_master.v     the master: write four words, read them back
  axi4_slave.v      the slave: a 4 KiB memory
  axi4_out_dff.v    output D flip-flops: the four words read back
  axi4_top.v        wires the four together; the master and slave connect directly
sim/
  tb_axi4_slave.v   the slave on its own, driven channel by channel (33 checks)
  tb_axi4_top.v     the whole system: load, start, check            (43 checks)
results/            logs and waveforms from the passing runs
docs/               block diagram, waveforms, presentation
run_tests.ps1       runs both testbenches (Windows)
Makefile            same thing for GNU make
```

```powershell
.\run_tests.ps1                  # both
.\run_tests.ps1 -Suite top -Wave # then open the waveform
```

## How a run goes

1. **Load.** The testbench stores a value in each input flip-flop, one per
   clock: `load = 1`, `load_sel` picks the register (0 = address, 1 to 4 =
   the four words), `load_data` is the value.
2. **Start.** The testbench raises `start`. The master:
   - writes the four words to the address (one burst of four beats) and
     waits for the response,
   - reads the four words back (one burst); each beat goes to the output
     flip-flops.
3. **Done.** `done` goes high. The words are in `rd0..rd3`, and `pass` is 1 if
   they equal the four that were loaded. Drop `start` to run again.

## The five channels

Each channel is a payload plus `VALID` (sender) and `READY` (receiver). A
transfer happens in the cycle where both are high.

| Channel | Direction | Signals |
|---|---|---|
| AW write address | master to slave | `AWID`, `AWADDR`, `AWLEN`, `AWVALID`, `AWREADY` |
| W write data | master to slave | `WDATA`, `WSTRB`, `WLAST`, `WVALID`, `WREADY` |
| B write response | slave to master | `BID`, `BRESP`, `BVALID`, `BREADY` |
| AR read address | master to slave | `ARID`, `ARADDR`, `ARLEN`, `ARVALID`, `ARREADY` |
| R read data | slave to master | `RID`, `RDATA`, `RRESP`, `RLAST`, `RVALID`, `RREADY` |

`AxLEN` is beats minus one (so up to 256 beats). `WSTRB` has one bit per byte.
`WLAST` and `RLAST` mark the final beat. `BID` repeats `AWID`, `RID` repeats
`ARID`. `BRESP` and `RRESP` are always `00` (OKAY).

## The master

One state machine, one step per channel:

`S_IDLE` (wait for `start`) → `S_AW` → `S_W` → `S_B` → `S_AR` → `S_R` →
`S_DONE` (hold `done` until `start` drops).

It holds no data of its own: the address and words are inputs from the input
flip-flops, and every read beat leaves on `rd_valid` / `rd_idx` / `rd_data`
for the output flip-flops.

## The slave

* **Write:** take the address, then take beats until `WLAST`, writing each
  word (only the bytes selected by `WSTRB`) and adding 4 to the address; then
  send one response.
* **Read:** take the address, send `ARLEN + 1` beats, adding 4 each time, and
  mark the last with `RLAST`.
* Reads and writes are separate state machines.

## The D flip-flops

* **Input** (`axi4_in_dff`): five 32-bit registers. One is stored on each
  clock edge where `load = 1`. Reset clears them.
* **Output** (`axi4_out_dff`): four 32-bit registers. A read beat is stored in
  the register for its position (`rd_idx`) on the clock edge where
  `rd_valid = 1`. Reset clears them.

## Timing

With nothing between the master and the slave, a beat moves every clock the
receiver is ready. Write address at cycle 1, four write beats at cycles 2 to
5, response at 6, read address at 7, four read beats at 8 to 11, `done` at 12:
**13 clock cycles from `start`**.

## What is tested

* **Slave alone (33 checks):** single and multi-beat bursts, address before
  data and data before address, held-off responses and read data, byte
  strobes, ID echo, the longest burst (256 beats), reset in the middle of a
  burst.
* **Whole system (43 checks):** nothing happens until `start`; the input
  flip-flops hold what was loaded; the master finishes and `pass` is 1; the
  output flip-flops and the slave's memory hold the four words; every response
  is OKAY with the right ID; `VALID` and the payload hold steady until `READY`
  (AW, W, AR); a second run with a different address and different words;
  `pass` drops if a loaded word no longer matches; a reset in the middle of
  the sequence clears the flip-flops and a reload runs clean.

## Not included

Burst types other than counting up (no FIXED, no WRAP), narrow beats, the
`AxLOCK`/`AxCACHE`/`AxPROT`/`AxQOS` signals, error responses, several
transactions at once, an interconnect (one master, one slave).

## Notes

* The master always moves four words with all bytes enabled.
* The input flip-flops must not change while a sequence is running.
* One burst at a time. An address beyond 4 KiB wraps inside it.
* Reset is active low and asynchronous. It clears the master, the slave's
  state machines and both flip-flop banks; the memory contents are not cleared.
