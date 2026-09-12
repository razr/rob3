# ROB3 Teachbox + arm GUI

A dependency-free (Tkinter) GUI that shows the ROB3 **Teachbox** (5x5 key matrix)
on the left and the six **robot axes** on the right. Pressing keys drives the
real firmware in ucSim; the axis potentiometers are modelled by the external
**plant** (the physics that is not on the 8031 bus — see
[`../ARCHITECTURE.md`](../ARCHITECTURE.md)).

```
   Teachbox (5x5)                 Axes — pot feedback (0..255)
  ┌───┬───┬───┬───┬───┐          0  q1 Base   [███████        ] 137  tgt 137
  │RUN│STO│INS│DEL│ERR│          1  q2 Shoul  [██████████     ] 183  tgt 183
  │POS│TIM│OUT│MRK│GOT│          2  q3 Elbow  [████           ]  70  ...
  │IF │NOP│ENT│↑/→│↓/←│          ...
  │ 7 │ 8 │ 9 │ 4 │ 5 │
  │ 6 │ 1 │ 2 │ 3 │ 0 │
  └───┴───┴───┴───┴───┘
```

## What is real vs modelled

| Layer | Real / modelled | Notes |
| :---- | :-------------- | :---- |
| Keypad press | **real firmware** | `set hardware teachbox <row>,<group>` into the `cl_teachbox` scanner (when the custom `ucsim_51` is present). |
| Firmware | **real ROM** in ucSim | `cl_adc` gives it a live ADC + EOC→INT1 so it free-runs. |
| Motor → pot | **modelled (plant.py)** | The L293/motor/joint/pot are *not* on the 8031 bus, so they live outside ucSim. |
| Pot → firmware | **real** | Plant pushes pot values via `set hardware adc <ch> <val>`; the firmware reads them through the ADC. |

**Honest limitations**

- The **L293 direction bit-map is `[INFER]`** (see ARCHITECTURE.md "Direction-trace
  findings"), so the plant's motor→pot direction is provisional until the servo
  accel/decel algorithm is reverse-engineered.
- Interactive ucSim over a pty is **slow per cycle**, so the responsive part of
  the UI is the plant; firmware keypad presses run in the background with a
  small cycle budget. The pot animation (target ← jog/select, plant converges,
  value pushed to the ADC) is the live, interactive loop.
- Without the custom `ucsim_51` (built with the `cl_hw` modules), the GUI falls
  back to a **plant-only demo**: the keypad drives the plant directly so the UI
  still works.

## Run

```bash
cd simulator/harness/gui
# with the firmware in the loop (needs the custom ucsim_51 — see
# ../../ucsim-modules/README.md):
UCSIM_51=~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51 python3 gui.py

# plant-only fallback (no custom binary needed):
python3 gui.py
```

## Using it

1. **Select an axis:** press a numeric key `2`..`7` → selects axis 0..5
   (matches the firmware's POSITION-mode `key index N → axis N-2`).
2. **Jog:** `↑/→` increases, `↓/←` decreases the selected axis' target; the pot
   bar animates toward it.
3. Watch the orange target tick and the green pot bar converge; the value is
   pushed into the firmware's ADC each tick.

## Files

| File | Purpose |
| :--- | :------ |
| `plant.py`  | The physical model: pots + `decode_l293` (motor→direction) + integrate. No ucSim dependency; has a self-test (`python3 plant.py`). |
| `engine.py` | Persistent `ucsim_51` session over a **pty** (ucSim only prints its prompt on a TTY). Presses keys, pushes pots, reads IRAM/XRAM state. Smoke test: `python3 engine.py`. |
| `gui.py`    | The Tkinter front-end tying keypad + plant + engine together. |
| `cli.py`    | A text front-end (same plant + engine) — type Teachbox keystrokes, watch the pots. See below. |

## CLI

A no-display text version. Type Teachbox keystrokes; the six axes are shown as
ASCII bars.

```bash
cd simulator/harness/gui
python3 cli.py                       # plant-only (instant, interactive REPL)
python3 cli.py --firmware            # also drive the real ROM in ucSim (slower)
python3 cli.py --script "P 1 . 200 E"   # non-interactive one-shot
```

Keystrokes (type a string, spaces ignored):

| Keys | Meaning |
| :--- | :------ |
| `0`–`5` | select axis 0..5 |
| `+` `-` | jog the selected axis up / down |
| `P a . n E` | POSITION: `a`=axis, `n`=value, `E`=ENT (e.g. `P 1 . 200 E`) |
| `E` `N` `D` `C` `R` `I` `O` | ENT / NOP / DEL / ERR / RUN / INS / OUT |
| `:show` `:axis N` `:target N V` `:run` `:help` `:quit` | meta commands |

Example session:

```
tb> 3 +++
  select axis 3
  jog axis 3 -> target 146
  3 q4 Wrist     [#################             ] 146  (tgt 146)  <
tb> P 5 . 60 E
  POS commit: axis 5 = 60
  5 Gripper      [#######                       ]  60  (tgt  60)  <
```

> `--firmware` presses each key into the real firmware scanner (`cl_teachbox`)
> and pushes pots into the ADC (`cl_adc`); interactive ucSim over a pty is slow
> per cycle, so it is off by default. Plant-only mode is the responsive path and
> exercises the same key semantics and plant physics.

## Testing headless

The GUI stack has a headless smoke path (Tk under Xvfb):

```bash
UCSIM_51=/path/to/ucsim_51 xvfb-run -a python3 _smoke_gui.py   # prints SMOKE OK
```
