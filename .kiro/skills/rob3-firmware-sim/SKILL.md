---
name: rob3-firmware-sim
description: >
  ROB3-specific firmware build, verification, and simulation workflow: the
  two-layer golden-byte-match + behavioral-sim model, the Makefile targets
  (verify / sim-init / sim-run / sim-teachbox / sim-teachbox-axis / gen), the
  ucSim `@`-filename segfault workaround, the `run N` vs `step N` bounded-advance
  gotcha, the XRAM peripheral-window seeding table, injected hardware stimulus as
  test scaffolding, the compiled teachbox / adc / loopback `cl_hw` modules, the
  P3.2/P3.4 emergency-off + poll gates that keep the sim teachbox silent, the
  keypad (row,group)->index map and debounce release-then-hold protocol, verified
  entry points/state, and the Python batch + interactive harnesses. Use when
  building, verifying, simulating, or extending the ROB3 8031 firmware and its
  ucSim test rig.
metadata:
  origin: ROB3
  globs: ["firmware/**", "simulator/**", "**/*.a51", "**/*.hex", "simulator/ucsim-modules/**"]
---

# ROB3 Firmware Build & Simulation Workflow

> ROB3-specific counterpart to the generic MCS-51 skills. For the instruction
> set see `mcs51-assembly`; for SDCC C see `mcs51-c-programming`; for generic
> ucSim use/extension see `ucsim`; for generic ucSim debugging see
> `mcs51-debugging`; for the board and its memory map see `rob3-hardware`.
> This skill covers only what is specific to *this* firmware and *this* test rig.

## The board & firmware in one line

An **Intel 8031** boots an external **M2764A 8 KB EPROM** (`firmware/hex`,
`firmware/bin`); reset is `LJMP 0x0600`. The in-tree firmware is assembly; the
annotated listings live in `firmware/src/annotated/*.annotated.asm`. See `rob3-hardware`.

## Two-layer verification model (how this project proves firmware)

1. **Golden byte-match** (`make verify`): assemble a byte-exact `.a51`
   transcription and `cmp` it against the ROM slice. Proves *the listing matches
   the image*. Matching SHA-256 hashes are printed.
2. **Behavioral simulation** (`make sim-*`): run the **real ROM** in ucSim
   (`s51`) and assert runtime state (SFRs, IRAM) against the annotation. Proves
   *the firmware behaves as documented*.

Always keep both green. If you edit an annotated region, regenerate the `.a51`
(`make gen`) so the golden test still matches the ROM bytes — **do not hand-edit
the generated `.a51`**; edit the annotated `.asm` and regenerate.

## Transcribed regions (current scope)

| Region   | Addresses         | Source                              |
| :------- | :---------------- | :---------------------------------- |
| init     | `0x0600..0x074C`  | `firmware/src/annotated/main.annotated.asm`   |
| teachbox | `0x0C00..0x0C6B`  | `firmware/src/annotated/teachbox.annotated.asm` (keypad scanner) |

The main loop, ISRs, serial protocol, and motion interpreter are **not yet
transcribed**.

## Makefile targets (`cd simulator`)

| Target | Description |
| :----- | :---------- |
| `make` / `make all` | Assemble regions and run the golden byte-match (`verify`). |
| `make verify` | **Golden test.** `cmp` assembled regions vs ROM slices; prints SHA-256. |
| `make sim-init` | Behavioral: from reset, init **blocks at `0x0680`** (ADC EOC/INT1 wait) — correct with no ADC model. |
| `make sim-run` | Behavioral: inject the gates, run to end of init `0x074B` into the main loop. |
| `make sim-teachbox` | Behavioral: run the keypad scanner, assert key decode. |
| `make sim-teachbox-module` | Behavioral: exercise the compiled teachbox `cl_hw` module (opt-in; skips w/o custom `ucsim_51`). |
| `make sim-adc` | Behavioral: free-run past the ADC/INT1 gate via the compiled adc `cl_hw` module (opt-in). |
| `make sim-teachbox-axis` | **Black-box** keypad axis-select → POSITION mode via the real scanner+handler (opt-in; needs teachbox **and** loopback modules). |
| `make test` | `verify` + all `sim-*`. |
| `make gen` | Regenerate the byte-exact `.a51` sources from the ROM (via `gen_init.py`). |
| `make clean` | Remove `build/`. |
| `make help` | List targets. |

Overridable vars (e.g. macOS): `make OBJCOPY=gobjcopy verify`,
`make SIM="$(command -v s51)" test`. Toolchain/versions: `firmware/INSTALL.md`.

## CRITICAL gotcha — the `@` in the ROM filename crashes s51

ucSim parses a file argument as `filename@memoryspace`. The shipped image
`firmware/hex/M2764A@DIP28.HEX` is read as file `M2764A` into a memory space
`DIP28.HEX` that doesn't exist; `cl_uc::read_file` then dereferences a **NULL**
console and **segfaults** (symptom: "banner only, no output", core dump under a
pty). This is *not* a curses problem. **Always run against an `@`-free copy:**

```bash
cp firmware/hex/M2764A@DIP28.HEX simulator/build/rob3.hex
s51 -t 51 -X 11.0592M simulator/build/rob3.hex
```

The Makefile does this copy for you (`$(SAFEHEX) = build/rob3.hex`, relative to
`simulator/`). Filed upstream as ucSim issue
[#13](https://github.com/danieldrotos/ucsim/issues/13) (submitted + closed);
local report at `simulator/issues/002-segfault-on-at-in-filename/`.

## CRITICAL gotcha — `run N` does NOT stop after N cycles; use `step N`

In this ucSim build (`s51` / `ucsim_51`), `run <N>` **free-runs until
interrupted** and ignores the count. For a *bounded* advance use `step <N>`,
which reliably runs N instructions and returns immediately (reason `(109)
resSTEP`), even while the ADC/INT1 servo ISR is active (~4.5 ms for 8000). A
harness that issues `run 8000` per key therefore blocks for the whole read
timeout (~20 s); `step 8000` returns in milliseconds. (This bit the interactive
teachbox harness — see `UCSimEngine.run_cycles`.)

Two related interactive-driving rules (both cost hours if missed):

- **Never pipeline a command after a `run`/`step` in one console write.** ucSim
  freezes the console during a run; a line already sitting in the input buffer
  is consumed as a **user interrupt** (`stop(resUSER)` in newcmd.cc
  `proc_input`) and **discarded without executing**. Send press, then `step N`
  **alone**, then the release, as separate writes. Batching one write is only
  safe with **no** run/step in it (e.g. the six `set hardware adc` pot pushes).
  Reproducible report + patch: `simulator/issues/001-pipelined-command-discarded-on-resuser/`.
- Bit reads (`JB`/`JNB`) go through the **`bits` address space**
  (`bits->read(bitaddr)` in jmp.cc), *not* the SFR byte cell — relevant when a
  `cl_hw` module tries to override a port bit (see the loopback module).

## Verified firmware ↔ hardware landmarks

Confirm entry addresses from the **ROM bytes, not disassembler labels** (`0xFF`
padding decodes as `MOV R7,A` and shifts boundaries):

- Reset `0x0000` → `LJMP 0x0600` init; init blocks at `0x0680` on the ADC/INT1
  gate (`JB 0x22.0`); completes at `0x074B` into the main loop `0x074D`.
- Keypad scanner entry **`0x0C00`** (0x0BFF is padding); key handler **`0x0C80`**
  (0x0C7F is padding).
- Keypad P1 read at **`0x0C0F`** (`MOV A,0x90`); row strobe written near
  **`0x0C0C`**; `sim_teachbox.sh` breaks at **`0x0C2A`**.

Expected asserted init state (from `simulator/BUILD.md` / `simulator/tests`):
`SP=0x31`, `TMOD=0x21`, `SCON=0x50`, `IE=0x84` (EA+EX1) at the gate;
axis mask `IRAM[0x22]=0x01`, output shadow `IRAM[0x47]=0xFF`; after the run
path `IE=0x07` and axis speed table `IRAM[0x48..0x4D]=01×6`.

> Byte-vs-bit: the gate is `JB 0x22.0` (bit 0 of **byte** 0x22, the one-hot axis
> mask), not RAM byte 0x22 as a whole. Resolve bit operands before seeding.

## Injecting hardware stimulus (peripherals aren't modeled)

ucSim models the **MCS-51 core only** — no 8255, ADC, SRAM, or 74LS138 decode.
Firmware that waits on hardware stalls in the sim; you must inject the stimulus,
and **label it as test scaffolding, not a claim about the silicon** (the ROB3
scripts do exactly this).

- **ADC EOC → INT1 gate.** From reset the ROM blocks at `0x0680` on
  `JB 0x22.0`. The axis-servo ISR would clear/toggle `0x22.0` on each ADC EOC;
  `sim_run.sh` emulates that by `set mem iram 0x22 0x00` then `0x01` across the
  two waits, and forces `P3.0=0` for the fixed-baud path.
- **Simulated port pins idle HIGH.** `cl_port` returns `cell->get() & port_pins`
  with `port_pins=0xFF`, so an undriven `P1` reads `0xFF`. The teachbox keypad
  columns (P1.5/6/7) are physically **active-only-when-pressed and idle LOW**, so
  a naive sim sees a phantom key hit on the first scanned row. A pin model must
  drive those bits LOW itself (see the teachbox module below).

## XRAM *is* the peripheral window (seed/read, no interception needed)

ucSim `s51` exposes writable XRAM at the board's memory-mapped device addresses,
so many peripherals can be modelled by just seeding/reading XRAM:

| Peripheral      | DPH  | XRAM addr | From CPU |
| :-------------- | :--- | :-------- | :------- |
| 8255 Port A     | 0x50 | `0x5000`  | write (L293 #1/#2 motor dir) |
| 8255 Port B     | 0x51 | `0x5100`  | write row strobe / read I/O  |
| 8255 Port C     | 0x52 | `0x5200`  | write (L293 #3 motor dir)    |
| ADC channel sel | 0x58 | `0x5800`  | write channel                |
| ADC feedback    | 0x59 | `0x5900`  | read axis position           |

```text
set mem xram 0x5900 0xAB     ; seed ADC feedback
dump xram 0x5900             ; reads back 0xAB
```

Closed loop in principle: write modelled arm position to `0x5800/0x5900` → let
the servo ISR run → read commanded motor bits from `0x5000/0x5200` → integrate →
repeat. **The blocker for a faithful closed loop is the *stateful* servo
algorithm** (accumulated per-axis workspace `0x78+` and bank-1 state across
successive ISR invocations), not the sim plumbing — see
`simulator/harness/README.md`.

## Python batch harness (`simulator/harness/ucsim.py`)

`UCSimBatch` runs `s51` once per "transaction" and parses `dump`/`Stop at`
output. State that must persist across transactions is re-seeded at the top of
each script by the caller. Deterministic and CI-friendly, but **cannot make
mid-run decisions** (it can't read state to decide when to stop) — for that use
a stateful interactive session (`s51 -p <prompt>`); see `ucsim`.

```python
from ucsim import UCSimBatch
sim = UCSimBatch("../build/rob3.hex")            # cpu="51", xtal="11.0592M"
out = sim.run("""reset
set mem xram 0x5900 0x40    ; seed ADC feedback
pc 0x00d5
step 3
dump iram 0x58 0x58
""")
val = UCSimBatch.parse_dump_byte(out, 0x58)      # -> int, or -1 if not found
```

Helpers: `parse_dump_byte`, `parse_dump_row`, `parse_stopped_pc`. The driver
strips ucSim's ANSI `\x1b[0K` sequences and auto-appends `quit`.

## The teachbox `cl_hw` module (`simulator/ucsim-modules/teachbox/`)

A compiled ucSim peripheral (`cl_teachbox : cl_hw`, `HW_GPIO`) that models the
ROB3 Teachbox 5×5 key matrix + LEDs so the real firmware's `kbd_scan` reads a
modelled device instead of hand-injected P1 values. See the generic mechanics in
`ucsim` (Part 2); this section is the ROB3 specifics.

- **Registered cells:** `register_cell(sfr, P1)` (0x90) and
  `register_cell(xram, 0x5100)` (8255 Port B row strobe).
- **`read(P1)`** keeps `P1.0..4` from the cell, clears the 3 column bits (idle
  LOW), and sets the pressed key's column bit (group1→P1.5, 2→.6, 3→.7) *iff*
  `press_row == strobed_row()`.
- **`write(0x5100)`** captures the row strobe into `cur_strobe`.
- **Command:** `set hardware teachbox <row> <group>` (row 0..7, group 1..3);
  single arg = release.

### Build into a custom `ucsim_51`

Developed against Daniel Drotos' ucSim **0.9.9** source checkout. Get the source
if it isn't already cloned:

```bash
UCSIM=~/github/danieldrotos/ucsim
[ -d "$UCSIM" ] || git clone https://github.com/danieldrotos/ucsim "$UCSIM"
```

1. Copy `teachbox.cc`/`teachboxcl.h` into `$UCSIM/src/sims/s51.src/`.
2. Append `teachbox.o` to `OBJECTS` in `src/sims/s51.src/objs.mk`.
3. In `src/sims/s51.src/uc51.cc`: `#include "teachboxcl.h"`, and at the end of
   `cl_51core::mk_hw_elements()`:
   ```cpp
   { class cl_hw *tb = new cl_teachbox(this); add_hw(tb); tb->init(); }
   ```
4. `cd "$UCSIM" && ./configure && make -C src/sims/s51.src`  → `ucsim_51`.

```bash
cp firmware/hex/M2764A@DIP28.HEX /tmp/rob3.hex
printf 'set hardware teachbox 0 1\nreset\npc 0x0c00\n...\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M /tmp/rob3.hex
```

### `strobed_row()` — calibrated & verified

`row = cur_strobe >> 4` is correct: the firmware seeds the strobe from
`0x47 & 0x0F` and advances the **high nibble** by `+0x10` per row
(`no_hit: add A,#0x10`), recovering the row as `(strobe >> 4) & 7`
(`swap A / anl A,#0x07`). So the CPU drives `0x00,0x10,0x20,…,0x70` on 8255
Port B and the module decodes each directly. (Note IRAM `0x46` holds the strobe
pattern and `0x47` the LED/row latch — distinct bytes; `sim_teachbox.sh` seeds
`0x47`.)

Verified end-to-end with the compiled module: pressing row R makes `kbd_scan`
see the column only at strobe `0x46 == (R<<4)` for R = 0..7, all three groups
decode, and release yields no hit. Covered by
`simulator/tests/sim_teachbox_module.sh` (opt-in: needs the custom
`ucsim_51`; skips gracefully otherwise). The P1-injection scanner/handler test
`simulator/tests/sim_teachbox.sh` covers the index/handler decode without the
module.

## The ADC `cl_hw` module (`simulator/ucsim-modules/adc/`) — free-run enabler

A compiled ucSim peripheral (`cl_adc : cl_hw`, `HW_PORT`) that models the
ADC0808/0809 so the ROM **free-runs from `reset; run`** instead of stalling at
the `0x0680` ADC/INT1 gate. This replaces the `sim_run.sh` hand-injection of
IRAM `0x22`. It is a **pure sensor + interrupt source** — no physics.

- **Registered cells:** XRAM `0x5800`/`0x5900` (ADC windows) and SFR `TCON`
  (0x88). (It does **not** touch Port A/C — motor physics is external, see
  below.)
- **write(0x5800):** latch `channel = val & 7`, arm an EOC countdown.
- **read(0x5800/0x5900):** return `pot[channel]` (whatever the plant last set).
- **tick():** when the countdown expires, assert **EOC → INT1 by setting
  TCON.IE1 (0x08)**. The core's external-#1 it-source then vectors
  `0x0013 → 0x00C0` when EA+EX1 are set — the real EOC→INT1 wiring, no injection.
- **Command:** `set hardware adc <ch> <value>` (plant pushes a pot reading),
  `set hardware adc` (print state).

Verified (`simulator/tests/sim_adc.sh`, opt-in like the teachbox module): with
only `P3.0=0` (fixed baud), `reset; run` reaches the main loop `0x074D`; the
servo ISR `0x00C0` fires naturally; a pushed pot byte flows through the ISR's
`MOVX A,@DPTR` (0x00D8) into ACC.

### Architecture: ucSim = bus chips, plant = external

The motor/joint/pot physics is **not** in ucSim — the L293/motor/joint/pot are
not on the 8031 bus. Only the ADC (and the 8255, via XRAM today) are modelled.
The firmware↔world contract is just **`motor[6]` out** (8255 Port A/C
`0x5000`/`0x5200`) and **`pot[6]` in** (served by `cl_adc`), so any plant — a
Python model, ROS2/Gazebo/Isaac, or the real bench — can sit behind a bridge
with no firmware change. Full rationale + the layered plan:
`simulator/harness/ARCHITECTURE.md`.

> **Direction bit-map is still `[INFER]`.** A trace established that the servo
> compares an accel/decel-*transformed* target (`R4`, not the raw `0x40+N`) to
> the feedback at `0x00EE`, and with a static pot the ISR never reaches the
> motor-write `MOVX` at `0x01C2` (it exits toward `0x0154`). So which Port A/C
> bit pattern raises vs lowers a pot cannot be extracted by simple probing —
> it needs the stateful accel/decel algorithm reverse-engineered first. The
> EOC→INT1 trigger and open-loop feedback (the free-run enablers) are solid.

## Why the sim teachbox is silent — the P3 gates & the loopback module

Pressing keys with `set hardware teachbox …` and letting the ROM run from a
plain `reset; run` does **nothing** by default: no IRAM slot ever changes,
because the firmware never reaches the main-loop keypad poll (`tb_poll`,
`0x07C4`). A PC trace goes `0x074D → 0x0003 → 0x0040` and loops in
`0x0047..0x0054`. There are **three sequential P3-input gates**, all conditioned
on the real board by **MM74C04N #1** (needs the RS-232 shorting connector
installed — see `hardware/board/MM74C04N.md`, `hardware/teachbox/README.md`):

1. **P3.2 (INT0) — EMERGENCY-OFF.** Enabled (`IE=0x17`), **level-triggered**
   (`TCON.IT0=0`), active-LOW. The handler at `0x0040` cuts both motor ports and
   spins at `0x0054: JNB P3.2, 0x0052` until P3.2 is HIGH. Undriven → reads LOW
   → permanent emergency-off. (`emergency_off`, annotated in
   `main.annotated.asm`.)
2. **P3.4 (T0) — poll enable.** `0x07AB: JB P3.4, 0x07C4` — the scanner is
   called only when P3.4 is HIGH.
3. **Keypad debounce** — see the release-then-hold protocol below.

**The `loopback` `cl_hw` module** (`simulator/ucsim-modules/loopback/`) models
the "RS-232 shorting connector present" pin state: it holds **P3.2 and P3.4
HIGH** so the ROM leaves emergency-off and reaches `tb_poll` from a plain
`reset; run`. Build/register it exactly like the teachbox/adc modules (append
`loopback.o`; `#include "loopbackcl.h"`; `new cl_loopback(this)` in
`mk_hw_elements()`). It leaves **P3.0 alone** so the harness can still force the
fixed-baud path (`P3.0=0`). Commands: `set hardware loopback on|off`,
`set hardware loopback <maskbyte>`.

> **Why a read-only operator isn't enough (the hard-won bit).** A cell `read()`
> override fixes the firmware's explicit `JB`/`JNB` but does **not** stop the
> level-triggered INT0: the interrupt controller (interrupt.cc) tracks
> `bit_INT0 = (port_pins & port_value)` from `EV_PORT_CHANGED` events, and its
> `tick()` re-asserts IE0 whenever `bit_INT0==0`. The module must drive the pin
> HIGH **through the port write path** (fire the change event) — so its `tick()`
> does `cell_p3->write(v | 0x14)`, **not** `cell->set()`. It also registers the
> `bits`-space cells `0xB2`/`0xB4` (P3.2/P3.4) so `JB`/`JNB` see them HIGH.

## Keypad (row,group) → index map and the debounce accept protocol

With the loopback module in place, the **real** keypad path works black-box.
Two verified facts (`[SIM]`, swept in ucSim):

- **Index map:** `index = row + 1 + (group-1)*8` (row 0..7, group 1..3). So
  group 1 → `0x01..0x08`, group 2 → `0x09..0x10`, group 3 → `0x11..0x18`.
  `kbd_handle` (`0x0C80`) does `DEC A`. **Axis-select** = index `0x02..0x07`
  (group 1, rows 1..6) → axis 0..5, each setting mode `IRAM[0x29]=0x40`
  (POSITION).
- **Debounce accept = RELEASE-then-HOLD.** The accept path (`0x0C41`) is gated
  by `JNB 0x20.6`, and flag `0x20.6` is set **only** by the `key_release` path
  (scanner sees no key). So dispatch requires: release (sets `0x20.6`) → press +
  **hold** the same index across ~3 scan passes (~24k stepped instructions) →
  `kbd_handle` runs. Holding from reset with no prior release never dispatches.

Reference harness pattern (per key): `release; step×3; press; step until PC hits
0x0C80; step×N; release`. See `simulator/tests/test_teachbox_axis_select.py`
(the `make sim-teachbox-axis` target), which asserts all six axis-select keys
reach POSITION mode.

> **Not yet mapped:** full `POS a . n ENT` numeric value entry + commit
> (`pos_digit` 0x0D65 / `pos_commit` 0x0D9F). It depends on further editor state
> (`0x29.3`, `0x2A.x`, the `0x6E:0x6D` accumulator) held across a multi-key
> sequence; the per-key release cadence needed for debounce disrupts it. Axis
> select is `[SIM]`-confirmed; value entry is the open follow-up.

## Interactive engine harness (`simulator/harness/gui/engine.py`)

Beyond the batch driver, `UCSimEngine` holds one long-lived `ucsim_51` over a
**pty** (ucSim only prints its prompt on a TTY) and talks to it line-by-line —
the interactive counterpart used by the Teachbox GUI/CLI. It presses keys
(`press`/`release` → `set hardware teachbox`), pushes pots
(`push_pots` → batched `set hardware adc`), advances with `run_cycles` (which
uses **`step`**, per the gotcha above), and reads IRAM/XRAM state. Use it when
you need to *press → advance → read → decide → repeat* in one session (the batch
harness can't make mid-run decisions). Text front-ends: `cli.py` (and
`gui.py`); a `--console-port N` opens a second `nc`-attachable console, but note
the two consoles contend for the one sim — prefer the built-in `:ucsim <cmd>`
passthrough for inspection.

## Reading failures (ROB3 quick triage)

- **Banner only / core dump** → the `@` filename bug. Use the `rob3.hex` copy.
- **Breakpoint never hits** → wrong entry address (padding shift; re-derive with
  `dc`) or the path is gated on un-injected hardware; add stimulus.
- **Phantom keypress / instant "hit"** → undriven port reading `0xFF`; the pin
  model must drive idle-LOW columns.
- **Keys pressed but nothing happens / trapped at 0x0047..0x0054** → the P3.2
  EMERGENCY-OFF gate (and P3.4 poll gate); build/enable the `loopback` module.
- **Scanner runs but no key dispatches (0x0C80 never hit)** → debounce needs the
  RELEASE-then-HOLD cadence (flag `0x20.6`).
- **A per-key `run 8000` blocks ~20 s** → use `step`, not `run` (bounded advance
  gotcha); and never pipeline a command after a run/step in one write.
- **Golden test FAIL after edits** → you changed bytes; `make gen` and
  re-annotate the `.asm`, don't hand-edit the generated `.a51`.

## When to use this skill

- Running `make verify` / `make sim-*` / `make gen`, or adding sim tests.
- Driving `s51` on the ROB3 ROM (batch harness or interactive) with the correct
  gates/stimulus and the `@`-free hex copy; remember `step N` (not `run N`) for
  bounded advance.
- Building or calibrating the teachbox / adc / loopback `cl_hw` modules.
- Getting the firmware to actually poll the keypad (P3.2/P3.4 gates + loopback)
  or dispatch a key (debounce release-then-hold; the (row,group)→index map).
- Any task that touches the ROB3 firmware build/verify/simulate pipeline.
