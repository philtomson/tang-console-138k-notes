# Gate-level replay: RTL vs Gowin netlist

`make_replay.py` checks whether Gowin's netlist of a block behaves like its
RTL for the inputs your design really gives it.  The method and its caveats
are in [docs/05](../../docs/05-debug-methods.md).

## Steps

1. **Synthesize the block alone** (synthesis only):

   ```sh
   NAME=blk TOP=my_block SYNTH_ONLY=1 SRC=my_block.v \
     ../gowin_build/run_gowin.sh ../gowin_build/build.tcl
   ```

   Copy any `.mem` files next to `my_block.v` first: Gowin resolves `$readmemh`
   relative to the top file.

2. **Generate the replay**, which also prints the recorder snippet:

   ```sh
   ./make_replay.py --top my_block --rtl my_block.v \
       --netlist blk/impl/gwsynthesis/blk.vg --out rp
   ```

3. **Record inputs.**  Paste the printed `$fwrite` snippet next to the block's
   instance in your system simulation and run it; you get `inputs.hex`, one
   line per clock.  (Or generate stimulus, as the example below does.)  Run
   from a directory that has every `.mem` file your design reads.

4. **Run:**

   ```sh
   iverilog -g2012 -s tb -o rp/sim rp/tb.v my_block.v rp/gate.v \
       $GOWIN/IDE/simlib/gw5a/prim_sim.v
   vvp -n rp/sim +rec=inputs.hex +stop=5
   ```

   You get `END ... diverging_cycles=0`, or `DIVERGE cycle N:` lines naming each
   differing output with its RTL and gate values.

## Example

`example/` has a small dual-write module, its split fix and 4,000 random
input cycles.  Both synthesize correctly when standalone (the tool reports 0
divergences), which is itself the lesson of [docs/04](../../docs/04-gowin-synthesis-pitfalls.md)
pitfall 1: this mismatch only shows up in context.

```sh
cd example
NAME=dw TOP=dual_write SYNTH_ONLY=1 SRC=dual_write.v ../../gowin_build/run_gowin.sh ../../gowin_build/build.tcl
../make_replay.py --top dual_write --rtl dual_write.v --netlist dw/impl/gwsynthesis/dw.vg --out rp
iverilog -g2012 -s tb -o rp/sim rp/tb.v dual_write.v rp/gate.v $GOWIN/IDE/simlib/gw5a/prim_sim.v
vvp -n rp/sim +rec=inputs.hex
```

## Tips from real use

* If the gate model reproduces your **board's** wrong output exactly, you have
  proven a synthesis mismatch, and every further experiment can stay in
  simulation.
* Stop at the first divergence (`+stop=1`): iverilog replays of large blocks
  are slow (hours for millions of cycles).
* To localize inside the block, probe internal nets.  Gowin keeps submodule
  boundaries and names nets after the RTL (escaped identifiers such as
  `\sl[0].l1 `), so you can compare `r.u.sl[0].l1` against `g.u.\sl[0].l1 `.
  Compare pipeline stages only while their valid flag is set.
