# 01 — The board, connecting to it, and pins

## Which board this is

* Sipeed **Tang Console** (the "retro console" board) with the **138K** core:
  `GW5AST-LV138PG484AC1/I0`, Gowin **device version C**.
* Our unit: PCB revision **32001C**, two DDR3 chips → a **32-bit (x32)**
  DDR3 interface.
* For DDR3, the clock input and the PLL/DDR placement, the pinout is
  **identical to Sipeed's Tang Mega 138K** examples.  We diffed Sipeed's
  `ddr3_1v4_hs.cst` pin by pin against the board and used it unchanged (see
  [03](03-ddr3-bringup.md)).
* `openFPGALoader --detect` reports `idcode 0x1081b`, manufacturer Gowin,
  family GW5AST, model GW5AST-138.

## The two USB-C ports

| Label on the board | What it is |
|---|---|
| **`MCU`** | FT2232H USB bridge: **JTAG** (for flashing) **+ a USB-UART**.  On Linux the UART is `/dev/ttyUSB1` (USB_Debugger). **Use this one.** |
| `FPGA` | Raw FPGA pins (USB OTG).  Nothing enumerates unless your design contains a USB core. |

If you plug into `FPGA` by mistake, `lsusb` shows no FTDI device (`0403:6010`)
and `openFPGALoader` fails with `unable to open ftdi device`.  One of our
sessions saw only an unrelated `1d6b:0104` "composite gadget" in that case.

## The UART wedges — replug before you debug

**Known quirk:** roughly every other time the FPGA is (re)configured, the
FT2232's UART channel stops delivering bytes.  JTAG keeps working, so
flashing succeeds, but the serial port reads silence.  **Unplugging and
replugging the `MCU` cable fixes it.**

Before concluding that your design's UART is broken, replug, reflash and
capture again.  We lost time more than once to a "dead" design that was only
a wedged bridge.

A related trap: bytes the design sent **before** you opened the port can sit
in the host buffer.  Timestamp your capture and ignore the first few hundred
milliseconds after flashing, or you will decode the previous bitstream's
output.

## Flashing

```sh
openFPGALoader -b tangmega138k design.fs      # SRAM, volatile
```

The `tangmega138k` board name works for the Console.

**If you also run the Gowin tools from the same shell:** the environment the
Gowin IDE needs (`LD_LIBRARY_PATH=.../gowin/IDE/lib`, see
[02](02-gowin-toolchain.md)) breaks openFPGALoader
(`error while loading shared libraries: libbz2.so.1`).  Run the IDE in a
subshell `( export ...; gw_sh ... )`, or `env -u LD_LIBRARY_PATH -u LD_PRELOAD
openFPGALoader ...`.  A flash that "fails" this way does not configure the
board, so the old bitstream keeps running.

## Pins we verified

Placed by Gowin P&R in our design and exercised on the board (`ball/bank`, IO
standard as placed):

| Signal | Ball / bank | Standard | Notes |
|---|---|---|---|
| 50 MHz clock in | **V22** / 4 | LVCMOS33 | `create_clock -period 20` |
| UART TX (FPGA → host, to the FT2232) | **U15** / 5 | LVCMOS33 | 115200 8N1 verified |
| UART RX (host → FPGA) | V14 / 5 | LVCMOS33 | NextTang notes this pin is shared with JTAG and the BL616; we left it unused |
| LED | **V13** / 5 | LVCMOS33 | **lit when the pin is driven HIGH** (confirmed on the board) |
| Key | F4 / 7 | LVCMOS15 | bank 7 is 1.5 V (DDR3 bank); we did not test the key |

**Bank voltages:** banks 2, 4 and 5 are 3.3 V (LVCMOS33 at VCCIO 3.3 in the pin
report).

### PMOD1

From NextTang's constraint files (facts only, see credits) and confirmed with
a PMOD-DTx2 module on the board ([06](06-pmod-dtx2.md)).  Connector pin
numbering follows the module silkscreen convention, where pins 1–2 are 3V3 and
3–4 are GND:

| Connector pin | Ball / bank |
|---|---|
| 5 | E21 / 2 |
| 6 | D21 / 2 |
| 7 | E22 / 2 |
| 8 | D22 / 2 |
| 9 | F19 / 2 |
| 10 | F20 / 2 |
| 11 | W19 / 4 |
| 12 | W20 / 4 |

W19/W20 sit in bank 4, which is 3.3 V (the 50 MHz clock input shares it).
NextTang avoided those two pins because the bank voltage was unknown to them;
we drove them at LVCMOS33 without problems.

The second PMOD socket (NextTang calls it J6/PMOD0) partly maps to V18, V19,
G21, G22, F18 and E18.  We did not verify the full pin order.

## Useful references

* Sipeed board page: <https://wiki.sipeed.com/hardware/en/tang/tang-console/retro-console.html>
* Sipeed Tang Mega 138K examples (Apache-2.0), including the DDR3 test and
  constraints: <https://github.com/sipeed/TangMega-138K-example>
* NextTang (GPL-3.0), hardware-verified Console designs:
  <https://github.com/jattree/NextTang>
