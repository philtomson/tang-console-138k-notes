# PMOD-DTx2 driver and demo

`pmod_dtx2.v` shows an 8-bit value as two hex digits on Sipeed's PMOD-DTx2 module.
`top.v` is a demo that counts 00..FF (about 4 counts per second) and blinks the LED.

Plug the module into the Console's **PMOD1**, matching pins 1–2 (3V3) and 3–4 (GND)
to the socket, then:

```sh
cd examples/pmod_dtx2
NAME=pmoddemo TOP=top SRC=top.v:pmod_dtx2.v:pins.cst:timing.sdc \
  ../../tools/gowin_build/run_gowin.sh ../../tools/gowin_build/build.tcl
openFPGALoader -b tangmega138k pmoddemo/impl/pnr/pmoddemo.fs
```

If the digits read upside down on your setup, set `ROTATE180=0`.
See [docs/06](../../docs/06-pmod-dtx2.md) for the pinout and why the rotation is needed.
