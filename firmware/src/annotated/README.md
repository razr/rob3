# ROB3 firmware — annotated, assembling source (1:1 with the ROM)

This directory holds the **annotated disassembly** of the ROB3 8031 firmware,
organized as an assembling source tree. The goal is a build whose 8 KB output
is **byte-identical** to the original EPROM image
(`firmware/bin/M2764A@DIP28.BIN`), while every instruction carries a
human-readable annotation and a provenance tag.

## Build

```bash
make            # assemble + link + pad to 8 KB  -> _build/rob3.bin
make verify     # cmp _build/rob3.bin against the ROM (the 1:1 test)
make regions    # dump each region's ROM slice under _build/rom/ (conversion aid)
make status     # list region files that still contain narrative gaps
make help
```

Toolchain: `sdas8051` + `sdld` (SDCC suite) + `objcopy` (binutils).

## Layout

One top unit includes the symbolic equates and every code region in address
order; the region files each `.org` at their true ROM offset.

```
rob3.asm            TOP: .include the inc/*.inc equates, then the regions,
                    in ascending address order; owns the FF padding fill.

vectors.asm     0x0000  reset + interrupt vector table (+ board / device map)
ext0_estop.asm  0x0040  EXT0  EMERGENCY-OFF ISR (INT0 = P3.2, active LOW)
timer0_tick.asm 0x0080  TIMER0 system-tick ISR
ext1_servo.asm  0x00C0  EXT1  axis-servo ISR (ADC EOC; round-robin 6 axes)
rs232.asm       0x0300  serial UART ISR + binary protocol dispatch + TX helper
init.asm        0x0600  reset initialization sequence
main.asm        0x074D  idle main loop (flag poll: teachbox / serial / program)
program.asm     0x0803  stored-program interpreter (prepare / exec / goto)
teachbox.asm    0x0C00  keypad scanner + editor + POS-digit entry + jog
tables.asm      0x0FC5  shared bit/const lookup tables (ROM tail)

inc/
  sfr.inc         8051 SFRs + bit addresses (architecture, not ROB3-specific)
  devices.inc     MOVX device windows (DPH selects: 8255 / ADC / aux / SRAM)
  system.inc      AUTHORITATIVE IRAM map (0x00..0x7F) + shared flag bytes
                  (0x20 system, 0x23 timer, 0x28 program/motion) with per-bit defs
  servo.inc       per-axis arrays (target/speed/curpos/fb/decel/ws) + servo masks
                  (0x21/0x22/0x2B/0x2C/0x2D) + port shadows            (ext1_servo.asm)
  teachbox.inc    keypad/editor state (0x46/0x47/0x56/0x57/0x29/0x2A)  (teachbox.asm)
  serial.inc      RS-232 workspace (0x24/0x25/0x60/0x68) + protocol constants (rs232.asm)
  program.inc     interpreter workspace (0x3E/0x3F/0x66/0x67/0x26/0x27) + opcodes (program.asm)
```

`system.inc` is the single place that documents the whole internal-RAM layout
and the cross-cutting flag bytes; each subsystem include owns the bytes/masks it
uses. There is intentionally **no** `adc.inc` — the ADC has no data structures
of its own, only the two MOVX windows (`devices.inc`) and the feedback array
(`servo.inc`).

## Provenance tags

Every firmware claim is tagged with how it was established:

- **[BYTE]** verified from the ROM bytes (byte-exact)
- **[SIM]**  verified by running the ROM in ucSim and observing state
- **[HW]**   confirmed against a hardware doc / bench bring-up
- **[INFER]** hypothesis, not yet proven

Unmarked instruction lines default to **[BYTE]**.

## Status / regenerating a region

The whole tree assembles to a **byte-identical 8 KB image** (`make verify` is
green; all 10 regions pass `make status`). The assembling bodies were produced
from the ROM with [disasm51](https://github.com/OlekMazur/disasm51) (the same
decoder that made `firmware/src/main.asm`) via `d51_to_sdas.py`, which renders
sdas8051-native syntax (0x.. hex, numeric bit addresses, in-region branch
targets as local labels, out-of-region/absolute targets as numbers). The
per-region annotation headers document each block; the assembling body follows.

To regenerate a region's assembling body from the ROM (needs disasm51 in a
venv, since the environment is externally-managed):

```bash
python3 -m venv /tmp/d51venv && /tmp/d51venv/bin/pip install disasm51
/tmp/d51venv/bin/python d51_to_sdas.py \
    ../../bin/M2764A@DIP28.BIN <org_hex> <len_dec> > body.asm
# then splice body.asm under the region file's annotation header and:
make verify-region REGION=<name>
```

Golden discipline: never claim 1:1 until `cmp` proves it — `make verify` is that
proof (it prints matching SHA-256 hashes for the assembled image and the ROM).
