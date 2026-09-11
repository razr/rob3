# Session: ROB3 — Hardware doc consistency, Arduino bring-ups, teachbox annotation & ucSim module

**Date:** 2026-09-11
**Task:** A wide-ranging session: review/repair the newly-added hardware
schematic docs for consistency, convert the hardware "test" writeups into real
Arduino projects, extend the firmware annotation into the teachbox path (with
tests), and stand up a way to "attach the teachbox to the simulator" — which
led to building a real ucSim hardware module.

Working method throughout: **verify against the ROM/simulator/hardware before
asserting**; keep unverified claims tagged and separate; commit in small, honest
steps; never push.

## What was done

### 1. Hardware schematic docs (`hardware/board/*.md`)
Cross-checked every IC's "Board connections" for reciprocity and naming.
- Fixed broken/misnamed links and standardized the address latch as **74HC373**
  (interleaved D/Q pinout) — the earlier "74HC573" was wrong; the D-inputs vs
  Q-outputs anomaly disappears under the 373 pinout. (User confirmed it's a 373.)
- Fixed `74HC138`→`74LS138`, 8255 pin 6 (/CS) → 74LS138 (not 74LS244), 8255
  pin 21 → 74LS244 pin 15, and completed the 8031 reciprocal nets in Notes.
- Identified the unmarked ADC (markings scratched off) as **ADC0808/0809** from
  the ringed-out connections + firmware behaviour (EOC→INT1, DPH 0x58/0x59,
  `anl A,#07h` = 8 channels), confirmed against `main.asm`.
- Documented the **74LS138 decode logic**: B=A11, C=A12; input A tied to Y4 as a
  self-latch; A14/A15 gate peripheral vs SRAM. Built the DPH→device table.

### 2. Reverse-engineering docs corrected (`docs/*.md`)
Reconciled `reverse_engineering_notes.md` / `8031_sfr_map.md` / `8255_mapping.md`
/ `axis_state_machine.md` with the verified ROM + hardware: reset vector 0x0600
(not jump_05FF), real ISR targets, Timer0 reload TL0=0x11/TH0=0xE8, serial ISR
at 0x0300, and **DC servo via L293 + potentiometric feedback via ADC** (not
steppers/encoders).

### 3. Teachbox & connectors docs
- `hardware/teachbox/board.md`: fixed the LED-decoder A0/A2 DB25 pins (23/22, per
  the working `test.md` bring-up) and the scanner column-read path (P1/0x90, not
  8255 Port B).
- `hardware/connectors/db25.md`: fixed DO2→74LS244 pin 18; clarified STOP/legend.
  `rs232.md`: clarified DB9 pin 2/3 directions (paths already matched the parts).

### 4. Motors docs
`bueler-motor.md`: corrected to **3 populated L293s / 6 motors** (the 4th
footprint is unpopulated, per user), Port A+C drive, enables tied to VCC; added
`motors/README.md`.

### 5. Real Arduino bring-up projects (from the `test.md` writeups)
- `hardware/teachbox/arduino/` — `led_test` + `keypad_test` sketches, shared
  pin header, `host/monitor.py`, README + full INSTALL.md (arduino-cli/IDE).
- `hardware/motors/arduino/` — `pot_reader` + `motor_control` sketches (with the
  per-axis ADC calibration from test.md), host console, README.
- Both syntax-checked (g++ `-fsyntax-only` with Arduino stubs; `py_compile`).
  NOT compiled with the real Arduino toolchain (not installed here).

### 6. Firmware annotation extended + tests (`firmware/`)
- `src/teachbox.annotated.asm` — the **keypad scanner** `kbd_scan` (entry
  0x0C00), the **axis-select** POSITION path (key index N → axis N-2, R1=0x50+
  axis, mode 0x29=0x40), and the **axis jog** `kh_jog` (0x0E26: +/- inc/dec the
  axis position with 0x00/0xFF clamp, then arm motion). All [BYTE]/[SIM]-verified.
- Golden byte-match + behavioral tests added to the Makefile:
  `make test` → **ALL TESTS PASSED (23 assertions)** on SDCC 4.2.0 / ucSim 0.8.5.
- Fixed annotation mislabels found via the sim: TH0/TH1, TL0/TL1, SETB TR0
  byte-vs-bit.

### 7. "Attach the teachbox to the simulator" → a real ucSim module
- Built ucSim **0.9.9 from source** (`~/github/danieldrotos/ucsim`) and wrote a
  `cl_teachbox` (`cl_hw`) peripheral hooking P1 + the 8255 Port B strobe; command
  `set hardware teachbox <row> <group>`. Compiles, links into `ucsim_51`,
  registers as HW, and responds. Saved to `firmware/sim/ucsim-module/` with a
  build README (it needs the ucSim source tree, so it is a manual build).

## Key findings / gotchas (now in `.kiro/steering/rob3-lessons-learned.md`)
- **`@` in `M2764A@DIP28.HEX` crashes ucSim** (parsed as file@memory → null
  console segfault). Use an `@`-free copy. Curses was wrongly blamed.
- **ucSim ports idle HIGH; the keypad columns idle LOW** — the teachbox `read()`
  must drive the column bits itself, else the scanner sees a phantom row-0 hit.
- **Byte-vs-bit operands** (SETB 0x8C=TR0, JB 0x57=0x2A.7) — a recurring trap.
- **Disassembler labels are one byte off** true entries (reset 0x0600, scanner
  0x0C00, handler 0x0C80); confirm from ROM bytes.

## Open items (next session)
- **Teachbox ucSim module: calibrate `strobed_row()`** to the firmware's actual
  8255 Port B (0x5100) strobe bytes, so a `set hardware teachbox R G` press is
  detected by `kbd_scan` end-to-end → feeds axis-select/jog → "type keys, watch
  the axis move." This is the last piece; module infrastructure is done.
- **Closed-loop servo sim** (approach 1): run the servo ISR (0x00C0) in real
  firmware context with XRAM-modelled ADC feedback (0x5800/0x5900) and motor
  capture (0x5000/0x5200). The ISR is stateful across invocations; needs the
  natural INT1 trigger working. XRAM peripheral-model plumbing is verified.
- Annotate the POS-digit entry (`POS a . n`, encoded accumulator via 0x0FC4) and
  the servo/accel-decel algorithm; add matching tests.
- `hardware/motors/nmm-motor.md` is still a stub (needs part info).
- `hardware/connectors/6pin-idc.md` Connectors 3–6 are stubs.
- Local `main` is ahead of `origin/main` (not pushed).

## Provenance
Every firmware claim carries [BYTE] (ROM-verified), [SIM] (simulator-verified),
[HW] (hardware-doc-confirmed) or [INFER] (unproven). Hardware-doc fixes were
cross-checked between reciprocal IC files and, where possible, the firmware.
