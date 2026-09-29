# 03 — DDR3 on the Tang Console with the Gowin DDR3 IP

The Console's two DDR3 chips form a 32-bit interface.  We used Gowin's **DDR3
Memory Interface** IP (`DDR3_Memory_Interface_Top`) with a 400 MHz memory
clock and a 100 MHz user clock, generated as in Sipeed's Tang Mega 138K
`ddr_memory` example.  The pin constraints are Sipeed's `ddr3_1v4_hs.cst`,
used unchanged (identical pinout on the Console).

This page lists every problem we hit, in the order we hit them, and what the
evidence showed.  **Summary of what works:**

| Item | Working setting |
|---|---|
| Memory-clock enable (PLL `enclk` of the 400 MHz output) | `enclk = !controller_rst_n \|\| pll_stop` — follow the IP's `pll_stop` output |
| SDC | the three clocks (sys / memory / controller) in **asynchronous clock groups** |
| PLL reset | never reset (`reset = 0`) |
| Controller reset | release `rst_n` a few cycles after `pll_lock` |
| Write handshake | one-cycle `cmd_en` + `wr_data_en` when **both** `cmd_ready` and `wr_data_rdy` are high |
| Read handshake | hold `cmd_en` (read command) until `cmd_ready`; one word (256 bits) comes back per command |
| Start-up | verify your initial writes; one design also needed a ≥ 21 ms wait after `init_calib_complete` (see §4) |
| Bring-up check | write a known pattern, read it back, count mismatches (see [examples/ddr3_selftest](../examples/ddr3_selftest)) |

A 256-bit user word covers 8 × 32-bit columns: the IP address is in 32-bit
units, so word *n* is at `addr = n << 3`.

## 1. Calibration keeps dropping → let `pll_stop` drive the memory-clock enable

**Symptom:** `init_calib_complete` goes high, then falls and rises again during
operation, sometimes in 60–100 % of our status samples.  The rate varied from
load to load of the *same* bitstream.  Reads accepted during a drop never
return.

**Cause:** we had held the memory clock's PLL output enable at `1`, which we
thought was a fix for an earlier symptom.  The IP's `pll_stop` *output* is
meant to gate that clock: the PHY stops the memory clock during its update
steps.  Both hardware-verified references do this: Sipeed's example
(`.enclk2(pll_stop)`) and NextTang (`!controller_reset_n || pll_stop`).

**Fix:** `enclk = !controller_reset_n || pll_stop` (the OR keeps the clock
running while the controller is in reset).  After this change,
`init_calib_complete` stayed high in every sample for as long as we watched.

## 2. Reads accepted but never returned → asynchronous clock groups in the SDC

**Symptom:** with calibration stable, the very first read after a write was
accepted (`cmd_ready`) and no `rd_data_valid` ever came back.

**Cause:** our SDC had only `create_clock` for the three clocks.  The IP's
internal controller→memory-clock paths then got timed, and they failed badly:
DQS `HOLD` / `read_rclksel` −5.8 ns, IDES8 `CALIB` −3.7 ns.  These are the
read path's control signals.  NextTang's verified SDC puts memory, controller
and system clocks in separate asynchronous groups (Sipeed's uses `-exclusive`),
and its timing report has none of those paths.

**Fix:**

```tcl
create_clock -name sys_clk          -period 20.000 [get_ports {clk}]
create_clock -name memory_clock     -period 2.500  [get_nets {memory_clk}]
create_clock -name controller_clock -period 10.000 [get_pins {u_ddr3/gw3_top/u_ddr_phy_top/fclkdiv/CLKOUT}]
set_clock_groups -asynchronous -group [get_clocks {memory_clock}] \
    -group [get_clocks {controller_clock}] -group [get_clocks {sys_clk}]
```

(Gowin's SDC parser may reject `\` line continuations.  Keep each command on
one physical line if it complains.)

Reads then returned immediately and continuously.  **Note:** an older note in
our project claimed "clock groups make calibration retrain forever".  That was
measured while problem 1 was still present, so don't let it scare you off.

## 3. Writes: pulse, don't hold

**Symptom:** a MIG-style held `cmd_en` (hold until `cmd_ready`) while waiting
for `wr_data_rdy` made the controller **accept the same write command
several times**: we measured 10 command accepts for 1 data accept.  The
duplicate commands then starve waiting for data and block every read behind
them.

**Fix:** assert `cmd_en` (with `cmd = 000`) and `wr_data_en` together, for
exactly one cycle, only when `cmd_ready && wr_data_rdy` are **both already
high**.  This is also what NextTang's verified adapter does.  We also tried
"two independent held latches" (hold `cmd_en` until `cmd_ready`, hold
`wr_data_en` until `wr_data_rdy`); it froze the interface on hardware.
`wr_data_end = 1` and `wr_data_mask = 0` (all bytes enabled).

## 4. A post-calibration write-loss window, seen in one design and not another

**What we saw in the BitNet design.**  A design that wrote an initial memory
image right after calibration later read some of it back **wrong**.  Nothing
flagged it: calibration looked fine, every command was accepted, and later
writes were fine.  We preloaded 1152 words with an address-derived pattern,
read them all back and compared, and timestamped every write (100 MHz
controller cycles since our `calib_done`, which trailed the IP's first
`init_calib_complete` by ~2.6 ms):

| Wait after `calib_done` before the first write | Lost words | What the timestamps showed |
|---|---|---|
| 0 | 12 of 1152 (last bad: word 336) | first write accepted at t≈0, then **no write accepted for ~10.5 ms**, then the rest |
| 10.5 ms | the **same** 12 words | writes ran at ~96 cycles/word, starting at 10.5 ms |
| **21 ms** | **0** | writes ran at **2.1 cycles/word** |
| 42 ms | 0 | (what that design ships with) |

The pattern was deterministic across runs.  Letting other traffic interleave
with the early writes made it much worse (349 lost).

**What we did NOT see in a minimal design.**  Our minimal self-test
([examples/ddr3_selftest](../examples/ddr3_selftest)) uses the same IP,
constraints, clocking and handshake.  It lost **nothing**, and saw **no
stall**, with:

* 2048 back-to-back writes starting immediately after calibration
  (`DELAY=0`): all accepted in ~2,300 cycles, 0 errors;
* 2048 writes paced 4,096 cycles apart (`PACE=4096`), spanning 0–84 ms after
  calibration: every write accepted on its slot, 0 errors.

So this is **not** simply "the controller drops writes N ms after
calibration".  Something in the larger design's interaction with the
controller triggers it.  We have not found the root cause.

**What to do about it:**

* **Verify what you write**, at least at bring-up.  Write an address-derived
  pattern, read it back, count mismatches.  This check is what exposed the
  loss; nothing else did.
* A **~20–40 ms wait after `init_calib_complete`** before any traffic fixed
  it in the design where it occurred, and costs nothing at boot.
* Block **all** other traffic until your initial writes and their
  verification are done.

**Also:** make `init_calib_complete` "sticky" in your logic (latch it once
seen); it can toggle during init.  Synchronize it into your fabric clock
domain before using it.

## 5. The first read after calibration

Early in bring-up, the first read command after calibration was accepted and
never returned.  We worked around it with a "primer": write word 0, then read
it back and discard the result before any real traffic.  That period also had
problems 1 and 2 in play, so this may have been a symptom of those rather than
a real controller property.  The primer is cheap, so we kept it.  It also
serves as the verify pass for the preload self-test.

## 6. Throughput notes

* One read command returns one 256-bit word (two 128-bit beats).  The
  controller accepts back-to-back reads (Sipeed's `ddrtest.v` streams them).
  Our design used one outstanding read at a time and, with problems 1–4 fixed,
  still ran within ~1 % of an ideal memory for our compute-bound workload.
* After the post-calibration window, back-to-back writes ran at ~2 cycles per
  256-bit word.
* A per-command "drain" delay after writes was **not** needed.  The 1152-word
  back-to-back preload verifies clean with no gap.

## Generating the IP

Gowin IP isn't redistributable, so it isn't in this repo.  Generate the **DDR3
Memory Interface** in the Gowin IDE IP core generator for the GW5AST-138C,
with the settings from Sipeed's Tang Mega 138K `ddr_memory` example
(DDR3, x32, 400 MHz memory clock, 4:1 → 100 MHz user clock).  Or copy the
generated IP directory from that example.  Use that example's
`ddr3_1v4_hs.cst` for the DDR3 pins.  We needed no pin changes for the Console.
