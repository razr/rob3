# ROB3 loopback module (`cl_loopback`)

> **Not a data loopback.** Despite the name, this module does **not** echo
> TX→RX (P3.0/RXD). It reproduces only the *gate side-effect* of the ROB3
> "9-pin shorting connector": forcing **P3.2** (EMERGENCY-OFF) and **P3.4**
> (poll enable) to the level that lets the ROM reach `tb_poll`. Modelling a
> real serial loopback would be incorrect here (the blocking gates are P3.2/
> P3.4, not P3.0). Full electrical trace and the open "why is the connector
> required" question:
> [`../../../hardware/connectors/rs232-shorting-connector.md`](../../../hardware/connectors/rs232-shorting-connector.md).

Models the pin-level effect of the **RS-232 shorting connector** that the ROB3
requires to run (hardware/teachbox/README.md, "Hardware requirements"). On the
real board, **MM74C04N #1** (hardware/board/MM74C04N.md) conditions these 8031
Port-3 inputs the firmware cares about:

| Pin | 8031 | Source on the board | Driven by this module? |
| :-- | :--- | :------------------ | :--------------------- |
| P3.2 | INT0 | **DB25 pin 4 EMERGENCY-OFF** (STOP path), active LOW | yes — forced HIGH |
| P3.4 | T0   | **DB9 pin 4** teach-poll enable gate | yes — forced HIGH |
| P3.0 | RXD  | DB9 pin 2 serial / baud strap | **no — left alone** |

Note P3.2 is set on the real board by the **DB25 STOP path**, not by the RS-232
(DB9) connector; the module forces it HIGH anyway so the sim can run without a
STOP model. The exact DB9 strap the real shorting connector uses (and its
polarity) is **unresolved** — see
[`../../../hardware/connectors/rs232-shorting-connector.md`](../../../hardware/connectors/rs232-shorting-connector.md).
This module is a **simulation aid** that forces the correct 8031-pin end state,
not a wiring-accurate model of the connector.

With those gates HIGH the firmware (1) leaves the EMERGENCY-OFF handler at
`0x0040`, and (2) passes the `JB P3.4, tb_poll` gate at `0x07AB` and actually
scans the keypad.

## Why it's needed in ucSim

An **undriven input pin reads LOW** in ucSim, so without help the ROM sees a
permanent emergency-off: INT0 (level-triggered, enabled via `IE=0x17`) keeps
vectoring to `0x0040`, whose `JNB P3.2, 0x0052` spin never falls through, and
the main-loop teachbox poll (`tb_poll`, `0x07C4`) is never reached. See the
"THREE GATES" note on the main loop in
`firmware/src/annotated/main.asm` and the `rob3-lessons-learned`
entry.

## What it does

Attaches to Port 3 and holds the conditioned input pins HIGH:

- Registers the **P3 byte cell** (`0xB0`) and the **bits-space cells** for
  P3.2 (`0xB2`) and P3.4 (`0xB4`); `read()` returns those pins HIGH so the
  firmware's `JB`/`JNB` bit reads and the byte read `sfr->read(P3)` see them
  set.
- On every `tick()`, writes the P3 latch bits HIGH **through the cell**
  (dispatching to `cl_port::write`), so the port fires `EV_PORT_CHANGED` and the
  interrupt controller re-samples `bit_INT0 = (pins & value)` — this is what
  actually stops the level-triggered INT0 from re-firing. (A read-only operator
  or a silent `cell->set()` is **not** enough: the interrupt controller tracks
  INT0 from port-change events, not from a cell read.)

P3.0 is deliberately **left alone** so the harness can still select the
fixed-baud path (`P3.0 = 0`).

## Commands

```
set hardware loopback on          # enable (default)
set hardware loopback off         # disable (bare board, emergency-off asserted)
set hardware loopback <maskbyte>  # choose which P3 bits to force HIGH (default 0x14)
info hardware loopback            # show state
```

## Verified

- With the module built in, from a plain `reset; run`, the ROM **escapes the
  emergency-off handler** and the main loop **reaches `tb_poll` (0x07C4)** — the
  keypad scanner runs. [SIM]
- The existing `make sim-teachbox-module` test still passes (no regression to
  the teachbox/adc modules). [SIM]

## Known limitation

Reaching the scanner is necessary but not sufficient to dispatch a key: the
keypad **debounce** (kbd_scan, `0x0C00`) still requires a key to be *held* the
right way across scan passes before `kbd_handle` (`0x0C80`) is called. That is a
firmware-timing characterization, separate from this module. See the main-loop
"GATE 4" note in the annotated disassembly.

## Build / load

Built as a loadable plugin against the ucSim SDK (see `../README.md` for
details). In this checkout the SDK is the in-tree one at
`~/github/razr/ucsim/sdk` (not installed to `/usr/local`), so pass `SDK=`:

```bash
cd ..                 # simulator/ucsim-modules/
make SDK="$HOME/github/razr/ucsim/sdk"      # -> loopback/loopback.so
# (or `make` alone if the SDK is installed under /usr/local)

# then in ucsim_51:
#   loadhw "loopback/loopback.so"
#   set hardware loopback on
```
