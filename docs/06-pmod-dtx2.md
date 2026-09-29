# 06 — PMOD-DTx2 (two-digit 7-segment) on the Console

Sipeed's PMOD-DTx2 is a two-digit, multiplexed 7-segment display.  It makes a
very readable status display: two hex digits, such as `C0` for "waiting for
calibration", `d0` for "done, 0 errors", or `E1` for "error 1".  The driver is
in [examples/pmod_dtx2](../examples/pmod_dtx2).

## Pinout (module silkscreen)

| Module pin | Signal |
|---|---|
| 1, 2 | 3V3 |
| 3, 4 | GND |
| 5 | C |
| 6 | Sel |
| 7 | B |
| 8 | A |
| 9 | E |
| 10 | D |
| 11 | F |
| 12 | G |

There's no decimal point.  **Segments are active-low**, and `Sel = 1` lights
the tens digit (Sipeed's driver: `o_sel ? tens : ones`), so you multiplex at a
few hundred Hz.

## On the Console's PMOD1

The module's pin numbering matches the Console socket numbering (see
[01](01-board-and-connection.md)), so:

| Signal | Ball |
|---|---|
| A | D22 |
| B | E22 |
| C | E21 |
| D | F20 |
| E | F19 |
| F | W19 |
| G | W20 |
| Sel | D21 |

All LVCMOS33.

**The module reads upside down on the Console.**  As mounted, the display is
rotated 180° relative to how Sipeed's font expects it to be viewed: our `d0`
first showed as `P0`.  Rotating a digit 180° swaps segments A↔D, B↔E and C↔F
(G is unchanged), so fix it in the output mapping:

```verilog
// seg_on = {G,F,E,D,C,B,A}, 1 = lit
assign pmod_seg = ~{seg_on[6], seg_on[2], seg_on[1], seg_on[0],
                    seg_on[5], seg_on[4], seg_on[3]};   // rotated, active low
```

With the rotation, the tens digit (`Sel = 1`) appears on the **left** as the
Console is normally viewed.

**Unconfigured pins show garbage.**  While a design that doesn't drive these
pins is running, the display shows random segments (for example a backwards F
and a 9), because some pins float and others are pulled up.  That isn't a
wiring fault.
