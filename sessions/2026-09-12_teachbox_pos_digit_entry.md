# Session: ROB3 — Teachbox POS-digit direct entry (type a number → axis slot)

**Date:** 2026-09-12
**Task:** Continue the teachbox work. Pick up the mid-flight experiment of using
`set hardware teachbox` to move an axis to a specific value (e.g. axis 1 → 128),
determine how the firmware sets an axis position from a typed number (vs the
+/- jog), and annotate + test that path.

Working method: verify against the ROM/simulator before asserting; keep the
[BYTE]/[SIM]/[HW]/[INFER] provenance tags; commit small; never push.

## Starting state (uncommitted from prior session)
- `firmware/sim/ucsim-module/teachbox.cc` (+README): compiled `cl_teachbox`
  module, strobe→row calibrated (`row = strobe>>4`), verified end-to-end.
- `firmware/Makefile`: added `sim-teachbox-module` + `demo-teachbox` targets;
  `test` now includes `sim-teachbox-module` (opt-in skip w/o custom `ucsim_51`).
- New tests `sim_teachbox_module.sh`, `demo_teachbox_axis.sh` (untracked).
- Custom `ucsim_51` with the module lives at
  `~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51` (stock is `/usr/bin`).

## What was done

### Traced how an axis reaches a specific value
The +/- **jog** (`kh_jog`, 0x0E26) only steps ±1 per press — reaching 128 that
way is 128 presses (the auto-repeat mechanism). The real "set to a number" path
is the manual's **`POS a . n ENT`** direct entry, previously left `[INFER]`.

Found and [BYTE]/[SIM]-verified it:
- **Decimal accumulate** (entry 0x0D65, A = digit): a 16-bit value is built in
  `(0x6E:0x6D)` = (high:low) by `value = value*10 + digit` — `MUL AB` with
  `B=#0x0A` at 0x0D68 (low) and 0x0D81 (high).
  - ucSim: typing 1,2,8 gives `0x6D`: `0x00 → 0x01 → 0x0C(12) → 0x80(128)`.
- **Commit** (0x0D9B..0x0DA1): `R1 = R4 + 0x4F` (R4 = axis+2 numbering, so
  R4=2 → axis-1 slot 0x51), then **`MOV @R1,0x6D` at 0x0D9F** writes the
  accumulated value straight into the axis position slot.
  - ucSim: R4=2, `0x6D=0x80` → slot `0x51 = 0x80`. So "POSITION, select axis 1,
    type 1 2 8, ENT" sets axis 1 = 128.

(The table at 0x0FC5 `01 02 04 08 10 20 40 80` is a 1<<n bit table used by the
routine at 0x0FCE that fetches a 16-bit XRAM entry into `0x66:0x67` — related
plumbing, not the digit accumulator itself.)

### Annotation
`firmware/src/annotated/teachbox.annotated.asm`:
- Added the **POS-DIGIT DIRECT ENTRY** section (accumulate at 0x0D65 + commit at
  0x0D9B/0x0D9F), tagged [BYTE][SIM].
- Updated the two prior `[INFER]` notes (POSITION-mode entry + open items) to
  point at the now-verified annotation.

### Test
`firmware/sim/tests/sim_teachbox.sh` — added section (5):
- accumulate: type 1→1, 2→12, 8→128 (asserts `0x6D`);
- commit: R4=2 / `0x6D=0x80` → axis-1 slot `0x51 = 0x80`.
Runs on stock `s51` (pure firmware, driven by pc/break).

### Verification
`make test` → **ALL TESTS PASSED** (golden byte-match for init+teachbox intact;
sim_init / sim_run / sim_teachbox green; sim_teachbox_module SKIPPED on stock
s51 as designed). New assertions all PASS.

## Key finding
Two ways to set an axis position from the teachbox, now both verified:
- **jog** (`kh_jog` 0x0E26): `@R1 ±1` per +/- press, clamped 0x00..0xFF.
- **direct entry** (`POS a . n`): decimal accumulate in `(0x6E:0x6D)` then
  `MOV @R1,0x6D` at 0x0D9F commits the typed value to slot `0x50+axis`.

## Open items (unchanged / next)
- Full **free-run** integration: inject the init ADC/INT1 gate → run main loop →
  hold a key across debounce → observe the servo ISR drive the motor, from a
  single `reset; run` (the current module demo drives stages via pc/break).
- Servo ISR motor drive (0x00C0 → 8255 Port A/C → L293) annotation + test.
- Teachbox LED output modelling in the cl_hw module (only the key-read path is
  modelled today).
- Local `main` still ahead of `origin/main`; nothing pushed. Commit pending.

## Provenance
Every claim tagged [BYTE]/[SIM]/[HW]/[INFER]. The POS-digit path is [BYTE] (ROM
bytes decoded) + [SIM] (ucSim: 1,2,8 → 128 → axis-1 slot 0x51 = 0x80).
