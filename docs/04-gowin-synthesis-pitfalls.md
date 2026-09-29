# 04 — When Gowin synthesis silently disagrees with simulation

Four times, our design behaved **differently on the board than in Verilator
simulation**, with timing met and no synthesis error.  Each time, a gate-level
simulation of the Gowin netlist reproduced the board's behaviour exactly
(method in [05](05-debug-methods.md)), which pinned the problem to how the
RTL was synthesized.  Minimal reproducers, where we have them, are in
[examples/synth_pitfalls](../examples/synth_pitfalls).

## 1. Two writes to the same array in one clock cycle → one is dropped

```verilog
reg signed [63:0] qword [0:7];
always @(posedge clk)
    if (st == S_ROPE_Q) begin
        qword[qlo_w][{qbyte,3'b000} +: 8] <= qlo_q;   // word 0..3
        qword[qhi_w][{qbyte,3'b000} +: 8] <= qhi_q;   // word 4..7
    end
```

Simulation performs both writes.  Gowin mapped `qword` to distributed RAM
(`RAM16SDP4`, **one write port**) and kept only one of them.  It gave no
warning, although the source comment even said the array was meant to be
registers.  On the board the low half of every attention query stayed 0;
results were slightly off and no check fired.

**Fix:** split the array so each part is written at most once per cycle
(`qword_lo[]`, `qword_hi[]`).  That is correct whether synthesis picks
registers or a RAM.

**It depends on context.**  The same code in a small standalone module
synthesized to plain registers, which handle two writes correctly (0
divergences in a 4,000-cycle random gate-level replay).  Only inside the
large attention engine did Gowin pick distributed RAM.  So you can't rule this
out by testing the block alone.  Check what the array became in the **full
design's** netlist:

```sh
examples/synth_pitfalls/check_ram_mapping.sh impl/gwsynthesis/<name>.vg
```

Running that over our design found a second instance of the pattern that had
not bitten yet.  A matrix-vector unit's accumulator array, written once per
slice per clock (2 writes), had become `RAM16S4` (single-port distributed
RAM).  It was harmless only because with batch size 1 the second write goes to
an unused entry.

**Rule:** never write one array twice in the same clock.  If you must, check
the full design's netlist to see what the array became.

## 2. A LUT idiom that is fine alone but wrong in context

A Yosys-generated decode table written as

```verilog
assign _00_ = 32'd259981312 >> { _04_, _01_, _03_, _02_, byt[1] };
assign wcode[7] = 64'h40ce400f4050fcc4 >> { _07_, _08_, _06_, _00_, _09_, _05_ };
// ... (each output bit = constant shifted by an index, truncated to 1 bit)
```

synthesized **correctly on its own**: an exhaustive gate-vs-RTL check was
0/256 mismatches.  Inside the ternary matrix-vector unit, where its output fed
a register with a hold mux (`if (advance) w1 <= wcode;`), Gowin folded the
register logic into the LUTs.  The netlist then decoded some weights wrongly:
sign flips and zero/non-zero swaps in specific lanes.  A gate-level replay of
that unit reproduced the board's wrong result bit for bit.

**Fix:** regenerate the table as a plain `case` statement, 256 entries
produced by exhaustively evaluating the old module, so it is bit-identical by
construction.  The netlist then matched RTL, and so did the board.

**Rule:** be suspicious of machine-generated LUT netlists (`const >> index`)
fed into vendor synthesis.  A `case` table is the safer form.

## 3. Use before declaration → implicit 1-bit nets

```verilog
DDR3_Memory_Interface_Top u_ddr3 ( ..., .addr(app_addr), .cmd_ready(cmd_ready), ... );
...
wire [28:0] app_addr;     // declared ~70 lines AFTER the instance
wire        cmd_ready;
```

Verilator quietly resolves later declarations.  Strict Verilog makes
`app_addr` an implicit 1-bit wire at its first use.  Gowin warned `EX3638
'app_addr' is already implicitly declared` and, in our case, widened it
afterwards, so it happened to work.  iverilog rejects such files outright, and
other tools may not widen.  We had nine of these across the design, including
the DDR3 read-return path (`qcount` used 80 lines before its declaration).

**Rule:** declare before use.  Run `iverilog -g2012 -o /dev/null -s top
<files>` as a strict elaboration check, and treat `EX3638` as an error.

## 4. Truncated literals

```verilog
localparam [15:0] DRAIN_CYCLES = 16'd65536;   // == 0
```

Gowin warns (`EX3792 Literal value 'd65536 truncated to fit in 16 bits`), and
the value is 0.  Our design had a "65536-cycle drain" that never existed.  It
didn't matter in the end, but it hid what we were actually running.

## 5. (Toolchain, not synthesis) A microcode-compiler trap that hangs synthesis

This one is specific to the hotwright/hotstate microcode compiler (`hotc`)
we used for control sequencers, but the synthesis symptom applies more
widely.  In hotc, `for (kg = 0; kg < N_KV - 1; ...)` has **arithmetic in a
comparator operand** (`N_KV - 1`), so the compiler can't make it a 1-bit
comparator wire.  It put `kg`'s raw bits on the truth-table address bus
instead, and the truth-table ROM grew from 4K to **64K** entries.
GowinSynthesis then spun in tech mapping for 30+ minutes.  Using a literal
bound (`#define N_KV_M1 7`) brought it back to 4K entries and 10 s.

**Rule:** if synthesis stalls, look for an array or ROM that suddenly got much
bigger.
