# DDR3 self-test

A minimal, standalone DDR3 bring-up for the Tang Console 138K.  It writes an
address-derived pattern with the Gowin DDR3 IP, reads it all back, and
reports the result over the UART and on an optional PMOD-DTx2.  It uses the
settings verified in [docs/03](../../docs/03-ddr3-bringup.md): the memory-clock
enable follows `pll_stop`, asynchronous clock groups, and one-cycle writes.

On our board, flashed from these exact files:

```
DDR3 N=0800 ERR=0000 FIRST=0000 LAST=0000 TW0=00000002 TW1=000008E5
```

That is 2048 × 256-bit words (64 KiB), 0 errors, with all writes done ~23 µs
after calibration (`TW*` are 100 MHz controller cycles since
`init_calib_complete`).

## What you need (not included)

Gowin IP can't be redistributed.  From Sipeed's
[Tang Mega 138K examples](https://github.com/sipeed/TangMega-138K-example)
`ddr_memory` project (or regenerate it in the Gowin IDE with the same
settings):

* the **DDR3 Memory Interface** IP: `ddr3_memory_interface/ddr3_memory_interface.v`
  (module `DDR3_Memory_Interface_Top`; DDR3, x32, 400 MHz memory clock,
  100 MHz user clock);
* the **PLL** IP: `gowin_pll/gowin_pll.v`, `gowin_pll_mod.v`, `pll_init.v`
  (module `Gowin_PLL`, `clkout2` = the 400 MHz memory clock);
* the pin constraints: `ddr3_1v4_hs.cst`, used unchanged (the Console's pinout
  matches the Mega's).

Port and instance names in `ddr3_selftest.v` match that `.cst` (`clk`,
`uart_tx`, `led_V13`, `ddr_*`, `Gowin_PLL_inst`, `u_ddr3`).  Gowin wants a
single constraints file, so append `pmod1.cst` if you use a display:

```sh
cat /path/to/sipeed/ddr3_1v4_hs.cst pmod1.cst > board.cst
```

## Build and run

```sh
IP=/path/to/sipeed/example/src
SRC=ddr3_selftest.v:../pmod_dtx2/pmod_dtx2.v:$IP/ddr3_memory_interface/ddr3_memory_interface.v:\
$IP/gowin_pll/gowin_pll.v:$IP/gowin_pll/gowin_pll_mod.v:$IP/gowin_pll/pll_init.v:board.cst:timing.sdc
NAME=selftest TOP=ddr3_selftest SRC=$SRC \
  ../../tools/gowin_build/run_gowin.sh ../../tools/gowin_build/build.tcl
openFPGALoader -b tangmega138k selftest/impl/pnr/selftest.fs
python3 -m serial.tools.miniterm /dev/ttyUSB1 115200
```

The report line repeats every ~0.7 s.  The first few lines you see may be
backlog from the FT2232's buffer.  If you see nothing, replug the `MCU` cable
(see [docs/01](../../docs/01-board-and-connection.md)).

| Field | Meaning |
|---|---|
| `N` | words tested (hex) |
| `ERR` | mismatching words |
| `FIRST`, `LAST` | first / last mismatching word index |
| `TW0`, `TW1` | controller cycles from calibration to the first / last write |

PMOD-DTx2 codes: `C0` waiting for calibration, `C1` post-calibration wait,
`A1` writing, `A2` reading, `d0` pass, `E1` fail.  LED: slow blink while
running, steady on for pass, fast blink for fail.

## Parameters

| Parameter | Default | |
|---|---|---|
| `N_WORDS` | 2048 | words to test (up to 65535) |
| `DELAY` | 0 | extra controller cycles to wait after calibration before writing |
| `PACE` | 0 | extra cycles between writes.  With `PACE > 0`, bad word *n* was written ≈ `TW0 + n·(PACE+1)` cycles after calibration, which maps any loss window in time |

We used `DELAY=0, PACE=4096` (writes spread over 0–84 ms after calibration) to
look for the post-calibration write loss that one of our larger designs
showed.  This minimal design showed none (docs/03 §4).
