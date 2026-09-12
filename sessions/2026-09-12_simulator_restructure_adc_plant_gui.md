# Session: ROB3 — simulator restructure, cl_adc, plant/bridge architecture, Teachbox GUI+CLI

**Date:** 2026-09-12
**Task:** A multi-part session: (1) restructure the sim rig to a top-level
`simulator/`; (2) add a compiled ucSim **ADC** peripheral so the ROM free-runs;
(3) reorganise the ucSim modules; (4) settle the closed-loop **architecture**
(ucSim = bus chips, plant = external); (5) build a **Teachbox GUI and CLI** with
a modelled potentiometer plant.

Working method throughout: verify against the ROM/simulator before asserting;
keep [BYTE]/[SIM]/[HW]/[INFER] provenance; commit in small honest steps.

## What was done

### 1. Restructure: `firmware/sim/` -> top-level `simulator/` (committed `c96ba18`)
- Moved the whole build/verify/simulate rig out of `firmware/` (which now holds
  only the ROM + disassembly + annotations) into a sibling `simulator/`.
- `Makefile` reads the ROM from `../firmware`; `BUILD.md` moved into
  `simulator/`; `INSTALL.md` stayed in `firmware/`. All path refs updated across
  README/INSTALL/BUILD/sim READMEs/skill/steering. `git mv` -> renames.

### 2. `cl_adc` ucSim peripheral (committed `c96ba18`, then refactored — see 4)
- ADC0808/0809 model: serves per-channel feedback on the ADC MOVX windows
  (XRAM 0x5800/0x5900) and asserts **EOC -> INT1 by setting TCON.IE1 (0x08)**,
  the real wiring that drives the axis-servo ISR (0x00C0).
- This lets the real ROM **free-run from `reset; run`** past the init gate at
  0x0680, replacing the `sim_run.sh` hand-injection of IRAM 0x22.
- New opt-in test `tests/sim_adc.sh` + `make sim-adc`. Verified: free-run
  reaches 0x074D, the servo ISR fires from a natural EOC->INT1, and a pushed pot
  byte flows through the ISR's `MOVX A,@DPTR` (0x00D8) into ACC.

### 3. `ucsim-module/` -> `ucsim-modules/` with per-module subfolders (committed `c96ba18`)
- `ucsim-modules/{teachbox,adc}/` each with `.cc`/`.h` + a README; shared build
  steps in `ucsim-modules/README.md`.

### 4. Closed-loop architecture decided + `cl_adc` slimmed to a pure sensor
- Long design discussion. Key conclusions, written up in
  **`simulator/harness/ARCHITECTURE.md`**:
  - **ucSim models only bus-addressable chips** (8255 via XRAM, ADC via
    `cl_adc`). The **L293/motor/joint/pot are NOT on the 8031 bus**, so they are
    *plant* and live **outside** ucSim.
  - The firmware learns position **only** from the pot via the ADC (pure closed
    loop; no encoder). So a plant must make the pot move when/only-when the
    motor is driven, in the commanded direction.
  - The whole firmware<->world contract is **`motor[6]` out** (8255 Port A/C
    0x5000/0x5200) and **`pot[6]` in** (served by `cl_adc`). Any plant — Python,
    ROS2/Gazebo/Isaac, or real bench HW — plugs in behind a bridge with no
    firmware change.
  - Direction must be exact; speed can be approximate.
- Refactored **`cl_adc` to a pure sensor conduit**: removed the in-module
  `integrate_arm()`/`closed_loop`/Port A-C registration; it now only holds the
  selected channel + a per-channel `pot[]` cache written from outside, serves it
  on a feedback read, and raises EOC->INT1. `set hardware adc <ch> <val>` = the
  plant pushing a pot reading.

### 5. Teachbox GUI + CLI (`simulator/harness/gui/`)
- **`plant.py`** — the external physics: `pot[6]`, `decode_l293` (motor bits ->
  direction), integrate + clamp. No ucSim dependency; self-test passes.
- **`engine.py`** — a **persistent `ucsim_51` session over a pty** (ucSim only
  prints its `-p` prompt on a TTY, not a pipe — discovered + worked around).
  Presses keys (`set hardware teachbox`), pushes pots (`set hardware adc`),
  reads IRAM/XRAM.
- **`gui.py`** — Tkinter: the 5x5 Teachbox (all 25 keys, verified (row,group)
  mapping from `hardware/teachbox/test.md`) + six axis pot bars with targets.
  Threaded engine boot, background pot-push so the UI stays responsive.
- **`cli.py`** — text front-end, same plant+engine. Keystrokes
  `0-5 + - P E N D C R I O`, `POS a . n E`, meta `:show/:axis/:target/:run/
  :quit`. `--firmware` opt-in to drive the real ROM (slow via pty); default is
  the responsive plant-only mode.
- **`_smoke_gui.py`** — headless Tk-under-Xvfb smoke test.

## Verification
- `make test` (golden + behavioral, incl. compiled teachbox + adc modules):
  **ALL TESTS PASSED**.
- GUI headless smoke (Xvfb): select axis 1, jog up -> target 183, plant pot
  converges to 183 -> **SMOKE OK**; plant-only fallback also **SMOKE OK**.
- CLI: plant-only script `3 +++ P 5 . 60 E` correct in 0.07s; REPL over piped
  stdin works; `--firmware` boots the ROM with modules and processes keys.
- `plant.py` self-test OK; all Python modules compile.

## Key findings / gotchas
- **ucSim emits its `-p` prompt only on a TTY**, not a pipe -> a persistent
  interactive driver must use a **pty** (`pty.fork`), and strip full CSI escape
  sequences (colour), not just `\x1b[0K`.
- **Interactive ucSim over a pty is slow per cycle** (~20 s for 100k cycles),
  so keypad-into-firmware is background/opt-in; the plant is the responsive core.
- **Stock `s51` has no modules** and `run_to(main_loop)` on it hits the 30 s
  serial auto-detect hang -> the GUI/CLI skip running the ROM unless the `cl_hw`
  modules are present.
- **EOC->INT1** is asserted by setting **TCON.IE1 (0x08)**; the 8051 core's
  external-#1 it-source vectors 0x0013 -> 0x00C0 when EA+EX1 are set.
- **Direction-trace is blocked (documented, not a quick win):** the servo
  compares an accel/decel-*transformed* target (`R4`, not raw 0x40+N) to the
  feedback at 0x00EE, and with a static pot the ISR never reaches the motor
  write `MOVX` at 0x01C2 (it exits toward 0x0154). So the L293 direction bit-map
  stays **[INFER]** until the stateful accel/decel algorithm is reverse-
  engineered; the plant's `decode_l293` is a clearly-labelled placeholder.

## Custom ucsim_51
The GUI/CLI/tests need the custom `ucsim_51` built with the `cl_hw` modules
(teachbox + adc), which lives in the separate ucSim source checkout
(`~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51`). The module *sources*
are committed under `simulator/ucsim-modules/`; the binary is a local opt-in
build. Point tools at it with `UCSIM_51=/path/to/ucsim_51`.

## Open items / next
- **Direction trace** (upgrade `decode_l293` [INFER] -> [SIM]) — needs the servo
  accel/decel RE; the deep, deferred task.
- **Socket bridge** `cl_hw` carrying `motor[6]`/`pot[6]` over TCP, so
  ROS2/Gazebo/Isaac can be the plant unchanged (architecture note step 4).
- Full free-run keypress->motion still needs the keypad debounce reproduced.
- Local `main` ahead of `origin/main`; nothing pushed.
