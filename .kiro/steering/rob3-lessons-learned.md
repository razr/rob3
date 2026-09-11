---
inclusion: auto
name: rob3-lessons-learned
description: ROB3-specific gotchas from firmware reverse-engineering and ucSim simulation (auto-loaded)
---

# ROB3 Lessons Learned

Project-specific pitfalls discovered while reverse-engineering the ROB3 8031
firmware and simulating it with ucSim. Keep entries short, non-obvious, and
likely to recur.

## ucSim / simulation

### The `@` in `M2764A@DIP28.HEX` crashes ucSim
ucSim (`s51` / `ucsim_51`) parses a file argument as `filename@memoryspace`. The
ROM image `firmware/hex/M2764A@DIP28.HEX` is therefore read as file `M2764A`
into a memory space named `DIP28.HEX`, which does not exist. `cl_uc::read_file`
(uc.cc) then calls `con->dd_printf(...)` on a **NULL** console (the input-file
path passes `con=NULL` from `cl_app::read_input_files`), causing a **segfault**
— symptom is "banner only, no command output" on a pipe and a core dump under a
pty. This was initially and wrongly blamed on curses; curses is unrelated.
- **Fix:** always run ucSim against an `@`-free copy, e.g.
  `cp firmware/hex/M2764A@DIP28.HEX /tmp/rob3.hex` (the sim harness/tests already
  copy to `sim/build/rob3.hex` for this reason).

### Simulated port pins idle HIGH, but the teachbox matrix idles LOW
ucSim's `cl_port` returns `cell->get() & port_pins`, and `port_pins` defaults to
`0xFF`, so P1 reads as `0xFF` when nothing drives it. The ROB3 keypad columns
(P1.5/6/7) are physically **active only when a key on the strobed row is
pressed** and otherwise idle LOW. If a peripheral model leaves them high, the
firmware scanner (`kbd_scan`, 0x0C00) sees `P1 & 0xE0 != 0` on the first row and
takes the "hit" path immediately, so the scan never advances.
- **Fix (in the teachbox `cl_hw` module):** the P1 `read()` override must drive
  the three column bits itself — clear them (idle LOW) and set only the pressed
  key's bit — rather than OR-ing onto the raw `0xFF` cell value.
  See `firmware/sim/ucsim-module/`.

## 8051 disassembly / annotation

### Byte-vs-bit operands (recurring)
`SETB` / `JB` / `CLR` operands are **bit addresses**, which can collide
numerically with byte SFR/RAM addresses. Examples hit in this project:
`SETB 0x8C` is `TCON.4 (TR0)`, not the `TH0` byte at 0x8C; `JB 0x57` is bit
`0x2A.7`, not RAM byte 0x57; likewise `0x55/0x56` in the teachbox handler are
bits of byte `0x2A`. Always resolve bit-addressed operands to their (byte, bit)
before annotating or seeding state in the simulator.

### Disassembler labels vs true entry points
The disasm51 output and some hardware docs use labels/addresses that are one
byte off the real entry (0xFF padding decoded as `MOV R7,A` shifts boundaries).
Verified truths: reset is `LJMP 0x0600` (not "jump_05FF"); the keypad scanner is
entered at **0x0C00** (0x0BFF is padding); the key handler at **0x0C80**
(0x0C7F is padding). Confirm entry addresses from the ROM bytes, not the labels.
