# Session: ROB3 Firmware — Annotate Initialization Sequence

**Date:** 2026-09-03
**Task:** Comment the assembler in `firmware/src/main.asm` (initialization sequence
first), producing a separate annotated file, verifying everything with the
`s51`/ucSim simulator and against the raw ROM bytes rather than assuming.

## Task Constraints (from user)

- Focus first on the initialization sequence.
- Do **not** annotate `mov R7, A` (the 0xFF EPROM padding).
- Produce `firmware/src/main.annotated.asm` (leave original pristine).
- Always verify with the simulator; step through to confirm.
- Simulator may be run non-interactively.
- Record the control-board IC list in the file header.

## Control Board IC List (recorded in annotated file header)

L293 x3, M34004, MAX1044, MM74C04N x2, 74LS244, 74HC14, 74HC373, 74LS138,
ADC, EPROM 8K, SRAM 8K, 8255, 8031.

Mapped to firmware behavior where possible:
- 8031 CPU, EPROM 8K = M2764A (this firmware), SRAM 8K = external program RAM
- 8255 = PPI (Ports A/B/C + control at DPH 0x50-0x53)
- 74LS138 = device-select decoder (DPH values on MOVX) [INFER]
- 74HC373 = AD0-AD7 address latch [INFER]
- 74LS244 = input buffer [INFER]
- L293 x3 = 6 motor channels -> 6 robot axes (Port A/C) [INFER mapping]
- ADC = axis feedback source at DPH 0x58/0x59 (feedback is ANALOG, not encoder) [INFER]
- MAX1044 = negative-rail generator (analog front end)
- MM74C04N/74HC14 = inverters / signal conditioning (e.g. P3.0 serial input) [INFER]
- M34004 = role not yet confirmed [INFER]

## Deliverable

`firmware/src/main.annotated.asm` — annotated **initialization sequence**:
- Reset + interrupt vector table (corrected, see findings)
- Full init body 0x0600 -> main-loop entry 0x074D
- Provenance tags on every claim: [BYTE] (verified from ROM bytes),
  [SIM] (simulator-verified), [INFER] (hypothesis, unproven)
- 0xFF padding intentionally not annotated
- Redundant `; ADDR: HEXBYTES MNEMONIC` marker comments removed at user request

## Key Findings (all byte-verified against firmware/bin/M2764A@DIP28.BIN)

### The disasm51 listing (main.asm) mislabels the vector area
- main.asm calls the reset target `jump_05FF`; the real reset entry is **0x0600**.
- Reset vector 0x0000 = `02 06 00` = LJMP 0x0600.

### Corrected interrupt vector map
| Vector | Addr  | Bytes      | Target / meaning |
|--------|-------|------------|------------------|
| RESET  | 0x0000| 02 06 00   | LJMP 0x0600 (init) |
| EXT0   | 0x0003| 02 00 40   | LJMP 0x0040 (motor pulse ISR) |
| TIMER0 | 0x000B| 02 00 80   | LJMP 0x0080 (system tick ISR) |
| EXT1   | 0x0013| 02 00 C0   | LJMP 0x00C0 (axis servo ISR) |
| TIMER1 | 0x001B| FF...      | unused gap (Timer 1 = baud gen only) |
| SERIAL | 0x0023| FF... 0x0035:02 03 00 | falls through to LJMP 0x0300 -> RS232 UART ISR |

### Serial / RS232 (corrected TWICE during session)
- The serial interrupt vector slot 0x0023 is 0xFF; execution falls through the
  0xFF fillers to **0x0035: LJMP 0x0300**, the real RS232 UART ISR.
- ISR @ 0x0300 prologue: PUSH PSW / SETB PSW.4 / JNB RI / CLR RI / MOV A,SBUF /
  reload serial timeout (0x18) — unmistakably the UART handler.
- Serial interrupt (ES) IS enabled: `MOV IE,#0x17` at 0x0739 (auto-detect path).
- Two earlier mistakes were caught and corrected: (1) first placed LJMP 0x0300
  at 0x0023 (wrong address), (2) then wrongly claimed no serial handler exists.

### Timer 1 vector gap / the `00 12 22` bytes at 0x0020
- Dead data. Timer 1 interrupt (ET1) is never enabled (IE writes 0x84/0x07/0x17,
  none set bit 3). Nothing branches to 0x0020. `12 22 FF` = LCALL 0x22FF is
  outside the 8 KB ROM, so it is not real code. Confirms the RE-notes artifact.

### Initialization sequence (0x0600), byte-verified
1. Power-on warm-up delay
2. Poke axis-select device (DPH=0x48)
3. 8255 config: Control=0x80 (all output), Port C=0x00, Port B=0xFF, Port A=0x00
4. Prime feedback/ADC device (DPH=0x59 = 0x01)
5. Clear internal RAM 0x7F..0x01, select bank 0
6. SP=0x31; display latch 0x47=0xFF; digital-out shadow 0x1F=0xFF
7. External SRAM probe (complement write/readback); page -> 0x3E/0x3F; base 0x8000, fallback 0xA0
8. Validate/rewrite 8-byte program-area header in SRAM; LCALL 0x0800
9. Seed axis subsystem; run one EXT1 feedback pass; IE=0x84
10. Copy 6 feedback readings (0x58..) -> current positions (0x50..)
11. Preset 6 axis speeds (0x48..0x4D) to 1
12. UART setup: TMOD=0x21, SCON=0x50 (mode 1, REN); P3.0 selects fixed vs auto-detect baud
13. Final: TH0=0xE8, start TR0, axis enable (0x20.0), select axis-0 feedback, EA=1 -> main loop

### Corrected SFR decodes found during verification
- 0x073F `75 8C E8` = MOV TH0,#0xE8 (0x8C = TH0, not TH1)
- 0x0742 `D2 8C` = SETB TR0 (bit 0x8C = TCON.4), starts Timer 0

## Verification Method (important)

### Simulator loader limitation (this environment AND user's machine)
- `s51`/ucSim 0.6.4. Loading via in-session `file` or CLI `-b` prints
  "Loading from ..." but code memory reads all 0xFF via `dc`/`dch` — firmware
  does not populate the disassembler's code-memory view here.
- Confirmed the same on the user's working machine (their `dc 0x600` also all FF).
- User's `dch 0 0x100` dump DID show correct vector bytes, matching our xxd
  ground truth exactly — so the ROM image content is confirmed.

### Assemble-and-diff equivalence check (the strong test we used)
- The original main.asm is disasm51 dialect and does NOT assemble under
  `sdas8051` (wrong syntax). It cannot be diffed directly.
- Instead: re-encoded the annotated init instructions in sdas8051 syntax,
  assembled with `sdas8051`, linked to Intel HEX, and compared emitted opcodes
  byte-for-byte against the ROM at the same addresses.
- **Result: 0 mismatches across 140 bytes** (vectors 0x0000-0x0013 + init
  0x0600..0x067D). This check caught two real annotation errors (the bogus
  0x0023 serial-vector claim and a DJNZ rel byte), which were then fixed.

## Tools / Environment

- `s51` (ucSim 0.6.4) present; `ucsim_51` not present (s51 is the equivalent).
- `sdas8051` + `sdcc` 4.2.0 available and used for the equivalence check.
- Working invocation on user's machine: `s51 -V -X 11.0592M -b <hexfile>`,
  then `br 0x600`, `run`. XTAL = 11.0592 MHz.

## Status

- [x] Vector table decoded and corrected
- [x] Initialization sequence (0x0600 -> 0x074D) annotated, [BYTE]-verified
- [x] Annotated file byte-equivalence confirmed via assemble-and-diff (0 mismatches)
- [x] Serial/RS232 path and Timer 1 gap resolved
- [x] IC list recorded in header
- [ ] Baud-detection inner loop (~0x06B6-0x073B) — entry annotated, body pending
- [ ] EXT0 motor ISR (0x0040), serial ISR (0x0300), main loop (0x074D) — later passes
- [ ] Dynamic [SIM] verification (probe branch taken, measured baud) — pending
      a working simulator load; use `where CODE 0x74 0x78 0xd8 0xfe` to locate
      the real load base on the user's machine
- [ ] Update docs/reverse_engineering_notes.md: serial ISR is at 0x0300
      (Timer 1 has no ISR), correcting the earlier "0x02FF Timer1 serial" note
