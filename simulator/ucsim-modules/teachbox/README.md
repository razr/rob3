# ROB3 Teachbox — ucSim hardware module (`cl_teachbox`)

A compile-time ucSim peripheral that attaches the ROB3 Teachbox key matrix to
the simulated 8031, so the firmware's keypad scanner reads "pressed" keys from a
modelled device instead of hand-injected P1 values.

For build/registration steps and the shared gotchas, see the
[parent README](../README.md).

## Files

| File | Purpose |
| :--- | :------ |
| `teachbox.cc`  | The `cl_teachbox` peripheral implementation. |
| `teachboxcl.h` | Its class declaration. |

## What it models

The Teachbox is a 5x5 key matrix on the DB25. The firmware scans it by driving a
row strobe through the 8255 (Port B, XRAM `0x5100`) into a 74LS138, and reading
the column returns on **P1 (SFR `0x90`)**, top 3 bits = the three column groups
(group 1 = P1.5, group 2 = P1.6, group 3 = P1.7). See `hardware/teachbox/`.

The module:
- registers the **P1 SFR cell**: on read it drives the column-group bit for the
  pressed key **iff** the strobed row matches (columns idle LOW, so the scan can
  proceed when nothing is pressed);
- registers the **XRAM `0x5100`** cell (8255 Port B): on write it captures the
  row strobe so it knows which row is active.

## Commands

```
set hardware teachbox <row> <group>   # row 0..7, group 1..3
set hardware teachbox <n>             # single arg = release
```

## Status: calibrated & verified

- Registers as a `HW_GPIO` element, responds to `set hardware teachbox`, and a
  press is detected by the real firmware scanner (`kbd_scan`, 0x0C00) on the
  correct strobed row.
- **Strobe→row decode.** The firmware seeds the strobe from `0x47 & 0x0F` and
  advances the **high nibble** by `+0x10` per row (`no_hit: add A,#0x10`),
  recovering the row as `(strobe >> 4) & 7` (`swap A / anl A,#0x07`). So
  `strobed_row() = cur_strobe >> 4` is exactly the firmware's own numbering.
  Verified in ucSim: pressing row R makes the scanner see the column only at
  strobe `0x46 == (R<<4)` for R = 0..7. Covered by
  `../../tests/sim_teachbox_module.sh`.

The `read()` override returns the column bits directly (idling the 3 column
lines LOW), not `port_pins`-masked data — otherwise the undriven-HIGH default
makes the scanner see a phantom row-0 hit.

## What works: key press → axis motion

Three verified stages connect a key to a robot axis moving; the automated
end-to-end run is `../../tests/demo_teachbox_axis.sh` (`make demo-teachbox`).

1. **Press → scanner sees it.** `set hardware teachbox <row> <group>` holds a
   key; `kbd_scan` (0x0C00) detects it on the strobed row matching `<row>`
   (verified: hit at strobe `0x46 == row<<4`).
2. **Axis-select.** `kbd_handle` (0x0C80) turns a numeric key index into an
   axis: `R1 = 0x50+axis`, mode `0x29 = 0x40` (POSITION). (key index 2 → axis 0.)
3. **Jog.** `kh_jog` (0x0E26) with `ACC.0=0`/`1` increments/decrements the
   selected axis's position slot `@R1` (`0x50+axis`), clamped `0x00..0xFF`.

Minimal interactive drive of stage 1 (prove the press is seen):
```bash
cp firmware/hex/M2764A@DIP28.HEX /tmp/rob3.hex
printf 'set hardware teachbox 1 1\nreset\npc 0x0c00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nbreak 0x0c2a\nrun\ndump iram 0x46 0x46\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M /tmp/rob3.hex     # -> 0x46 = 0x10 (row 1)
```

See also `../../../firmware/src/annotated/teachbox.asm`,
`../../tests/sim_teachbox_module.sh` (module end-to-end), and
`../../tests/sim_teachbox.sh` (P1-injection scanner/handler decode).

## Free-run status

The Teachbox demo still uses `pc`/`break` staging, because the keypad
**debounce** (state in `0x56`/`0x57` + flags `0x20.5/.6`) needs several
main-loop passes. The other historical free-run blocker — the un-modelled
ADC/INT1 gate that stalled init at `0x0680` — is solved by the [ADC
module](../adc/README.md): with it compiled in, `reset; run` boots through init
into the main loop on its own. Holding a key across debounce in a free-running
boot and watching the servo ISR drive the motor is the remaining integration
step.
