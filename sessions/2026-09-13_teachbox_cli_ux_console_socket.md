# Session: ROB3 — Teachbox CLI UX (configurable ROM, history) + ucSim console socket

**Date:** 2026-09-13
**Task:** A UX/tooling session on the Teachbox CLI (`simulator/harness/gui/cli.py`
+ `engine.py`). Started as Q&A about what the sim actually models (teachbox /
adc modules, the "plant", motor control), then turned into concrete CLI
improvements: clearer `--firmware` semantics, a configurable ROM path, command
history, and — the main deliverable — a way to attach a **separate terminal**
to the CLI's running ucSim with `nc` and issue `dump`/`di`/`break`/`step`.

Working method: verify against the ROM/simulator before asserting; keep the
[BYTE]/[SIM]/[HW]/[INFER] provenance; commit small.

## Q&A clarifications (no code, but worth recording)

- **`cl_teachbox` module** models the Teachbox scan *behaviour*, not one IC: it
  taps 8255 Port B (XRAM `0x5100`) on write to learn the strobed row and drives
  the P1.5/6/7 column bits on read for the held key. Collapses the 74LS138
  decode (`row = strobe>>4`) + passive key matrix + active-LOW column returns.
  Input-only; no LEDs, no debounce/timing.
- **`cl_adc` module** models the real **ADC0808/0809**: serves `pot[channel]` on
  a feedback read (XRAM `0x5800`/`0x5900`) and, crucially, asserts **EOC->INT1**
  (sets TCON.IE1) so the ROM free-runs. Pure sensor + interrupt source; no physics.
- **Motor control is NOT modelled inside ucSim.** 8255 Port A/C (`0x5000`/`0x5200`)
  are plain XRAM cells; there is no `cl_motor`/`cl_l293`. The motor->pot physics
  is the external **plant** (`plant.py`), per `harness/ARCHITECTURE.md`
  (ucSim = bus chips; L293/motor/joint/pot = off-bus plant). `decode_l293` is a
  documented **[INFER]** placeholder (direction map still unverified).
- **"Plant"** = control-systems term: the physical system being controlled (the
  ROB3 arm — motors + joints + pots), the counterpart to the firmware controller.
- The **CLI and GUI are two front-ends** (`cli.py`, `gui.py`) over one shared
  `engine.py` (ucSim over a pty) + `plant.py`. `:show` displays the *plant* pots,
  not the firmware's `0x50+N`.

## What was done (code)

All in `simulator/harness/gui/`.

### 1. `--firmware` semantics clarified, then made to carry an optional ROM
- Fixed a wrong docstring line that labelled `python3 cli.py` (no `--firmware`)
  as "firmware in the loop"; it is plant-only. `UCSIM_51` alone does nothing
  without `--firmware`.
- Collapsed an initial two-flag design (`--firmware` + `--firmware-hex`) into a
  single flag with an optional arg (user preference):
  - `--firmware` absent -> plant-only
  - bare `--firmware` -> default ROM
  - `--firmware <hexfile>` -> that ROM
  Implemented with `nargs="?", const="", default=None`.
- ROM default resolution lives in `engine.default_hex()` (honours the
  **`ROB3_HEX`** env var, else `firmware/hex/M2764A@DIP28.HEX`); `_safe_hex(src)`
  still makes the `@`-free copy to `simulator/build/rob3.hex` before loading.
- CLI prints `[ROM: .../build/rob3.hex]` on startup so you can see what loaded.

### 2. Command history (up/down arrows) in the REPL
- `readline` (guarded import) auto-enables arrow-key history + line editing.
- `_init_history()` loads/saves a persistent `~/.rob3_teachbox_history`
  (1000-line cap, `atexit` save). Banner shows a `(↑/↓ = history)` hint.
- Verified: readline records + round-trips entries through the history file.

### 3. ucSim command console over a socket (the main deliverable)
User wanted: CLI starts the sim with the user's binary, then attach from a
**separate terminal** with `nc localhost <port>` and run `dump`/`di`/etc.
- Discovered the right flag by reading `ucsim_51 -h`: **`-z <port>`** = command
  console on **both** stdio and a TCP socket (vs `-Z` = socket only; `-S` =
  UART/serial only, which canNOT do `dump`/`di`). Corrected an earlier wrong
  claim that this build had no command socket.
- `engine.py`: `UCSimEngine(..., console_port=None)`; when set, launch args get
  **`-b -z <port>`** (`-b` = black&white so the `nc` stream is clean, no ANSI).
- `cli.py`: `--console-port PORT` (errors without `--firmware`), threaded to the
  engine; startup prints `[console socket: nc localhost <port> ...]`.

## Verification

- `python3 -c ast.parse` on both files: **syntax OK**.
- `plant.py` self-test: **OK**.
- Plant-only REPL smoke (`P 0 . 255 E` / `:show`): axis 0 -> 255 correctly.
- `--console-port` guard rejects use without `--firmware`.
- **Live socket proof (binary directly, via a pty so the stdio console is
  alive):** `-z <port>` opens a `LISTEN` socket; over `nc`, `dump iram 0x50 0x55`
  returned real firmware bytes `17 59 5a f3 79 c0`. With `-b` the ANSI colour
  escapes are gone (only inherent telnet-IAC/`^M`/status-digit artifacts remain).
- Key finding: **`-z` only opens the listener once a real stdio console/TTY is
  present** — which is exactly the CLI's case (engine always uses `pty.fork`).
  A console-less launch loaded the ROM but did not listen.

## How to use

```bash
# terminal 1 — CLI starts ucSim with your ROM + console socket
cd simulator/harness/gui
UCSIM_51=~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51 \
  python3 cli.py --firmware --console-port 1234
#   (or:  --firmware /path/to/rom.hex  to load a different ROM)

# terminal 2 — attach and debug the SAME running ucSim
nc localhost 1234
dump iram 0x50 0x55
di 0x00c0 0x0100
break 0x074d
```

## Files changed
- `simulator/harness/gui/cli.py`  — `--firmware [HEXFILE]`, `--console-port`,
  readline history, startup ROM/socket messages, docstring/help fixes.
- `simulator/harness/gui/engine.py` — `default_hex()` (+`ROB3_HEX`),
  `_safe_hex(src)`, `UCSimEngine(hex_path=, console_port=)` -> `-b -z <port>`.

## Caveats / open items
- The `nc` console shares one interpreter with the CLI's pty console; after boot
  the CLI is quiet (commands only on keypress/settle), so avoid mashing teachbox
  keys in T1 while stepping in T2 (they'd collide on the shared core/prompt).
- `nc` stream still has telnet-IAC bytes on connect + `^M` + a status-digit
  prefix; cosmetic, not colour.
- Not added (offered, declined/out of scope): in-CLI `:ucsim`/`:pos` passthrough,
  a `:fw` proof-of-life command, an Option-A Unix-socket bridge with a lock.
- **L293 direction map still [INFER]** (unchanged) — the deferred servo
  accel/decel RE remains the deep task; not touched this session.
- Local `main` was ahead of `origin/main` in prior sessions; this session
  commits but does **not** push.
