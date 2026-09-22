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
- **Upstream:** filed as ucSim issue
  [#13](https://github.com/danieldrotos/ucsim/issues/13) (submitted + closed);
  local write-up at `simulator/issues/002-segfault-on-at-in-filename/`.

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
- **Reported:** reproducible write-up + patch at
  `simulator/issues/001-pipelined-command-discarded-on-resuser/` (confirmed bug,
  prepared for upstream submission).

### P3.2 idles LOW in ucSim → firmware sits in the EMERGENCY-OFF handler forever
INT0 (8031 pin 12 = P3.2) is wired to the active-LOW EMERGENCY-OFF line, is
**enabled** (init sets `IE=0x17`) and **level-triggered** (`TCON.IT0=0`). Its
handler (0x0003 → `LJMP 0x0040`) cuts both motor 8255 ports and then **spins at
`0x0054: JNB P3.2, 0x0052`** until P3.2 goes HIGH. In ucSim an undriven pin
reads LOW, so the firmware sees a permanent emergency-off: INT0 re-fires, the
handler never falls through, and execution **never reaches the main-loop
teachbox poll (`tb_poll`, 0x07C4)** — so no keypress is ever scanned/handled.
Symptom: press keys via `set hardware teachbox …`, hold them as long as you
like, and no IRAM slot (0x50+axis) ever changes; a PC trace from 0x074D goes
straight into 0x0003 → 0x0040 and loops in 0x0047..0x0054.
- **Fix:** drive the **P3.2 pin HIGH** (emergency-off de-asserted) before
  expecting the firmware to run normally. Note `set mem sfr 0xb0 …` writes the
  P3 *latch*, not necessarily the input pin in this build — verify with a PC
  trace that execution actually leaves 0x0040 and reaches 0x07C4. The
  emergency-off handler is annotated at `emergency_off` (0x0040) in
  `firmware/src/annotated/` (init.asm, main.asm).
- **Root cause (HW):** P3.2 (and P3.4/poll-gate, P3.0/baud) are conditioned by
  **MM74C04N #1**; the board needs the **RS-232 shorting connector** installed
  for these to sit HIGH (hardware/teachbox/README.md, board/MM74C04N.md). The
  `loopback` cl_hw module (`simulator/ucsim-modules/loopback/`) reproduces that
  "connector present" pin state and lets the ROM reach the teachbox poll from a
  plain `reset; run`.
- **ucSim gotcha (interrupt sampling):** a read-only cell operator that returns
  P3.2 HIGH is **not** enough to stop the level-triggered INT0 — the interrupt
  controller (interrupt.cc) tracks `bit_INT0 = (port_pins & port_value)` from
  `EV_PORT_CHANGED` events, and its `tick()` re-asserts IE0 whenever
  `bit_INT0==0`. The pin must be driven HIGH **through the port write path**
  (fire the change event), which is why the loopback module writes the P3 latch
  via `cell->write()` on each `tick()`, not `cell->set()`.

### ucSim's MCS-51 UART is byte-level and never drives the RXD/TXD pins
`cl_serial` (`src/sims/s51.src/serial.cc`) delivers a whole received byte into
`SBUF`/`RI` and writes a whole transmitted byte out; it **never toggles P3.0
(RXD) or P3.1 (TXD)**. Two consequences bit this project:
- **`MOV A,SBUF` returns the model's internal `s_in`, not the SBUF SFR cell**,
  and a write to SBUF sets `s_out`. So you **cannot inject a received byte with
  `set mem sfr 0x99`**, and you **cannot observe a transmitted byte with
  `dump sfr 0x99`**. Protocol logic tests therefore enter the ISR *after* the
  SBUF read (seed `A`/the RX buffer) — see `simulator/tests/sim_serial.sh`.
- **Firmware that bit-bangs the RXD pin cannot run.** ROB3's software auto-baud
  polls the raw P3.0 pin (`JB P3.0,$` at 0x06BF) and times edges with Timer 0;
  with no pin activity it spins forever. Fix: the **`rxd` cl_hw module**
  (`simulator/ucsim-modules/rxd/`) shifts an 8N1 frame out on P3.0 at a
  configurable machine-cycles/bit (through the port write path). Once auto-baud
  sets TH1/TR1 the CORE UART receives normally — so use `-S in=,out=` for the
  actual command bytes and `rxd` only for the pin-level bring-up. Filed as
  `simulator/issues/003-mcs51-uart-does-not-drive-rxd-txd-pins/`.

### ROB3 serial only works on the AUTO-BAUD path (P3.0=1), not fixed-baud
The fixed-baud strap path (P3.0=0 at 0x06A7) sets `IE=0x07` (**no ES** — serial
interrupt disabled) and never starts Timer 1 or writes TH1, so the UART receiver
is not armed. Only the auto-detect path ends with `IE=0x17` (ES on) + TR1
running. The auto-baud validation (`(run/6+8)&0xF0==0x20` at 0x070A) accepts a
narrow bit-time window (≈≤38400 at 11.0592 MHz; **115200 is out of range**) and
always derives **TH1=0xFC**. In the `rxd` sim model the lock lands at ~128
machine-cycles/bit (~7200); 9600 is just below the window — a modelling artifact
of representing the line in cycles, not a firmware defect.

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

### disasm51 dialect ≠ sdas8051 — convert before assembling the annotated source
`firmware/src/main.asm` is [disasm51](https://github.com/OlekMazur/disasm51)
output; the assembling 1:1 tree in `firmware/src/annotated/` uses **sdas8051**,
which does NOT accept disasm51 syntax: `NNh` hex → `0xNN`; bit dot-notation
`28h.7`/`0x22.0` → the **numeric bit address** (e.g. `0x47`, `0x10`); bare `org`
→ `.org`; `$` self-ref → `.`; `jump_XXXX` labels → local labels or numeric.
`firmware/src/annotated/d51_to_sdas.py` does this conversion using disasm51's own
instruction decoder (`disasm51.instructions`), emitting per-instruction bytes so
the output `cmp`s byte-exact. Install disasm51 in a venv (env is
externally-managed): `python3 -m venv … && …/pip install disasm51`.

### Region boundaries: some code runs PAST the obvious end (don't truncate)
When slicing the ROM into per-region assembling files, two blocks extend beyond
the "obvious" handler end and are easy to cut short — the whole-image `cmp` then
fails at the first missing byte:
- **RS-232** is `0x0203..0x0587` (901 B): the UART ISR/dispatch end ~0x052F but
  the **TX helper** continues to **0x0587** (after a short 0xFF gap at
  0x0530..0x053A). [BYTE]
- **Program interpreter** starts at **0x0800** (a 3-byte `prog_init` stub at
  0x0800..0x0802 that init `LCALL`s), not 0x0803. [BYTE]
Between-region 0xFF padding is reproduced by `objcopy --gap-fill=0xFF`; only
non-0xFF bytes (incl. the dead data `00 12 22` at 0x0020) must be emitted.

### Serial dispatch `rx_dispatch` (0x03A9) expects A=ETX, header in R6
To seed a command into the RS-232 dispatch you must set **A = 0x03 (ETX)** and
put the **header byte in R6** (IRAM 0x06), not the header in A. The
`cjne A,#0x03` at 0x03AE is a **frame-terminator check** (the last received byte
must be ETX); it then reloads the header from R6 (`mov A,R6`). Entering with the
header in A sends it straight to the generic-ack path and no command runs. The
class-0 handlers can also be entered directly at `cmd_class0` (0x0440) with
A=header for isolated dispatch tests (that path re-reads A). Program instructions
reuse this same decode in `prog_exec` (0x0941), so a stored opcode is the same
byte layout as a serial command byte.

### RS-232 command classes: bit7=0 is axis/position, bit7=1 is system/program
Easy to invert: **bit7=0** headers are the axis/position/query/control class
(`0x00–0x7F`); **bit7=1** (`0x80+`) are the system/program-control class. Within
class-0, bit6/5/4 pick the op and the low 3 bits are the axis (7=all); bit3 is
the acknowledge-request `R` bit (→ 0x23.1). All `0xFx` replies are ACK/status
bytes, not errors. Verified in `hardware/host/command.md`.

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
