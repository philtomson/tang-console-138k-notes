# Catching Gowin synthesis/simulation mismatches

Tools for the pitfalls in [docs/04](../../docs/04-gowin-synthesis-pitfalls.md).
Not every pitfall has a small reproducer: the dual-write one only appeared
inside a large design, where Gowin chose RAM for the array.  These tools find
the risky constructs in *your* design.

| Tool | Catches |
|---|---|
| `check_ram_mapping.sh <netlist.vg>` | which arrays became RAM primitives (`RAM16S*`/`RAM16SDP*`: distributed, one write port; `SDPB`/`DPB`: block RAM).  Any array you write more than once per clock should **not** be in this list. |
| `strict_elab.sh <top> <files...>` | use-before-declare (implicit 1-bit nets): iverilog refuses what Verilator and Gowin quietly accept.  Stub out vendor IP you have no source for. |
| `lut_to_case.py <file.v> <module> <in> <in_bits> <out> <out_bits>` | rewrites a small combinational module (e.g. a Yosys `64'hK >> {idx}` LUT netlist) as a bit-identical `case` table, the form that synthesized correctly for us |

Example, on the decode LUT that Gowin mis-synthesized in context:

```sh
./lut_to_case.py trit_decode_lut.v trit_decode_lut byt 8 wcode 10
# -> trit_decode_lut_case.v (256 entries, bit-identical by construction)
```

When board and simulation disagree but the block's inputs match, use the
gate-level replay in [tools/gate_replay](../../tools/gate_replay) to prove
it is a synthesis mismatch and find the first differing net.
