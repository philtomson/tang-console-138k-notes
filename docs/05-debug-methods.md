# 05 — Debug methods that worked

With no logic analyser in the loop, two methods found every hardware bug in
this project.  Both assume a working simulation of the whole design, so
"board == sim" is the thing you test.

## A. A UART "chirp" plus stage hashes

**The chirp.** A tiny free-running UART transmitter (no dependency on the
design's own logic) sends a short frame every ~20 ms:
`0x7E <byte1> ... <byte7>`.  Put live status in the bytes: calibration bits,
FSM states, 8-bit event counters.  Rules we learned:

* An 8-bit counter wraps.  Compare **deltas between frames**, not absolute
  values.
* To send more than 7 bytes, **rotate** an index through the frames: one
  frame carries byte *k* of a long report plus *k* itself.  32 entries of
  rotation carried everything we needed.
* Decode with a script that checks the frame delimiter *and* the value ranges,
  since payload bytes can equal the delimiter.
* Remember the FT2232 UART wedge ([01](01-board-and-connection.md)): no bytes
  means "replug first".

**Stage hashes.** When the board computes a different final answer than the
simulation, hash the data **at each stage boundary** on both, and walk forward
to the first boundary that differs:

```verilog
// order-sensitive, cheap, one per stage boundary
always @(posedge clk)
    if (valid) begin
        n <= n + 1;
        h <= {h[26:0], h[31:27]} + (data ^ n);   // mix in the index
    end
```

Use additive/rotating hashes mixed with the event index.  A pure rotate-XOR
hash came out exactly 0 in our first try, because the repetitive data
cancelled.  Report `(n, h)` over the chirp and compute the same in simulation.

What this found for us, in order: DDR3 write and read data matched
(ruling out the memory path); the attention engine's inputs matched; the
softmax outputs as *written* differed; the matrix-vector unit's *inputs*
matched but its outputs did not.  Each step removed a large part of the design
from suspicion in one build.

**Self-checks on the board.**  Some things don't need simulation.  Our DDR3
preload self-test ([03](03-ddr3-bringup.md)) writes an address-derived pattern
and reads it back.  Its counters (errors, first and last bad address, the
write timestamps) located the post-calibration write-loss window directly.

## B. Gate-level replay: RTL vs the Gowin netlist, same inputs

When a block's inputs match simulation but its outputs don't, suspect a
synthesis/simulation mismatch.  This proves or disproves it, and localizes it
to a net:

1. **Record** the block's inputs every clock in the (Verilator) system
   simulation, one hex line per cycle, with `$fwrite` behind an `ifdef`.  Run
   the simulation from a directory that has every `.mem` file.  A missing ROM
   file made one of our recordings run away to 16 GB while the design waited
   forever.
2. **Synthesize the block standalone** with Gowin (synthesis only; a thin
   wrapper exposing the block's ports; `.mem` files next to the wrapper).  The
   netlist is `impl/gwsynthesis/<name>.vg`.
3. **Replay** the recording into both the RTL and the netlist in iverilog,
   with Gowin's `prim_sim.v`, and compare the outputs every cycle.
   [tools/gate_replay](../tools/gate_replay) has scripts for this.  The
   details that matter:
   * rename every netlist module with a suffix (for example `_g`), because the
     netlist reuses the RTL module names;
   * `GSR GSR (.GSRI(1'b1));` in the testbench, and `iverilog -s tb`;
   * **mask bits that are X in the RTL**: iverilog leaves uninitialized
     memories at X, while the hardware (and Verilator) start at 0;
   * or **zero-initialize the RTL's RAMs** in the testbench, to match the
     board's power-up contents;
   * compare pipeline stages **only when their valid flag is set**, or junk in
     idle stages shows up as false differences.
4. **Probe internals.**  Gowin keeps submodules as modules, and their ports and
   many internal nets keep names derived from the parent (escaped identifiers
   like `\sl[0].l1`).  Compare the same nets in RTL and gate to find the first
   diverging one.

Before trusting a replay, check that **the gate model reproduces the board**.
For our matrix-vector bug, the standalone netlist produced exactly the board's
output hash (`889eeb8c`), while RTL gave the sim's (`fef73568`).  After that,
every experiment can run in simulation.

Replays are slow in iverilog (an attention engine took ~1 hour for 1.9M
cycles), so stop at the first divergence.
