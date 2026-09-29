# Sipeed Tang Console 138K — field notes

Hard-won, measured notes on the **Sipeed Tang Console** (retro console board) with
the **GW5AST-138C** core, from bringing up a DDR3-backed FPGA design (a BitNet
b1.58 inference fabric) on it with the Gowin vendor toolchain.

Everything here was found the slow way — on the real board, one variable at a
time — and each claim below is backed by a measurement described in the linked
doc.  If you are starting out with this board, the [quick facts](#quick-facts)
and the DDR3 section will likely save you days.

Board page: <https://wiki.sipeed.com/hardware/en/tang/tang-console/retro-console.html>

## Contents

| Doc | What's in it |
|---|---|
| [docs/01-board-and-connection.md](docs/01-board-and-connection.md) | Identifying the board, which USB-C port does what, the UART that wedges, flashing, pins we verified |
| [docs/02-gowin-toolchain.md](docs/02-gowin-toolchain.md) | Running the Gowin IDE headless (`gw_sh`) on Linux, environment traps, `.mem` path resolution |
| [docs/03-ddr3-bringup.md](docs/03-ddr3-bringup.md) | **Gowin DDR3 IP on this board**: clocking, constraints, handshake, the post-calibration write-loss window |
| [docs/04-gowin-synthesis-pitfalls.md](docs/04-gowin-synthesis-pitfalls.md) | Four ways Gowin synthesis silently disagrees with simulation, with evidence and fixes |
| [docs/05-debug-methods.md](docs/05-debug-methods.md) | Stage-hash debugging over UART; gate-level replay of a synthesized block against RTL |
| [docs/06-pmod-dtx2.md](docs/06-pmod-dtx2.md) | Driving the PMOD-DTx2 two-digit 7-segment module from the Console's PMOD1 |

Examples (MIT, standalone — no project-specific code):

| Example | |
|---|---|
| [examples/pmod_dtx2](examples/pmod_dtx2) | 7-segment status display driver + constraints |
| [examples/ddr3_selftest](examples/ddr3_selftest) | Minimal DDR3 bring-up / write-verify self-test with UART report |
| [examples/synth_pitfalls](examples/synth_pitfalls) | Minimal reproducers for the synthesis/simulation mismatches |
| [tools/gate_replay](tools/gate_replay) | Scripts to replay recorded inputs into RTL and a Gowin netlist and report the first divergence |

## Quick facts

* **Chip:** GW5AST-LV138PG484AC1/I0, device version **C**.  Our board: Tang
  Console, PCB rev "32001C", two DDR3 chips (x32).  The DDR3/clock pin map is
  identical to Sipeed's **Tang Mega 138K** examples.
* **Plug the USB-C cable into the port labelled `MCU`**, not `FPGA`.  `MCU` is
  the FT2232 bridge: JTAG + a USB-UART (`/dev/ttyUSB1` on Linux).  `FPGA` is raw
  pins with nothing enumerating unless your design has a USB core.
* **The UART channel wedges** after roughly every other flash: JTAG keeps
  working but the serial port delivers nothing.  Unplug/replug the `MCU` cable.
* **Flash:** `openFPGALoader -b tangmega138k design.fs` (SRAM, volatile).
* **DDR3 (Gowin DDR3 Memory Interface IP):**
  * drive the PLL output enable of the memory clock from the IP's `pll_stop`
    output — **not** a constant 1 — or calibration keeps dropping;
  * use **asynchronous clock groups** in the SDC for memory / controller /
    system clocks, or the PHY's read-path control paths are timed and fail
    and reads silently never return;
  * issue writes as a **single-cycle** `cmd_en` + `wr_data_en` when both
    `cmd_ready` and `wr_data_rdy` are high — a held `cmd_en` is accepted more
    than once;
  * **wait ≥ 21 ms after calibration before writing** (we use 42 ms): the
    controller stalls writes for ~10 ms after `init_calib_complete` and
    silently loses writes accepted as it comes out of that stall.
* **Gowin synthesis can silently differ from simulation.**  We hit four real
  cases (two writes to one array in the same cycle, a LUT idiom mangled in
  context, implicit 1-bit nets from use-before-declare, a truncated literal).
  See [docs/04](docs/04-gowin-synthesis-pitfalls.md) — and consider a
  gate-level replay ([docs/05](docs/05-debug-methods.md)) when board and sim
  disagree but every input matches.

## Credits

* Sipeed's Tang Mega 138K examples (Apache-2.0) — the DDR3 pin constraints and
  example top: <https://github.com/sipeed/TangMega-138K-example>
* NextTang (GPL-3.0) — a hardware-verified DDR3 bring-up for this board whose
  clocking/SDC choices resolved our calibration and read problems:
  <https://github.com/jattree/NextTang>.  No NextTang code is included here;
  we describe what we learned from it and link to it.

No Gowin IP is redistributed here; [docs/03](docs/03-ddr3-bringup.md) describes
how to generate the DDR3 IP.

## License

MIT — see [LICENSE](LICENSE).
