# Issue 003 — MCS-51 UART does not drive the RXD/TXD pins (bit level)

**Component:** `src/sims/s51.src/serial.cc` (`cl_serial`), the MCS-51 UART model
**ucSim:** 0.9.9
**Type:** modeling limitation (not a crash / not a wrong-result bug)

## Summary

ucSim's 8051 UART is modeled at the **byte/frame level**: on receive it waits a
frame-time (derived from the CPU clock and the UART registers), then delivers a
whole byte straight into `SBUF` and sets `RI`; on transmit it writes the whole
byte out when the frame completes. It **never drives the physical `P3.0` (RXD)
or `P3.1` (TXD) pins.**

For ordinary firmware that uses the UART through `SBUF`/`RI`/`TI`, this is the
correct and efficient abstraction. But firmware that treats the RXD pin as a
**raw GPIO** — e.g. software **auto-baud** that times the incoming start/data
bit edges by polling the pin — has nothing to observe, because the pin never
moves.

## Where it bites (ROB3)

The ROB3 8031 firmware auto-detects the host baud rate before enabling the UART.
Its init path samples `P3.0` HIGH and enters a measure loop that polls the raw
`P3.0` pin and times edges with Timer 0:

```
0x06BF:  JB  P3.0, 0x06BF     ; spin until the RXD start bit (P3.0 -> LOW)
         ...                  ; capture 4 edge widths (TL0/TH0) into a buffer,
                              ; validate the pattern, derive TH1 = ~(width-1),
                              ; start Timer 1 (TR1), then MOV IE,#0x17 (ES on)
```

In stock ucSim the UART never toggles `P3.0`, so this loop spins forever and the
firmware can **never leave auto-detect** — the entire serial subsystem is
unreachable in simulation. (The alternative fixed-baud strap path, `P3.0`=0,
sets `IE=0x07` with **no ES bit** and never starts Timer 1, so it does not run
the receiver either — verified `[BYTE]`+`[SIM]`. So auto-detect is the *only*
serial path, and it is exactly the one that needs pin-level RXD.)

## Root cause (source)

`cl_serial` in `src/sims/s51.src/serial.cc`:

- `read(cell)` for the SBUF cell returns the internal `s_in`; `write(cell)` to
  SBUF sets `s_out`. Neither is the SBUF SFR cell, and neither touches `P3`.
- `tick()` accumulates cycles and, once a frame time elapses, pulls the next
  input char into `s_in`/`SBUF` and calls `received()` (sets `RI`). There is
  **no code that references `P3`, a port pin, or `cell_in`** — a grep for
  `P3|pin|RXD|port_pin` in `serial.cc` returns nothing.

So the model has no notion of the serial lines as pins.

## Impact / severity

- Low for typical firmware (SBUF/RI/TI works fine).
- Blocking for firmware that **bit-bangs** or **auto-bauds** off the raw RXD
  pin. Such code cannot be simulated at all.

## Reproduction

`repro.sh` (in this folder) loads the ROB3 ROM, forces the auto-detect path
(`P3.0`=1), and shows execution stuck at the `0x06BF` RXD-spin after a large
`step`, with `IE` never reaching `0x17`. (Needs the ROB3 `adc` `cl_hw` module so
init reaches the baud branch; both are in `simulator/ucsim-modules/`.)

## Two ways to address it

1. **A `cl_hw` plugin that drives the RXD pin** (the approach taken here).
   `simulator/ucsim-modules/rxd/` shifts one 8N1 frame out on `P3.0` at a
   configurable bit time, synchronized to CPU cycles, through the port write
   path. This supplies the missing pin activity without touching ucSim core.
   Status: **verified end-to-end** — with this module the ROB3 auto-baud runs
   to completion (leaves the 0x06BF spin, validates, derives TH1=0xFC, starts
   Timer 1, IE=0x17). See `simulator/tests/sim_serial_autobaud.sh` and the
   module README for the accepted training-bit-time window.

2. **Core enhancement:** optionally have `cl_serial` toggle the RXD/TXD port
   pins during reception/transmission at the modeled bit rate (guarded by a
   config var so normal byte-level use is unaffected). This would let auto-baud
   firmware run against the built-in UART directly.

## Note (separate ROB3 finding, not a ucSim issue)

ROB3's auto-detect validates the measured bit width to roughly **24–39 Timer-0
ticks per bit** (the `A/6 + 8 & 0xF0 == 0x20` checks at `0x070A`). At
11.0592 MHz that corresponds to about **≤ 38400 baud**; **115200** is only ~8
timer ticks/bit and is **out of the auto-detect's measurable range**. This is a
firmware property, independent of the ucSim limitation above.
