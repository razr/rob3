# Kiro AI Instructions - ROB3 Firmware Reengineering

## Project Context

This project is a reverse engineering effort to recover and modernize the firmware of the ROB3 industrial robot.

The original firmware is available as an 8031/MCS-51 assembly disassembly:

```
firmware/src/main.asm
```

The target implementation language is C compiled with:

- Compiler: SDCC (Small Device C Compiler)
- Target: Intel 8051/MCS-51 architecture

The goal is to reproduce the original firmware behavior, not to redesign the system.

---

# Initial Instructions

Before generating any code:

1. Read and understand: `ROB3_FIRMWARE_REENGINEERING.md`
2. Analyze the original firmware: `firmware/src/main.asm`
3. Create and maintain reverse engineering notes: `docs/reverse_engineering_notes.md`


Do not start large-scale code conversion before understanding the firmware structure.

---

# Assembly Analysis Rules

When analyzing `main.asm`:

- Treat the assembly code as the source of truth.
- Do not assume function boundaries from labels alone.
- Identify:
  - reset vector
  - interrupt handlers
  - subroutines
  - state machines
  - global variables
  - hardware accesses
  - communication routines

For each discovered function document:

- Original address
- Purpose
- Input registers
- Output registers
- Modified memory locations
- Hardware dependencies

Example:

```
Function:
Address:
Purpose:
Inputs:
Outputs:
Hardware:
Notes:
```


---

## Deliverables

The final project should contain:

```
rob3/

├── ROB3_FIRMWARE_REENGINEERING.md
├── KIRO_INSTRUCTIONS.md

├── firmware/src/
│   └── main.asm

├── src/
│   ├── main.c
│   ├── robot.c
│   ├── axis.c
│   ├── protocol.c
│   ├── serial.c
│   ├── ppi8255.c
│   └── hardware.c

├── include/
│   ├── robot.h
│   ├── axis.h
│   ├── protocol.h
│   ├── ppi8255.h
│   └── hardware.h

└── docs/
    ├── reverse_engineering_notes.md
    ├── 8031_sfr_map.md
    ├── 8255_mapping.md
    └── axis_state_machine.md
```
