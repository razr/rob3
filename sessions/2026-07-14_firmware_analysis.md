# Session: ROB3 Firmware Initial Analysis

**Date:** 2026-07-14
**Task:** Analyze `firmware/src/main.asm` as described in `ROB3_FIRMWARE_REENGINEERING.md`

## What Was Done

1. Read and understood `ROB3_FIRMWARE_REENGINEERING.md` (project goals, hardware specs, deliverables)
2. Read and understood `KIRO_INSTRUCTIONS.md` (analysis rules, deliverable structure)
3. Performed full analysis of `firmware/src/main.asm` (7183 lines, 8KB EPROM)
4. Created all initial documentation files

## Key Findings

### Firmware Structure
- **Total ROM:** 8192 bytes (M2764A EPROM)
- **Actual code:** ~4 KB (0x0000–0x0FDE), rest is 0xFF padding
- **Architecture:** Interrupt-driven cooperative multitasking
- **4 ISRs:** Ext Int 0 (motor pulse), Timer 0 (5ms tick), Ext Int 1 (axis servo), Timer 1 (serial comms)
- **Main loop:** at 0x074D, polls ISR-set flags

### Hardware Identified
- **8255 PPI:** Port A (DPH=0x50), Port B (DPH=0x51), Port C (DPH=0x52), Control (DPH=0x53)
- **Axis multiplexer:** DPH=0x48 (select), DPH=0x58/0x59 (feedback read)
- **External RAM:** Auto-probed at startup (DPH ≥ 0xA0), stores robot programs
- **Serial:** Mode 1 UART, baud auto-detect from incoming signal

### Subsystems Recovered
1. **Axis servo controller** (6 axes, round-robin in ext int 1)
2. **Binary serial protocol** (host communication, program upload/download)
3. **Teach pendant/keyboard** (scan matrix, debounce, command editor)
4. **Program interpreter** (executes stored motion sequences from ext RAM)
5. **Motion executor** (manages axis trajectories with accel/decel profiles)

### Axis Mechanical Limits (from updated docs)
| Axis | Joint | Symbol | Range | Resolution |
|------|-------|--------|-------|------------|
| 0 | Base rotation | q1 | +80° to −80° | 0–255 |
| 1 | Shoulder | q2 | +70° to −30° | 0–255 |
| 2 | Elbow | q3 | 0° to −100° | 0–255 |
| 3 | Wrist | q4 | +100° to −100° | 0–255 |
| 4 | Wrist roll | q5 | +100° to −100° | 0–255 |
| 5 | Gripper | — | 0–60 mm | 0–255 |

All positions are 8-bit. Firmware uses zero-based numbering.

### Memory Map Summary
- 0x00–0x07: Register bank 0 (main)
- 0x08–0x0F: Register bank 1 (ISRs)
- 0x10–0x17: Register bank 2 (serial)
- 0x20–0x2F: Bit-addressable flags
- 0x40–0x45: Axis targets
- 0x48–0x4D: Axis speeds
- 0x50–0x55: Axis current positions
- 0x58–0x5D: Axis feedback values
- 0x60–0x65: Serial RX buffer
- 0x66–0x67: Program counter
- 0x70–0x75: Deceleration profiles
- 0x78–0x7F: ISR workspace

## Files Created

| File | Description |
|------|-------------|
| `docs/reverse_engineering_notes.md` | Complete firmware map, interrupt handlers, protocol, function table |
| `docs/8031_sfr_map.md` | SFR usage, timer configs, port pin assignments |
| `docs/8255_mapping.md` | PPI port functions, address decoding, bit assignments |
| `docs/axis_state_machine.md` | Axis control flow, data structures, motion algorithm |

## Open Questions / Next Steps

1. Decode acceleration/deceleration lookup table at ~0x0145
2. Map exact bit assignments in Port A/C for each motor phase
3. Confirm 8255 address decoding hardware
4. Identify servo feedback hardware (encoder type)
5. Decode program instruction set completely
6. Map P3 pin assignments to physical connectors
7. Begin C conversion starting with:
   - `hardware.c` / `hardware.h` (SFR definitions, external device access)
   - `ppi8255.c` / `ppi8255.h` (8255 port abstraction)
   - `main.c` (initialization, main loop skeleton)
   - ISR handlers

## Status

- [x] Import original 8031 disassembly
- [x] Identify reset/startup code
- [x] Map memory and registers
- [x] Identify interrupts
- [ ] Recover communication protocol (partially done)
- [ ] Convert functions incrementally
- [ ] Validate against original firmware behavior
