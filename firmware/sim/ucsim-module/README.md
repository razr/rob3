# ROB3 Teachbox — ucSim hardware module

A **compile-time ucSim peripheral** (`cl_hw` subclass) that attaches the ROB3
Teachbox key matrix to the simulated 8031, so the real firmware's keypad scanner
reads "pressed" keys from a modelled device instead of hand-injected P1 values.

This is the "attach the teachbox as an external module" approach: rather than
driving P1 via the debugger, the teachbox is a genuine simulated peripheral
built into a custom `ucsim_51`.

## Status

- **Module: works structurally.** Compiles, links into `ucsim_51`, registers as
  a `HW_GPIO` element, and responds to `set hardware teachbox <row> <group>`
  (prints a confirmation).
- **Open item: strobe→row calibration.** The module still needs its
  `strobed_row()` decode calibrated to the exact values the firmware writes to
  the 8255 Port B strobe (XRAM `0x5100`). Until then a press is not yet matched
  to the correct scanned row end-to-end. See "Open work" below.

## Files

| File | Purpose |
| :--- | :------ |
| `teachbox.cc`   | The `cl_teachbox` peripheral implementation. |
| `teachboxcl.h`  | Its class declaration. |

## What it models

The Teachbox is a 5x5 key matrix on the DB25. The firmware scans it by driving a
row strobe through the 8255 (Port B, XRAM `0x5100`) into a 74LS138, and reading
the column returns on **P1 (SFR `0x90`)**, top 3 bits = the three column groups
(group 1 = P1.5, group 2 = P1.6, group 3 = P1.7). See `hardware/teachbox/`.

The module:
- registers the **P1 SFR cell**: on read it drives the column-group bit for the
  pressed key **iff** the strobed row matches (columns idle LOW, so the scan can
  proceed when nothing is pressed);
- registers the **XRAM `0x5100`** cell (8255 Port B): on write it captures the
  row strobe so it knows which row is active.

Pressed key is set from the sim command line:

```
set hardware teachbox <row> <group>   # row 0..7, group 1..3
set hardware teachbox <n>             # single arg = release
```

## Building a custom ucsim_51 with this module

Requires the ucSim source (this project was developed against Daniel Drotos'
ucSim **0.9.9**, e.g. a checkout at `~/github/danieldrotos/ucsim`).

1. Copy the two files into the 8051 sim source:
   ```bash
   cp teachbox.cc teachboxcl.h  <ucsim>/src/sims/s51.src/
   ```
2. Add the object to the build — in `src/sims/s51.src/objs.mk`, append
   `teachbox.o` to the `OBJECTS` list.
3. Register the hw — in `src/sims/s51.src/uc51.cc`:
   - add the include near the other hw includes:
     ```cpp
     #include "teachboxcl.h"
     ```
   - at the end of `cl_51core::mk_hw_elements()` (after the interrupt hw):
     ```cpp
     { class cl_hw *tb = new cl_teachbox(this); add_hw(tb); tb->init(); }
     ```
4. Configure and build:
   ```bash
   cd <ucsim> && ./configure && make -C src/sims/s51.src
   ```
   Produces `src/sims/s51.src/ucsim_51`.

## Running (important gotchas learned)

- **Filename must not contain `@`.** ucSim parses `name@memory` as a
  file-into-memory spec, so `M2764A@DIP28.HEX` makes it try to load into a
  bogus memory space and **segfaults** (null console in `cl_uc::read_file`).
  Use an `@`-free copy, e.g. `cp hex/M2764A@DIP28.HEX /tmp/rob3.hex`.
  (This was the real cause of the "no output / crash", NOT curses.)
- **Curses is a non-issue.** A curses-linked build and a no-curses build behave
  the same for scripted stdin once the `@` filename is fixed.

Example:
```bash
cp firmware/hex/M2764A@DIP28.HEX /tmp/rob3.hex
printf 'set hardware teachbox 0 1\nreset\npc 0x0c00\n...\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M /tmp/rob3.hex
```

## How reads/writes dispatch (for maintainers)

`cl_memory_cell::read()` calls **every** registered hw operator in order and
returns the **last** one's value; `add_hw` appends, so the hw registered *last*
wins. The teachbox is added after the `cl_port` for P1, so its `read()` return
is authoritative. The teachbox `read()` therefore returns the column bits
directly (idling the 3 column lines LOW), not `port_pins`-masked data.

## Open work

Calibrate `strobed_row()`:
1. Capture the exact byte the firmware writes to XRAM `0x5100` at each row
   iteration of `kbd_scan` (break at the strobe write `0x0C0C`, read `ACC`).
2. Map those strobe values to matrix rows 0..7.
3. Update `cl_teachbox::strobed_row()` accordingly (currently assumes
   `row = strobe >> 4`, which does not match the observed `0x5100` values).

Once calibrated, a `set hardware teachbox <row> <group>` press will be detected
by `kbd_scan` end-to-end, feeding `kbd_handle` (axis-select / jog) so a key
sequence drives the modelled axis — see `firmware/src/teachbox.annotated.asm`
and `firmware/sim/tests/sim_teachbox.sh`.
