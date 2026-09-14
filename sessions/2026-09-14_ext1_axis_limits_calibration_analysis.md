# Session: ROB3 — annotate EXT1 axis servo ISR and investigate axis limits

**Date:** 2026-09-14
**Task:** Correctly annotate the External Interrupt 1 handler at `0x00C0`, explain
its control-flow labels and instructions, and determine how the robot's
per-axis mechanical limits and calibration values are represented.

Working method: verify against ROM bytes, existing simulator behavior, hardware
docs, and the [BYTE]/[SIM]/[HW]/[INFER] provenance convention. Do not promote
control-flow interpretations or mechanical assumptions to facts without
supporting evidence.

## Changes

Updated `firmware/src/annotated/main.annotated.asm`:

- Corrected the earlier mistake that treated Timer 0 at `0x0080` as "ISR1".
- Added the EXT1 axis-servo handler annotation at `0x00C0`.
- Annotated the handler instruction-by-instruction, including:
  - PSW/register-bank setup and axis pointer derivation.
  - ADC feedback branch and feedback-slot update.
  - Profile/error arithmetic and saturation paths.
  - Direction and speed state branches.
  - Port A/Port C shadow selection and motor-output table lookups.
  - Axis move-mask handling and round-robin ADC/channel advance.
  - Context restore and `RETI`.
- Added block-level explanations for every EXT1 control-flow label, including
  `ext1_limit_high`, `ext1_error_low`, `ext1_small_error`, profile branches,
  port paths, and `ext1_advance`.
- Kept fixed lookup-table motor polarity/output meanings marked `[INFER]` where
  the ROM bytes alone do not identify the L293 semantics.

## EXT1 control path [BYTE][HW][INFER]

- EXT1 is vector `0x0013 -> LJMP 0x00C0`.
- Hardware documentation identifies INT1/P3.3 as ADC end-of-conversion from
  the ADC0808/0809.
- The ISR processes one selected axis per interrupt and advances the rotating
  axis mask at `0x22`.
- Per-axis runtime areas currently documented are:
  - `0x40+N`: target-position area.
  - `0x48+N`: axis parameter/state input area used through the axis base pointer.
  - `0x50+N`: current-position/host-visible area.
  - `0x58+N`: ADC feedback values.
  - `0x70+N` and `0x78+N`: working/profile/state areas, still partly inferred.
- `0x4E` and `0x4F` are motor-output shadows written to 8255 Port A/C.
- `MOVC` lookups provide shared profile/output constants; they are not yet
  established as per-axis calibration storage.

## Axis limits and calibration findings

### Confirmed

- The axes do not need to rotate mechanically through 360 degrees; hardware
  documentation gives joint-specific ranges such as base `+80/-80`, shoulder
  `+70/-30`, and gripper `0..60 mm`.
- Firmware values are 8-bit and use `0x00..0xFF` as the apparent position/data
  domain.
- Startup enables one EXT1 cycle, reads feedback, then copies `0x58..0x5D`
  into `0x50..0x55` as initial current-position values.
- The EXT1 path uses ADC-derived values, arithmetic, profile tables, and move
  masks to drive the motor outputs.
- The ISR has `0x00` and `0xFF` assignments on low/high calculation paths. These
  are verified saturation values for an intermediate control quantity.
- The ISR clears/updates motion masks when the calculated error/state reaches
  its completion condition. A watchdog can also stop motion globally.
- INT0/P3.2 is a global emergency-off input. It is not confirmed as an
  individual per-axis limit input.

### Not established

- No explicit per-axis mechanical-limit constants were found in the inspected
  EXT1 path.
- No confirmed per-axis calibration table or homing routine was identified.
- The documented mechanical ranges have not been mapped to ADC codes or to
  `0x00..0xFF` values.
- The exact meaning of `subb A,R4` is unresolved: `A` is from the ADC/control
  read path while `R4` came from a `MOVC` lookup, so it must not yet be called
  a direct target-versus-feedback comparison.
- The exact roles of the `0x70+N` and `0x78+N` areas remain inferred from
  pointer arithmetic and consumers.
- It is unknown whether physical end stops are enforced by motor mechanics,
  analog feedback saturation, host-provided targets, undocumented board inputs,
  or a combination of these.

## Documentation correction

The annotation should not describe the `0x00`/`0xFF` branches as proven
mechanical end-stop enforcement. The accurate current statement is:

> The firmware saturates intermediate control values and stops when its internal
> motion-completion condition is met, but the mapping from each joint's physical
> range to firmware/ADC values and any hard-limit protection remain unresolved.

## Verification

- `git diff --check` passed.
- `make -C simulator verify` passed:
  - `init`: 333-byte golden match.
  - `teachbox`: 108-byte golden match.

## Open work

- Recover exact ROM addresses and contents of the EXT1 inline `MOVC` tables.
- Trace all reads/writes of `0x40..0x7F` through command handlers and the main
  motion executor.
- Determine whether host protocol commands write target, speed, deceleration,
  or calibration values for each axis.
- Search the full ROM and hardware docs for limit-switch, homing, or per-axis
  endpoint inputs before asserting software limit behavior.
- Use simulator experiments with controlled ADC values to observe when each
  axis's move mask clears and what output/shadow transitions occur.

## Status

No commit was created in this session. The annotated firmware file remains a
worktree modification.
