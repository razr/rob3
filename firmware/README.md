# ROB3 Onboard Firmware (8031 Controller)

This directory contains the original binary image extracted from the ROB3’s local controller board, alongside the workspaces required to reverse-engineer and reconstruct its assembly source code.

## Binary Specifications

*   **Source File:** [`M2764A@DIP28.BIN`](M2764A@DIP28.BIN)
*   **Target Memory Chip:** STMicroelectronics / Intel `M2764A`
*   **Package Layout:** Dual-in-Line 28-Pin (DIP28) Ceramic Window Package
*   **Memory Type:** Non-Volatile UV-Erasable EPROM
*   **Storage Density:** 64 Kbit organized as **8,192 words × 8-bit (8 KB)**
*   **Processor Architecture:** Intel 8031 / 8051 MCS-51 Harvard Architecture

## Memory Mapping Constraints

The Intel 8031 is a ROMless microcontroller relying on this external 8 KB EPROM chip for code execution. Keep these hardware parameters in mind during reverse engineering:

1.  **Code Space (Program Memory):** Maps from address `0x0000` to `0x1FFF`.
2.  **Reset Vector:** Initial boot execution branches instantly from `0x0000`.
3.  **Interrupt Vectors:** Ensure the instruction streams surrounding `0x0003` (External 0), `0x000B` (Timer 0), and `0x0023` (Serial RI/TI) are locked as code boundaries rather than data arrays.

## Disassembly and Tooling Workflow

To regenerate code blocks from the raw byte segments, process the binary through custom reverse engineering suites mapping the explicit MCS-51 register definitions.

### Option A: Command Line Disassembly (d51)
```bash
d51 -o src/main.asm M2764A@DIP28.BIN
```

### Option B: Interactive Static Analysis (Ghidra)
1. Import `M2764A@DIP28.BIN` as a **Raw Binary**.
2. Select Language Processor: **8051 / MCS-51 (8-bit)**.
3. Configure the block to initialize memory boundaries mapping natively from address `0x0000`.
