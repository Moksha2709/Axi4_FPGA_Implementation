# AXI4: five channels, a master and a memory

The smallest burst-capable AXI4 design that is still a real AXI4: a master that
starts the transfers itself, a memory that answers them, and a D flip-flop
stage at both ends of every channel.

Both test runs pass: **33 + 13 = 46 checks, 0 failing** (Icarus Verilog).

## Files

```
rtl/
  axi4_master.v     the master: data in D flip-flop registers, starts by itself
  axi4_reg_stage.v  one D flip-flop stage (holds one beat)
  axi4_slave.v      the slave: a 4 KiB memory
  axi4_top.v        master, ten stages, slave
sim/
  tb_axi4_slave.v   the slave on its own, driven channel by channel (33 checks)
  tb_axi4_top.v     the whole system, the master runs by itself   (13 checks)
results/            logs and waveforms from the passing runs
docs/               block diagram, waveforms, presentation
run_tests.ps1       runs both testbenches (Windows)
Makefile            same thing for GNU make
```

```powershell
.\run_tests.ps1                  # both
.\run_tests.ps1 -Suite top -Wave # then open the waveform
```

## How it fits together

```
 master  --AW,W,AR-->  [stage]  -->  [stage]  -->  slave
 (D flip-flop          master side   slave side     (4 KiB memory)
  registers)  <--B,R-- [stage]  <--  [stage]  <--
```

There is no host interface. The master holds an address and four words in D
flip-flop registers and, after reset, runs by itself:

1. write the four words to `0x10` (one burst of four beats), wait for the response
2. read the four words back (one burst), compare with what it wrote

It has two outputs: `done` (the sequence has finished) and `pass` (what came
back equals what was written).

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

## The slave

* **Write:** take the address, then take beats until `WLAST`, writing each
  word (only the bytes selected by `WSTRB`) and adding 4 to the address; then
  send one response.
* **Read:** take the address, send `ARLEN + 1` beats, adding 4 each time, and
  mark the last with `RLAST`.
* Reads and writes are separate state machines.

## The D flip-flop stage

A stage holds one beat in flip-flops. While it is full it tells the sender
"wait" (`in_ready = 0`). When the next side takes the beat, it is empty again.

`in_ready` comes straight from a flip-flop, so a late `READY` can never lose a
beat or send one twice. A bare flip-flop on `VALID`/`READY` would not be safe
for that reason. The cost is that a beat sits in the stage for a clock, so
**one beat moves every two clocks**. The whole sequence (write, response,
read, done) takes 27 clock cycles.

## What is tested

* **Slave alone (33 checks):** single and multi-beat bursts, address before
  data and data before address, held-off responses and read data, byte
  strobes, ID echo, the longest burst (256 beats), reset in the middle of a
  burst.
* **Whole system (13 checks):** the master finishes and passes, the four
  words are in the slave's memory, every response is OKAY with the right ID,
  `VALID` and the payload hold steady until `READY` (AW, W, AR), and a reset
  in the middle of the sequence is followed by a clean re-run.

## Not included

Burst types other than counting up (no FIXED, no WRAP), narrow beats, the
`AxLOCK`/`AxCACHE`/`AxPROT`/`AxQOS` signals, error responses, several
transactions at once, a host interface.

## Notes

* The master's data is fixed in its registers. To send something else, change
  the reset values in `axi4_master.v`.
* One burst at a time. An address beyond the 4 KiB wraps inside it.
* Reset is active low and asynchronous. It clears the state machines and the
  stages; the memory contents are not cleared.
