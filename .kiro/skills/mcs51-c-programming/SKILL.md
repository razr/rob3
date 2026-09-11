---
name: mcs51-c-programming
description: >
  Writing C for the Intel 8051/8031 with SDCC: memory models (data/xdata/code/
  idata/pdata), the __sfr / __sbit / __at keywords, memory-mapped peripheral
  access, interrupt service routines (__interrupt / __using), reentrancy limits,
  and the sdcc + packihx + ucSim build flow. Use when writing or porting C
  firmware for an 8051/8031 target.
metadata:
  globs: ["**/*.c", "**/*.h"]
---

# 8051/8031 C Programming (SDCC)

> Generic SDCC-for-MCS-51 reference. For the assembly it compiles to see
> `mcs51-assembly`; for simulating/debugging the result see `mcs51-debugging`
> and `ucsim`. Board-specific peripheral addresses and build locations belong
> in a project skill — the examples below use placeholder addresses.

## The golden rule: the 8051 is not a flat-memory machine

SDCC exposes the MCS-51 memory spaces as **storage classes**. Choosing the wrong
one silently costs code size, speed, or correctness. Pick deliberately.

| Storage class | Region                 | Access cost      | Use for |
| :------------ | :--------------------- | :--------------- | :------ |
| `__data`      | lower 128 B IRAM       | fastest, direct  | hot locals, counters |
| `__idata`     | upper 128 B IRAM       | indirect `@Ri`   | stack-ish scratch |
| `__pdata`     | 256 B XDATA page       | `MOVX @Ri`       | small paged buffers |
| `__xdata`     | 64 KB external RAM     | `MOVX @DPTR`     | large buffers, MMIO |
| `__code`      | program memory (ROM)   | `MOVC`           | const tables, strings |

```c
__data   unsigned char tick;         // fast on-chip
__xdata  unsigned char frame[64];    // external SRAM
__code   const unsigned char sine[256] = { /* ... */ };  // in ROM
```

Default data model is set with `--model-small` (default), `--model-large`, etc.
For an 8031 with real external SRAM, `small` with explicit `__xdata` on big
objects is usually best.

## Memory-mapped peripherals

When devices are selected by the high address byte (a common external-decode
scheme), declare them at their XDATA address with `__at` and read/write like
variables — the compiler emits the `MOVX` with the right `DPTR`. Use the actual
addresses from your board's memory map.

```c
/* Example: a parallel-I/O device mapped into XDATA (addresses are placeholders) */
__xdata __at (0x5000) volatile unsigned char PORTA;
__xdata __at (0x5100) volatile unsigned char PORTB;
__xdata __at (0x5200) volatile unsigned char PORTC;
__xdata __at (0x5300) volatile unsigned char CTRL;

void ppi_init(void) {
    CTRL  = 0x80;   /* device-specific mode/config word */
    PORTA = 0x00;
    PORTB = 0xFF;
    PORTC = 0x00;
}
```

> **Always `volatile`** on MMIO and on any variable shared with an ISR, or SDCC
> will optimize away the very reads/writes that touch hardware.

## SFR and bit access

```c
#include <mcs51/8051.h>   /* SDCC ships SFR headers: P0,P1,TCON,TMOD,IE,SCON... */

/* or declare explicitly: */
__sfr __at (0x90) P1;
__sbit __at (0x90^0) P1_0;     /* bit 0 of P1  */
__sbit __at (0xB0^3) P3_3;     /* P3.3 (INT1 pin) */
```

Use the header names (`TR0`, `ET0`, `EA`, `REN`, ...) rather than magic bit
numbers — this is the C analogue of resolving bit-vs-byte in assembly.

## Interrupts

SDCC maps ISRs to vectors with `__interrupt(n)`; `__using(b)` picks a register
bank so the ISR does not clobber the main program's R0–R7 (the C equivalent of
the assembly `SETB PSW.3` bank-switch pattern).

| n | Source  |
| - | :------ |
| 0 | INT0    |
| 1 | Timer0  |
| 2 | INT1    |
| 3 | Timer1  |
| 4 | Serial  |

```c
volatile __data unsigned char sample;

void int1_isr(void) __interrupt(2) __using(1) {
    sample = SOME_MMIO_REG;          /* read a data-ready peripheral */
    /* keep it short; do real work in the main loop from volatile flags */
}
```

ISR rules:
- Keep them short; do real work in the main loop from `volatile` flags.
- Anything an ISR and main both touch must be `volatile`; guard multi-byte
  shared state (disable `EA` around the read, or double-buffer).
- Don't call non-reentrant functions from an ISR (see below).

## Reentrancy and the stack (critical 8051 gotcha)

By default SDCC uses **static overlay** for function locals/parameters (there is
no cheap stack-relative addressing on the 8051). Consequences:

- A function is **not reentrant** by default. Calling the same function from both
  main and an ISR, or recursively, corrupts its overlaid locals.
- Mark functions that need it `__reentrant` (locals go on a simulated stack —
  slower, larger). Keep reentrant use minimal.
- Watch the stack: the 8051 hardware stack lives in IRAM and is tiny. Deep call
  chains + banks + overlay can collide. Budget IRAM against your `SP` init value.

## Fixed-point, not floating-point

Avoid `float`/`double` — SDCC's soft-float is huge and slow on the 8031. Use
integer/fixed-point math and lookup `__code` tables. Prefer
`unsigned char`/`unsigned int` sized to the data.

## Build flow (SDCC → HEX → ucSim)

```bash
sdcc -mmcs51 --model-small --code-loc 0x0000 --xram-loc 0x0000 \
     --xram-size 8192 -o build/ main.c
packihx build/main.ihx > build/main.hex     # tidy Intel HEX
# simulate (see mcs51-debugging / ucsim):
s51 -t 51 -X <xtal> build/main.hex
```

Match `--code-loc`, `--xram-loc`, `--xram-size`, and `-X <xtal>` to the real
board. Verify the linker map so nothing overlaps peripheral windows.

## Checklist before flashing/simulating

- [ ] Big objects explicitly `__xdata` / `__code`, not defaulted to IRAM.
- [ ] All MMIO and ISR-shared variables are `volatile`.
- [ ] ISRs use `__interrupt(n)` with the correct `n` and a dedicated `__using`.
- [ ] No `float`/`double`; math is integer/fixed-point + `__code` tables.
- [ ] Reentrancy considered; shared functions marked `__reentrant` or not shared.
- [ ] Linker map checked: code/xram sizes and locations match the board.

## When to use this skill

- Writing new 8051/8031 firmware or utilities in C with SDCC.
- Declaring memory-mapped peripherals from C.
- Debugging ISR corruption, reentrancy, or wrong-memory-space bugs.
- Porting assembly routines to C while keeping the same hardware behavior.
