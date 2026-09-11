---
name: rob3-firmware-sim
description: >
  ROB3-specific firmware build, verification, and simulation workflow: the
  two-layer golden-byte-match + behavioral-sim model, the Makefile targets
  (verify / sim-init / sim-run / sim-teachbox / gen), the ucSim `@`-filename
  segfault workaround, the XRAM peripheral-window seeding table, injected
  hardware stimulus as test scaffolding, the compiled teachbox `cl_hw` module
  and its strobe->row calibration, verified entry points/state, and the Python
  batch harness. Use when building, verifying, simulating, or extending the
  ROB3 8031 firmware and its ucSim test rig.
metadata:
  origin: ROB3
  globs: ["firmware/**", "**/*.a51", "**/*.hex", "**/sim/**", "firmware/sim/ucsim-module/**"]
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
annotated listings live in `firmware/src/*.annotated.asm`. See `rob3-hardware`.

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
| init     | `0x0600..0x074C`  | `firmware/src/main.annotated.asm`   |
| teachbox | `0x0C00..0x0C6B`  | `firmware/src/teachbox.annotated.asm` (keypad scanner) |

The main loop, ISRs, serial protocol, and motion interpreter are **not yet
transcribed**.

## Makefile targets (`cd firmware`)

| Target | Description |
| :----- | :---------- |
| `make` / `make all` | Assemble regions and run the golden byte-match (`verify`). |
| `make verify` | **Golden test.** `cmp` assembled regions vs ROM slices; prints SHA-256. |
| `make sim-init` | Behavioral: from reset, init **blocks at `0x0680`** (ADC EOC/INT1 wait) — correct with no ADC model. |
| `make sim-run` | Behavioral: inject the gates, run to end of init `0x074B` into the main loop. |
| `make sim-teachbox` | Behavioral: run the keypad scanner, assert key decode. |
| `make test` | `verify` + all `sim-*`. |
| `make gen` | Regenerate the byte-exact `.a51` sources from the ROM (via `sim/gen_init.py`). |
| `make clean` | Remove `sim/build/`. |
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
cp firmware/hex/M2764A@DIP28.HEX sim/build/rob3.hex
s51 -t 51 -X 11.0592M sim/build/rob3.hex
```

The Makefile does this copy for you (`$(SAFEHEX) = sim/build/rob3.hex`).

## Verified firmware ↔ hardware landmarks

Confirm entry addresses from the **ROM bytes, not disassembler labels** (`0xFF`
padding decodes as `MOV R7,A` and shifts boundaries):

- Reset `0x0000` → `LJMP 0x0600` init; init blocks at `0x0680` on the ADC/INT1
  gate (`JB 0x22.0`); completes at `0x074B` into the main loop `0x074D`.
- Keypad scanner entry **`0x0C00`** (0x0BFF is padding); key handler **`0x0C80`**
  (0x0C7F is padding).
- Keypad P1 read at **`0x0C0F`** (`MOV A,0x90`); row strobe written near
  **`0x0C0C`**; `sim_teachbox.sh` breaks at **`0x0C2A`**.

Expected asserted init state (from `BUILD.md` / `sim/tests`):
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
`firmware/sim/harness/README.md`.

## Python batch harness (`firmware/sim/harness/ucsim.py`)

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

## The teachbox `cl_hw` module (`firmware/sim/ucsim-module/`)

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

### Open work — calibrate `strobed_row()`

The module currently assumes `row = cur_strobe >> 4`, which does **not** match
the observed 8255 Port B (`0x5100`) values. In the firmware the strobe pattern
is held in IRAM **`0x46`** and the LED/row output latch in **`0x47`** (distinct
bytes — `sim_teachbox.sh` seeds `0x47`). Correct procedure:
1. Break at the strobe write (`0x0C0C`) and read `ACC`/`0x5100` each row of
   `kbd_scan`.
2. Map those exact strobe bytes → matrix rows 0..7.
3. Update `cl_teachbox::strobed_row()` to that mapping.
Verify end-to-end against `firmware/sim/tests/sim_teachbox.sh`.

## Reading failures (ROB3 quick triage)

- **Banner only / core dump** → the `@` filename bug. Use the `rob3.hex` copy.
- **Breakpoint never hits** → wrong entry address (padding shift; re-derive with
  `dc`) or the path is gated on un-injected hardware; add stimulus.
- **Phantom keypress / instant "hit"** → undriven port reading `0xFF`; the pin
  model must drive idle-LOW columns.
- **Golden test FAIL after edits** → you changed bytes; `make gen` and
  re-annotate the `.asm`, don't hand-edit the generated `.a51`.

## When to use this skill

- Running `make verify` / `make sim-*` / `make gen`, or adding sim tests.
- Driving `s51` on the ROB3 ROM (batch harness or interactive) with the correct
  gates/stimulus and the `@`-free hex copy.
- Building or calibrating the teachbox `cl_hw` module.
- Any task that touches the ROB3 firmware build/verify/simulate pipeline.
