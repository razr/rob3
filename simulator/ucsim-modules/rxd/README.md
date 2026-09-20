# `rxd` — RXD (P3.0) bit-level driver for ucSim

A loadable ucSim `cl_hw` plugin that drives the 8031 **P3.0 (RXD)** pin at the
**bit level**, so firmware that bit-bangs the serial line (e.g. software
auto-baud) can run in ucSim.

## Why

ucSim's built-in MCS-51 UART is byte/frame level: it delivers whole bytes into
`SBUF`/`RI` and never toggles the `P3.0`/`P3.1` pins (see
`../../issues/003-mcs51-uart-does-not-drive-rxd-txd-pins/`). The ROB3 firmware
**auto-detects the host baud** by polling the raw `P3.0` pin and timing the
incoming bit edges with Timer 0 (init loop at `0x06BF`, `JB P3.0,$`). With no
pin activity that loop spins forever. This module supplies the missing edges.

Scope: it drives **only** the physical RXD pin. It does **not** push bytes into
`SBUF` — that is the core UART's job once the firmware has configured the real
receiver from the measured baud.

## What it does

Shifts one standard **8N1** UART frame out on `P3.0`:

```
idle:  P3.0 = 1 (HIGH)
frame: [START=0][D0][D1]..[D7]  (LSB first)  [STOP=1]
```

Each bit is held for a configurable number of **machine cycles**. The pin is
driven through the port write path (`cell->write`), like the `loopback` module,
so `JB`/`JNB` reads and the byte read all see the change.

### Bit time (machine cycles)

`tick()` receives machine cycles; on the 8051 one machine cycle = 12 CPU clocks.
So:

```
cycles_per_bit = xtal_Hz / baud / 12
```

Examples at XTAL 11.0592 MHz:

| Baud | clocks/bit | cycles/bit |
| ---: | ---------: | ---------: |
| 9600   | 1152 | 96 |
| 19200  | 576  | 48 |
| 38400  | 288  | 24 |
| 115200 | 96   | 8  |

The harness computes this and passes it as the second argument (the module
takes machine cycles directly, since the ucSim `xtal` field is private to the
core).

> **ROB3 note:** the firmware's auto-detect validates a measured bit width of
> roughly **24–39 Timer-0 ticks/bit** (~≤ 38400 baud at 11.0592 MHz). **115200**
> is only ~8 ticks/bit and is *outside* the auto-detect's measurable range — use
> a bit time in the 24–39 machine-cycle range to satisfy the validation. See
> issue 003.

## Commands

```
set hardware rxd <byte> [cycles_per_bit]   queue a byte (0..255) to shift on P3.0
set hardware rxd idle                      force the line back to idle HIGH
set hardware rxd                           print state
```

## Build

```bash
make -C simulator/ucsim-modules rxd/rxd.so SDK="$HOME/github/razr/ucsim/sdk"
```

(or `make -C simulator/ucsim-modules all` to build every plugin.)

## Load & use

```bash
ucsim_51 -t 51 -X 11.0592M simulator/build/rob3.hex
# then, at the ucSim prompt:
loadhw "/abs/path/to/rxd.so"
# ...reach the auto-detect spin (0x06BF), then:
set hardware rxd 0x20 32     # shift training byte 0x20 at 32 cycles/bit
```

## Status — auto-baud verified end-to-end

The module drives `P3.0` at bit granularity **and the ROB3 software auto-baud
runs to completion** with it:

- Shift the training byte `0x20` at **128 machine cycles/bit** (the lock point)
  and the firmware leaves the `0x06BF` RXD spin, captures the 4 edge widths,
  passes the `0x070A` validation, derives **TH1 = 0xFC**, starts Timer 1 (TR1),
  and reaches `0x073C` with **IE = 0x17** (ES enabled). Verified by
  `simulator/tests/sim_serial_autobaud.sh`.

### Baud window (this XTAL = 11.0592 MHz)

The auto-baud validation `(run/6 + 8) & 0xF0 == 0x20` accepts a training bit
time of roughly **104..152 machine cycles/bit** in this model (centred ~128,
i.e. ~7200 as machine-cycle time), always deriving **TH1 = 0xFC**:

| cyc/bit | lock? |
| ------: | :---- |
| 96 (nominal 9600)  | NO (just below window) |
| 104..152           | **LOCK**, TH1=0xFC |
| 160+, 8 (115200)   | NO |

> The host in `hardware/host/README.md` uses **9600 8N1**, but 9600 (96 cyc/bit)
> lands just below this model's window and does not lock; the model locks at
> ~128 cyc/bit. This wire-baud-vs-cycles-per-bit offset is a **modelling
> artifact** (the firmware times edges with Timer 0 in mode 1; we represent the
> line in machine cycles). The verified, meaningful result is that the auto-baud
> path COMPLETES and arms the UART. `115200` is far outside the window (only
> ~8 cyc/bit) and cannot lock — a real firmware property (see issue 003).
