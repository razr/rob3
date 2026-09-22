---
name: mcs51-assembly
description: >
  Intel MCS-51 (8051/8031) assembly language programming, reading, and
  annotation. Covers the instruction set, addressing modes, SFRs, bit
  addressing, interrupt vectors, external-memory (MOVX) access, and the
  SDCC sdas8051 / ASxxxx toolchain. Use when writing, disassembling,
  byte-matching, or annotating 8051/8031 firmware.
metadata:
  globs: ["**/*.asm", "**/*.a51", "**/*.s51", "**/*.rel", "**/*.lst"]
---

# MCS-51 / 8031 Assembly

> Generic Intel MCS-51 reference. For debugging/simulating with ucSim see
> `mcs51-debugging`; for driving/extending ucSim see `ucsim`; for writing C see
> `mcs51-c-programming`. Board- and project-specific memory maps, entry points,
> and build workflows belong in a project skill, not here.

## Core architecture facts (memorize these)

- **Harvard-ish**: separate CODE (program, read via `PSEN`) and XDATA
  (external data, read/written via `MOVX` + `RD`/`WR`) address spaces, both up to
  64 KB, plus 128/256 B internal RAM (IRAM) and the SFR block.
- **8031 vs 8051**: the 8031 has **no on-chip ROM** and must boot from external
  program memory, so `EA` (pin 31) is tied to select external fetch. The 8051
  has internal ROM. Reset vector is `0x0000` on both.
- **8-bit accumulator (`A`), `B` register, 16-bit `DPTR`** (`DPH:DPL`) is the only
  16-bit pointer and is the workhorse for `MOVX`/`MOVC`.
- **Four register banks** (R0–R7) live in IRAM `0x00–0x1F`; the active bank is
  chosen by `PSW.RS1:RS0` (bits 4:3). Switch banks in ISRs to avoid clobbering
  the main program's R0–R7.

## Memory spaces and how to touch them

| Space   | Size   | Access instruction              | Selected by        |
| :------ | :----- | :------------------------------ | :----------------- |
| CODE    | 64 KB  | `MOVC A,@A+DPTR` / `@A+PC`      | `PSEN` (ROM)       |
| XDATA   | 64 KB  | `MOVX A,@DPTR` / `MOVX @DPTR,A`| `RD`/`WR` + decode |
| IRAM    | 256 B  | `MOV`, `@R0`/`@R1` (indirect)   | on-chip            |
| SFR     | 128 B  | direct `MOV` to 0x80–0xFF       | on-chip            |
| bit     | 256 b  | `SETB`/`CLR`/`JB`/`JNB`/`MOV C`| bit-addressable    |

> **IRAM direct vs indirect (recurring pitfall):** direct addressing `0x80–0xFF`
> hits **SFRs**; indirect `@R0/@R1` with the same value hits **upper IRAM**
> (only on 256-byte-RAM parts). They are different memories at the same numeric
> address.

## Addressing modes

```asm
    MOV  A, #0x50        ; immediate
    MOV  A, 0x50         ; direct  (IRAM/SFR byte at 0x50)
    MOV  A, @R0          ; register-indirect (IRAM)
    MOV  A, R7           ; register
    MOVX A, @DPTR        ; external data read  (RD strobe)
    MOVC A, @A+DPTR      ; code/table read     (PSEN strobe)
    MOVC A, @A+PC        ; PC-relative table read
```

## Bit addressing (the #1 disassembly trap)

`SETB` / `CLR` / `CPL` / `JB` / `JNB` / `JBC` / `MOV C,bit` operands are **bit
addresses**, which collide numerically with byte addresses. Always resolve to
`(byte, bit)` before annotating:

- Bit space `0x00–0x7F` = bits of IRAM bytes `0x20–0x2F` (`byte = 0x20 + bit/8`,
  `bit = addr & 7`). Example: `JB 0x57` → bit `0x2A.7`, **not** RAM byte `0x57`.
- Bit space `0x80–0xFF` = bits of the bit-addressable SFRs (P0, TCON, P1, SCON,
  P2, IE, P3, IP, PSW, ACC, B). Example: `SETB 0x8C` → `TCON.4 (TR0)`,
  **not** the `TH0` byte at `0x8C`.

```asm
    SETB 0xD0.3          ; PSW.RS0  -> select register bank 1 (common ISR pattern)
    JB   0x22.0, label   ; test bit 0 of IRAM byte 0x22
```

## Interrupt vectors (8-byte spacing)

| Source        | Vector  | Flag      | Enable bit |
| :------------ | :------ | :-------- | :--------- |
| Reset         | `0x0000`| RST pin   | —          |
| INT0          | `0x0003`| IE0/TCON.1| IE.EX0     |
| Timer0        | `0x000B`| TF0/TCON.5| IE.ET0     |
| INT1          | `0x0013`| IE1/TCON.3| IE.EX1     |
| Timer1        | `0x001B`| TF1/TCON.7| IE.ET1     |
| Serial (RI/TI)| `0x0023`| SCON.0/.1 | IE.ES      |

Only 8 bytes per slot, so real handlers usually `LJMP` out:

```asm
    .org 0x0000
    ljmp  init          ; 0x0000 reset
    .org 0x0013
    ljmp  int1_handler  ; 0x0013 external interrupt 1
```

## Common SFRs

`P0=0x80 SP=0x81 DPL=0x82 DPH=0x83 PCON=0x87 TCON=0x88 TMOD=0x89`
`TL0=0x8A TL1=0x8B TH0=0x8C TH1=0x8D P1=0x90 SCON=0x98 SBUF=0x99`
`P2=0xA0 IE=0xA8 P3=0xB0 IP=0xB8 PSW=0xD0 ACC=0xE0 B=0xF0`

## Idiomatic patterns you will read and write

### Memory-mapped peripheral write via DPTR
```asm
    mov   0x83, #0x50    ; DPH = 0x50  -> selects an XDATA device window
    mov   A, shadow      ; a RAM shadow copy of the port
    movx  @DPTR, A       ; drive the pins (WR strobe)
```
> When an external address decoder (e.g. a 74LS138) uses only the high address
> lines, `DPH` acts as the device selector and `DPL` is often don't-care. The
> exact decode is board-specific — see your hardware skill.

### Code table lookup
```asm
    mov   A, index
    movc  A, @A+DPTR     ; DPTR = table base in CODE space
```

### Timer 0 as a periodic tick (mode 1, 16-bit)
```asm
    anl   TMOD, #0xF0
    orl   TMOD, #0x01    ; T0 = mode 1
    mov   TH0, #0xE8     ; reload high (choose for desired period @ your xtal)
    mov   TL0, #0x11     ; reload low
    setb  TR0            ; = SETB TCON.4
    setb  ET0            ; enable T0 interrupt
    setb  EA
```

### ISR bank-switch + context save
```asm
int1_handler:
    mov   R7, A          ; stash A in current bank first
    push  PSW            ; = push 0xD0
    setb  PSW.3          ; RS0=1 -> bank 1 (isolate ISR registers)
    ; ... handler body uses bank-1 R0..R7 ...
    pop   PSW
    reti
```

## SDCC assembler (sdas8051 / ASxxxx) essentials

The SDCC ASxxxx suite assembles with **sdas8051** and links with **sdld**, then
`objcopy` (binutils) converts Intel HEX to raw binary.

- Directives: `.area CODE (ABS)`, `.org`, `.db`/`.byte`, `.dw`, `.ascii`, `.ds`,
  `.equ`/`.set`, `.include`.
- Numbers: **sdas8051 uses `0x` and C-style**. Do not mix in `asem-51`/`a51`
  (`#0FFh`) syntax.
- For byte-exact ROM transcriptions, emit raw `.db` bytes so a `cmp` against the
  image is exact.

```bash
sdas8051 -o -l -s out.rel in.a51        # assemble (list + symbols)
sdld -i -m -b CODE=0x0600 out.ihx out.rel
objcopy -I ihex -O binary out.ihx out.bin
```

## Annotating disassembly (general workflow)

1. Confirm the **real entry address from the ROM bytes**, not the disassembler's
   label. `0xFF` padding decodes as `MOV R7,A` and shifts instruction
   boundaries, producing off-by-one labels.
2. Resolve every bit operand to `(byte, bit)` before writing a comment.
3. Track `DPH` writes; on boards with high-address decode each one selects a
   device window (see your hardware skill).
4. Keep an annotated `.asm` byte-faithful if a golden byte-match test depends on
   it.

## When to use this skill

- Reading or annotating `*.asm` 8051/8031 listings (disasm51 or sdas8051 syntax).
- Writing new 8031 assembly or byte-exact transcriptions for the golden build.
- Using **disasm51** (`pip install disasm51`) to disassemble a ROM binary, or
  `d51_to_sdas.py` to convert its output to sdas8051-assemblable source.
- Diagnosing bit-vs-byte, bank-switch, or MOVX device-select bugs.
- Setting up timers, UART, or interrupt vectors on the 8051/8031.
