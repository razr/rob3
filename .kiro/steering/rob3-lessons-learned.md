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
  See `simulator/ucsim-modules/teachbox/`.

### `run N` does NOT stop after N cycles — use `step N` for bounded advance
In this ucSim build (`s51` / `ucsim_51`), `run <N>` **free-runs until
interrupted** and ignores the count — it does not stop after N cycles. A harness
that issues `run 8000` per key therefore blocks for the whole read timeout
(~20 s/key). `step <N>` is the primitive that reliably advances a bounded number
of instructions and returns immediately (reason `(109) resSTEP`,
"stepped … ticks"), even while the ADC/INT1 servo ISR is running (~4.5 ms for
8000). Symptom of the bug: the first key after reset is fast (CPU idle at the
main loop), but every key after a jog/target-set stalls for ~20 s.
- **Fix:** use `step N`, not `run N`, for a bounded burst. See
  `UCSimEngine.run_cycles` in `simulator/harness/gui/engine.py`.

### Never pipeline a command after a `run`/`step` in one console write
ucSim **freezes** the console while a `run`/`step` executes. If the next command
is already sitting in the console input buffer (e.g. you wrote
`"step 8000\nset hardware …\n"` in a single `os.write`), the arriving line is
treated as a **user interrupt**: `cl_console_base::proc_input` (newcmd.cc) sees
input-available on the frozen console, calls `sim->stop(resUSER)`, and the
pipelined line is consumed by `read_line()` **without being executed** (see also
the `resUSER` input-drain at sim.cc ~L258). Net effect: the following command is
silently swallowed, so a batch/sentinel read waits forever and hits the timeout.
- **Fix:** send anything involving a run/step as **one command per write** —
  write `set hardware teachbox …`, then `step N` **alone**, then the release,
  as three separate `os.write`s. Batching a single write is only safe when
  there is **no** run/step in it (e.g. the six `set hardware adc` pot pushes in
  `UCSimEngine.push_pots`, which are all immediate and cannot be interrupted).

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

## Provenance tagging (always)

Tag every firmware claim with how it was established, and keep unproven claims
separate from verified ones:

- **[BYTE]** — verified from the ROM bytes (byte-exact / golden match).
- **[SIM]** — verified by running the ROM in ucSim and observing state.
- **[HW]** — confirmed against a hardware doc or a bench (Arduino) bring-up.
- **[INFER]** — hypothesis, not yet proven. Never state as fact.

If you can't tag it, you haven't verified it. This applies to annotations,
docs, commit messages, and session notes alike. Verify against the
ROM/simulator/hardware **before** asserting; commit in small, honest steps.
See the `rob3-firmware-map` skill for the domain map this convention annotates.
