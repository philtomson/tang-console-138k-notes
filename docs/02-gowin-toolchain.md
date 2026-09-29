# 02 — Gowin toolchain, headless on Linux

We built everything with the Gowin vendor tools (V1.9.12.x, GowinSynthesis),
driven from TCL through `gw_sh` with no GUI.  The DDR3 Memory Interface IP is
vendor-only, so the open-source flow was not an option for this design.

## Running gw_sh headless

`gw_sh` is Qt-based and needs a few environment variables on Linux.
[`tools/gowin_build/run_gowin.sh`](../tools/gowin_build/run_gowin.sh) sets
them for the one process:

```sh
export LD_PRELOAD=/lib64/libfreetype.so.6      # bundled freetype breaks Qt here
export QT_QPA_PLATFORM=minimal                 # no display
export QT_PLUGIN_PATH=$GOWIN/IDE/plugins/qt
export LD_LIBRARY_PATH=$GOWIN/IDE/lib
$GOWIN/IDE/bin/gw_sh build.tcl
```

**Keep these out of your interactive shell.** Gowin's `IDE/lib` shadows
system libraries: `openFPGALoader` then fails to start
(`libbz2.so.1: cannot open shared object file`), and a flash you thought
happened didn't.

## A reusable build script

[`tools/gowin_build/build.tcl`](../tools/gowin_build/build.tcl) is a small
parameterized flow that takes its settings from environment variables:

```sh
NAME=blinky TOP=top SRC=top.v:board.cst:board.sdc \
  ./run_gowin.sh build.tcl          # -> blinky/impl/pnr/blinky.fs
SYNTH_ONLY=1 NAME=blk TOP=my_block SRC=my_block.v \
  ./run_gowin.sh build.tcl          # -> blk/impl/gwsynthesis/blk.vg (netlist)
```

For the GW5AST-138C on the Console: `-pn GW5AST-LV138PG484AC1/I0
-device_version C`.

Check timing after every build.  Gowin does **not** fail the build on
negative slack:

```sh
./timing_summary.py blinky/impl/pnr/blinky_tr_content.html
```

## Things that surprised us

* **`$readmemh` paths resolve relative to the directory of the TOP-LEVEL
  source file**, not the file containing the `$readmemh`, and not the
  directory you ran `gw_sh` from.  Keep copies of `.mem` files next to the
  top file.  Simulators resolve them relative to the run directory, so
  mismatched copies give sim/hardware differences with no error.
* **Synthesis can hang in "Tech-Mapping" on large truth-table ROMs.**  A
  microcode sequencer whose lookup ROM grew from 4K to 64K entries made
  GowinSynthesis spin for over 30 minutes (100 % CPU, 2 GB) without
  finishing; at 4K it takes 10 s.  If synthesis stalls, look for an array
  that became a huge ROM or a LUT.
* **Warnings that were actually bugs:**
  * `EX3638 ... is already implicitly declared`: a signal was used (for
    example in a port connection) before its declaration, so a 1-bit
    implicit net was created first.  See [04](04-gowin-synthesis-pitfalls.md).
  * `EX3792 Literal value 'd65536 truncated to fit in 16 bits`: the
    constant became 0.  Our "65536-cycle drain" never existed.
  * `EX2526 Entry size N ... does not match memory width M`: a `.mem`
    file's line width differs from the array.  Harmless in our case (hex
    padding), but check it.
* **`Extracting RAM for identifier 'x'` is only a candidate step.**  Whether
  an array ends up as block RAM, distributed RAM (`RAM16SDP4`) or registers
  shows only in the netlist (`impl/gwsynthesis/*.vg`).  That decides whether
  multi-write code is safe; see [04](04-gowin-synthesis-pitfalls.md).
* **`ram_style` values from other vendors** (for example Xilinx's `"ultra"`)
  are silently ignored.
* **The hierarchy is partly kept in the netlist.**  Submodules survive as
  modules, but their ports are renamed after the parent's nets (for example
  `\sl[0].aword`).  That is useful for gate-level debugging
  ([05](05-debug-methods.md)).

## Simulation primitives

For gate-level simulation of a Gowin netlist, use the vendor primitive
library `IDE/simlib/gw5a/prim_sim.v`.  With iverilog you need two tricks:

* instantiate `GSR GSR (.GSRI(1'b1));` at the top of your testbench (the
  primitives reference `GSR.GSRO` hierarchically);
* pass `-s <tb>` so iverilog doesn't elaborate every unused primitive as its
  own root.

The full recipe is in [05](05-debug-methods.md).
