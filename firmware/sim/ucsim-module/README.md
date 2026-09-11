# ROB3 Teachbox — ucSim hardware module

A **compile-time ucSim peripheral** (`cl_hw` subclass) that attaches the ROB3
Teachbox key matrix to the simulated 8031, so the real firmware's keypad scanner
reads "pressed" keys from a modelled device instead of hand-injected P1 values.

This is the "attach the teachbox as an external module" approach: rather than
driving P1 via the debugger, the teachbox is a genuine simulated peripheral
built into a custom `ucsim_51`.

## Status

- **Module: works end-to-end.** Compiles, links into `ucsim_51`, registers as
  a `HW_GPIO` element, responds to `set hardware teachbox <row> <group>`, and a
  press is detected by the real firmware scanner (`kbd_scan`, 0x0C00) on the
  correct strobed row.
- **Strobe→row decode: calibrated & verified.** The firmware seeds the strobe
  from `0x47 & 0x0F` and advances the **high nibble** by `+0x10` per row
  (`no_hit: add A,#0x10`), recovering the row as `(strobe >> 4) & 7`
  (`swap A / anl A,#0x07`). So `strobed_row() = cur_strobe >> 4` is exactly the
  firmware's own row numbering. Verified in ucSim: pressing row R makes the
  scanner see the column only at strobe `0x46 == (R<<4)` for R = 0..7. Covered
  by `../tests/sim_teachbox_module.sh`.

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

## What works: key press -> axis motion

Three stages connect a Teachbox key to a robot axis moving. Each is verified;
the automated end-to-end run is `../tests/demo_teachbox_axis.sh`
(`make demo-teachbox`).

1. **Press → scanner sees it.** `set hardware teachbox <row> <group>` holds a
   key; the real firmware scanner `kbd_scan` (0x0C00) detects it on the strobed
   row that matches `<row>` (verified: hit at strobe `0x46 == row<<4`).
2. **Axis-select.** `kbd_handle` (0x0C80) turns a numeric key index into an
   axis: `R1 = 0x50+axis`, mode `0x29 = 0x40` (POSITION). (key index 2 → axis 0.)
3. **Jog.** `kh_jog` (0x0E26) with `ACC.0=0`/`1` increments/decrements the
   selected axis's position slot `@R1` (`0x50+axis`), clamped `0x00..0xFF`.

Minimal interactive drive of stage 1 (prove the press is seen):
```bash
cp firmware/hex/M2764A@DIP28.HEX /tmp/rob3.hex
printf 'set hardware teachbox 1 1\nreset\npc 0x0c00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nbreak 0x0c2a\nrun\ndump iram 0x46 0x46\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M /tmp/rob3.hex     # -> 0x46 = 0x10 (row 1)
```

> **Honest limitation — no single free-run yet.** A plain `reset; run` does
> **not** reach the scanner: init stalls at the un-modelled ADC/INT1 gate (the
> reason `make sim-run` injects an INT1/EOC stimulus), and the keypad
> **debounce** (state in `0x56`/`0x57` + flags `0x20.5/.6`) needs several
> main-loop passes that are fiddly to reproduce free-standing. The demo above
> therefore drives the three stages deterministically (`pc`/`break`) rather than
> from a free-running boot. Wiring a full free-run (inject the init gates → run
> the main loop → hold a key across debounce → observe the servo ISR drive the
> motor) is the remaining integration step.

## How reads/writes dispatch (for maintainers)

`cl_memory_cell::read()` calls **every** registered hw operator in order and
returns the **last** one's value; `add_hw` appends, so the hw registered *last*
wins. The teachbox is added after the `cl_port` for P1, so its `read()` return
is authoritative. The teachbox `read()` therefore returns the column bits
directly (idling the 3 column lines LOW), not `port_pins`-masked data.

## Status: done (verified)

The `strobed_row()` calibration is complete and verified — `row = strobe >> 4`
matches the firmware's row stepping (see the Status note above). A
`set hardware teachbox <row> <group>` press is detected by `kbd_scan` end-to-end
on the correct row, feeding `kbd_handle` (axis-select / jog) so a key sequence
can drive the modelled axis — see
`firmware/src/annotated/teachbox.annotated.asm`,
`firmware/sim/tests/sim_teachbox_module.sh` (the module end-to-end test), and
`firmware/sim/tests/sim_teachbox.sh` (the P1-injection scanner/handler test).

Possible future work (not required for the teachbox to function): drive a full
key *sequence* through the main-loop poll and assert the resulting axis motion
(ties `kbd_scan` → `kbd_handle` → `kh_jog` → servo ISR together).
