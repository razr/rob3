# Session: extract EXT1 axis-servo annotation + explain servo/calibration/limits

**Date:** 2026-09-16
**Task:** Review the EXT1-related annotation in `main.annotated.asm`, extract it
to its own file, then progressively answer a chain of "how does it actually
work" questions (trigger, rate, one-vs-all axes, feedback scaling, calibration,
travel limits) — folding the verified answers into the annotation and hardware
docs. Kept [BYTE]/[SIM]/[HW]/[INFER] provenance throughout; corrected two of my
own wrong first guesses when the ROM/bench evidence contradicted them.

## Changes

### New: `firmware/src/annotated/ext1_axis_servo.annotated.asm`
Extracted the EXT1 / axis-servo ISR (0x00C0) from `main.annotated.asm` into its
own file (naming precedent: `teachbox.annotated.asm`). The code block is
byte-identical to the original except one intended fix: the previously-untagged
`mov @R0,A` got its `[BYTE]` tag.

Then, per request, **decluttered** the per-line provenance (option 2): stripped
~160 bare trailing `[BYTE]` tags, kept the exceptions inline (`[INFER]` motor
table reads, `[HW][BYTE]` MOVX), and added a header "DEFAULT: unmarked lines are
[BYTE]" note.

Added explanatory header sections (all provenance-tagged):
- **WHAT THIS INTERRUPT DOES** — plain-English: closed-loop position servo,
  time-slices all six axes; per-pass read-feedback → compute-error → clamp →
  encode/drive-motor → advance.
- **TRIGGER & RATE** — EXT1 = INT1 on P3.3, driven by ADC EOC; NOT timer-driven.
  A conversion is STARTED by a MOVX write (START = /WR); init fires the first,
  each ISR starts the next. The PAUSE between interrupts is the ADC conversion
  latency (ISR RETIs without waiting), which frees the CPU for the main loop —
  otherwise the ISR would starve everything. Absolute Hz is [INFER] (ADC clock
  source undocumented); trigger/no-wait/handshake are [BYTE][HW].
- **FEEDBACK SCALING / CALIBRATION** — 0..255 are RAW ratiometric ADC pot counts
  (VREF+=+5V), not degrees; servo is unit-agnostic (target vs feedback in same
  scale); pots are ABSOLUTE so no homing/self-cal; angle↔count map is per-axis,
  measured, and lives OUTSIDE the firmware (`hardware/motors/test.md`,
  `AXIS_CAL[0..5]`).
- **DRIVING ALL SIX AXES AT ONCE** — reconciles "simultaneous" (manual) with
  one-axis-per-interrupt: latched 8255 ports (A=axes0..3, C=axes4..5) + per-axis
  read-modify-write on the shadow (`anl`/`orl`) + round-robin faster than the
  motors respond = time-division multiplexing.
- Per-axis IRAM layout with clarified labels (TARGET=commanded/what POS writes;
  SPEED/step rate; CURRENT=host-view snapshot COPY of feedback, confirmed
  `mov 0x50,0x58` at 0x0498; FEEDBACK=raw ADC; DECEL; ISR workspace).
- The **8-wide one-hot rotating mask at 0x22** (6 axes on bits 0..5 + 2
  housekeeping phases on bits 6/7) and the init handshake that waits one full
  ADC sweep. Answers "what does the 7 in `jb 0x22.7` mean" (bit position /
  phase selector, not an axis count).
- A worked **`POS 2 . 200`** example showing values flow and one-axis-per-INT1.

### `firmware/src/annotated/main.annotated.asm`
Replaced the ~265-line EXT1 block with an 11-line pointer stub; added the file
reference to the 0x0013 vector comment. (Doc-only; the golden byte-match build
uses the `.a51` files, not these annotated listings — no build impact.)

### `hardware/teachbox/README.md`
Added a **ROB3i-vs-ROB3 model-scope** note at the "512 steps / POS 0..511"
spec: those figures are the newer ROB3i; the original ROB3 firmware here is
8-bit (0..255). (Per project owner: they have a ROB3.)

### `hardware/motors/test.md`
- Added **angle/position ↔ count mapping** worked examples (linear interpolation
  between two measured points): shoulder (+35°→146) and gripper (30mm→122) from
  real bench data; a ±130° example explicitly marked MEASURE-ME with placeholder
  numbers.
- Added a **⚠️ Safety** section: the ROM's `POS a . n` path validates only
  value 0..255 (byte-overflow → ERR at `jump_0D23`) and axis 1..6
  (`jump_0CA3`), then stores straight to target[a] with **NO per-axis position
  soft-limit**. So 0..255 is NOT self-limiting — commanding outside an axis's
  usable count window drives it into a hard stop/stall. Enforce per-axis
  `[min_count,max_count]` yourself (as the Arduino `motor_control` watchdog
  does). "value/axis check" is [BYTE]; "no clamp anywhere" is [INFER] (traced
  the POS-entry/axis-select/target-store paths, not a whole-ROM negative proof).

## Corrections made mid-session (honesty)
- First claimed P3.4 "idles HIGH so no plug needed" earlier — unrelated to this
  thread but the same discipline: here I initially under-explained the ADC
  start (fixed: MOVX = START) and the inter-interrupt pause (fixed: = conversion
  latency, ISR doesn't busy-wait).

## Verification
- Diffed extracted code vs original block: identical except the one intended
  `[BYTE]` tag add.
- No build impact (annotated files are documentation; `.a51` files drive the
  golden byte-match).

## Open / [INFER] left standing
- Absolute EXT1 rate / main-loop duty split (ADC clock frequency undocumented).
- Exact motor-drive polarity / L293 output-table semantics.
- "No position clamp anywhere in the ROM" not exhaustively proven.
