# Session: symbolic-equates header for the annotated disassembly

**Date:** 2026-09-16
**Task:** Replace magic numbers (`0x22`, `0x22.7`, `0x58`, ...) in the annotated
asm with named symbols. Created a shared SDAS/ASxxxx include and applied it.

## New: `firmware/src/annotated/rob3.inc`
Symbolic equates for the ROB3 data model, named per the rob3-firmware-map skill:
- SFRs (P1/P3/DPL/DPH/TH0/TL0/TCON/SCON/IE/B/ACC/PSW) + bit addrs (PSW_RS0,
  IE_EA, TCON_TR0).
- MOVX device windows (DEV_8255_PA/PB/PC/CTRL, DEV_ADC_START/DATA, DEV_AUX_LATCH,
  DEV_SRAM).
- Per-axis IRAM arrays (TARGET/SPEED/CURPOS/FB/DECEL/ISRWS `_BASE`).
- Shared masks/flags (AXIS_MASK, AXIS_ACTIVE, NEED_MOVE, MOVING, DIRECTION,
  PORTA/C_SHADOW, EDIT_MODE/STATE, ...).
- Bit-address symbols with the 8051 convention documented: bitaddr =
  (byte-0x20)*8 + bit for RAM 0x20..0x2F (e.g. AXIS_MASK_B7 = 0x17), and
  SFR-byte+bit for SFRs (IE_EA=0xAF, TCON_TR0=0x8C). All bit math hand-verified.
- Teachbox/editor + program/serial symbols (LED_LATCH, KBD_STROBE,
  KBD_DEBOUNCE0/1, ARG_ACC_LO/HI, EDIT_ERR_B5/6/7, EDIT_MODE_B3, PROG_PAGE, ...).

Notes the well-known byte-vs-bit numeric collisions inline (e.g. TCON_TR0 bit
0x8C == TH0 byte 0x8C; EDIT_ERR bits 0x56/0x57 == debounce bytes 0x56/0x57).

## Applied `.include "rob3.inc"` + symbolized operands
Every changed line keeps the RAW address (and, in teachbox, the opcode bytes) in
a trailing comment so byte-match traceability is preserved.

- **`ext1_axis_servo.annotated.asm`** — fully symbolized (entry/feedback/control/
  port-select/advance). SFRs, device windows, AXIS_MASK bits, TMR_PHASE bits,
  port shadows.
- **`teachbox.annotated.asm`** — fully symbolized (kbd_scan, kbd_evt, kbd_handle
  axis-select, kh_jog, pos_digit/pos_commit). Carefully handled the byte-vs-bit
  collisions (EDIT_ERR bits vs debounce bytes) using the bit symbols; left the
  narrative "byte-vs-bit gotcha" notes with raw addresses on purpose.
- **`main.annotated.asm`** — PARTIALLY symbolized: init/axis-seed and UART/timer
  setup (AXIS_MASK, ADC device, IE/EA, TCON/SCON, FB/CURPOS/SPEED bases,
  P3.0/P3.2, baud-ready flag). The baud-measure / timer-tick region where the
  SAME operand value 0x8C means TH0-byte on one line and TR0-bit on the next was
  **intentionally left raw** — its existing comments already teach that hazard,
  and symbolizing there would risk the exact byte/bit bug. Follow-up: finish the
  rest of main once reviewed.

## Provenance / verification
- Addresses are [BYTE] (from the ROM / firmware-map); a few flag-bit ROLES stay
  [INFER] and are marked.
- NOT assembled: the annotated files are documentation and are not part of the
  golden byte-match build (which uses simulator/*.a51), and no SDAS toolchain is
  confirmed in this env. Risk is limited to name/address correctness, which was
  cross-checked against the firmware-map and the bit math hand-verified.

## Follow-up
- Finish symbolizing the remainder of `main.annotated.asm` (baud-measure, timer
  ISR, main loop) with the same raw-in-comment discipline.
