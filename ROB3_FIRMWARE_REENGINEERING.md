# ROB3 Firmware Reengineering Project

- **Robot:** ROB3 industrial robot
- **Axes:** 6-axis robot
- **Axis numbering:** Axis 0 = robot base axis, Axis 5 = gripper axis

## Overview

This project aims to reverse engineer and modernize the firmware of the ROB3 industrial robot controller by converting the original Intel 8031 assembly firmware into structured and maintainable C source code.

The original firmware was developed for an 8031/MCS-51 microcontroller and is available only as a disassembled assembly listing. The objective is to recover the original firmware architecture, understand the low-level hardware interactions, and recreate the functionality in C while preserving the original behavior.

This project focuses on firmware understanding, documentation, and migration rather than redesigning the robot controller.

---

## Project Goals

The main goals are:

- Analyze the disassembled 8031 assembly firmware.
- Recover the original software structure and execution flow.
- Identify functions, state machines, variables, and hardware dependencies.
- Translate assembly routines into equivalent C implementations.
- Preserve timing behavior and communication protocols.
- Create maintainable and documented firmware source code.

---

## Target Hardware

### Robot System

- **Robot:** ROB3 industrial robot
- **Controller:** Custom embedded controller
- **CPU:** Intel 8031 / MCS-51 family microcontroller
- **Firmware size:** Approximately 8 KB
- **Original language:** 8031 assembly
- **Target language:** Embedded C

---

## Reverse Engineering Scope

The analysis should identify and document:

### Startup and Initialization

- Reset vector
- Hardware initialization
- Memory initialization
- Peripheral setup
- Default robot state

### Interrupt System

- Interrupt vectors
- Timer interrupts
- Serial interrupts
- External interrupts
- Interrupt-driven state updates

### Communication System

Recover the serial communication protocol:

- RS-232 interface
- Command format
- Data packets
- Command parsing
- Response handling
- Error handling

### Robot Control

Analyze and reconstruct:

- Axis control logic
- Servo commands
- Position handling
- Motion states
- Speed control
- Limit handling
- Emergency stop behavior


### Motor and Axis Interface Mapping

The ROB3 robot has six controlled axes.

Axis numbering used by the original firmware:

| Axis | Function |
|------|----------|
| Axis 0 | Base rotation |
| Axis 1 | Shoulder |
| Axis 2 | Elbow |
| Axis 3 | Wrist |
| Axis 4 | Wrist roll |
| Axis 5 | Gripper |

### ROB3 Axis Mechanical Limits

The ROB3 robot uses five rotational joints plus an electric gripper.

| Firmware Axis | Joint | Symbol | Motion Range | Resolution |
|---|---|---|---|---|
| Axis 0 | Base rotation | q1 | +80° ... 0° ... -80° | 0...255 |
| Axis 1 | Shoulder | q2 | +70° ... 0° ... -30° | 0...255 |
| Axis 2 | Elbow | q3 | 0° ... -100° | 0...255 |
| Axis 3 | Wrist | q4 | +100° ... 0° ... -100° | 0...255 |
| Axis 4 | Wrist roll | q5 | +100° ... 0° ... -100° | 0...255 |
| Axis 5 | Gripper | — | 0 ... 60 mm | 0...255 |

Note:
- The firmware uses zero-based axis numbering.
- The original robot documentation uses one-based axis numbering.
- Each axis position is represented by an 8-bit value (0...255).

The reverse engineering process must identify how the firmware maps these logical axes to the physical motor control hardware.

Recover:

- Axis selection mechanism
- Motor enable signals
- Direction signals
- Position/step commands
- Servo control signals
- Feedback signals
- Limit switch inputs
- Gripper open/close control

Document:

- 8255 port assignments
- Bit-level signal mapping
- Axis command format
- Axis state transitions

Example:

| Axis | Hardware Signal | Description |
|------|-----------------|-------------|
| 0 | 8255 Port A bits | Base motor control |
| 1 | 8255 Port B bits | Shoulder motor control |
| 2 | 8255 Port C bits | Elbow motor control |
| 3 | TBD | Wrist axis 1 |
| 4 | TBD | Wrist axis 2 |
| 5 | TBD | Gripper control |

The firmware should model six independent axis controllers:

```c
#define AXIS_BASE       0
#define AXIS_SHOULDER   1
#define AXIS_ELBOW      2
#define AXIS_WRIST      3
#define AXIS_WRIST_ROLL 4
#define AXIS_GRIPPER    5
```

### Input/Output Handling

Identify:

- Digital inputs
- Digital outputs
- Sensors
- Switches
- Status signals
- Hardware control registers

---

---

## Hardware Reverse Engineering Workflow

The following hardware-related analysis steps must be completed before finalizing the C implementation.

### 8031 SFR Mapping

Identify all accesses to standard Intel 8031/MCS-51 Special Function Registers.

Use the SDCC header:

```c
#include <8051.h>
```

Document usage of:

- Accumulator (ACC)
- Program Status Word (PSW)
- Stack Pointer (SP)
- Timer registers
- Serial registers (SCON, SBUF)
- Interrupt registers (IE, IP)
- Port registers (P0 - P3)

Create a mapping document:

```
docs/8031_sfr_map.md
```

External Bus Access Analysis

Identify all external memory and I/O accesses.

Special attention should be given to:

- `movx @DPTR,A`
- `movx A,@DPTR`
- External address generation
- Data bus usage
- Chip select logic

Document discovered external devices:

```
docs/external_hardware_map.md
```

## Intel 8255 PPI Identification

The ROB3 controller uses an Intel 8255 Programmable Peripheral Interface for motor and I/O control.

Determine:

- 8255 base address
- Port A function
- Port B function
- Port C function
- Control register configuration
- Initialization sequence

Document:

```
docs/8255_mapping.md
```

## Firmware Conversion Strategy

The original assembly code should be converted into modular C components.

The conversion should:

- Preserve original execution logic.
- Keep state machines explicit.
- Maintain register and memory relationships.
- Avoid unnecessary optimization.
- Document unknown behavior.
- Separate hardware-specific code from application logic.

---

## Proposed C Architecture

```
rob3/
|
├── src/
│ |
│ ├── main.c # Main firmware execution loop
│ ├── robot.c # Robot control state machine
│ ├── axis.c # Axis movement handling
│ ├── protocol.c # Serial command processing
│ ├── serial.c # RS-232 communication
│ ├── io.c # Digital input/output handling
│ ├── timer.c # Timer functions
│ └── hardware.c # MCU-specific hardware access
|
├── include/
│ |
│ ├── robot.h
│ ├── axis.h
│ ├── protocol.h
│ ├── serial.h
│ └── hardware.h
|
└── docs/
|
├── memory_map.md
├── protocol.md
└── reverse_engineering_notes.md
```

## Assembly Translation Rules

When converting assembly code:

1. Preserve behavior before improving structure.
2. Do not remove unknown code paths.
3. Keep timing-sensitive operations unchanged.
4. Document assumptions.
5. Map registers and memory locations explicitly.
6. Identify possible hardware registers.
7. Separate recovered logic from guessed behavior.

Example:

Original assembly:

```asm
mov A, R7
anl A, #07H
mov command, A
```

Possible C translation:

```C
command = register_r7 & 0x07;
```

## Hardware Abstraction

### Hardware-specific operations should be isolated:

```C
void set_output(uint8_t value);
uint8_t read_input(void);

void uart_send(uint8_t data);
uint8_t uart_receive(void);

void timer_start(void);
```

This allows the recovered firmware logic to be separated from hardware-specific implementation details and simplifies future testing, simulation, or migration.

## SDCC Hardware Access

Hardware registers should use SDCC-compatible definitions:

```c
#include <8051.h>

__sfr __at(0x80) P0;
__sfr __at(0x90) P1;
```

## Documentation Requirements

During reverse engineering maintain:

### Memory Map

Document:

- RAM locations
- SFR usage
- Stack usage
- Global variables
- Buffers

## Function Mapping

Example:

| Address | Function         | Description              |
| ------- | ---------------- | ------------------------ |
| 0x0000  | `reset`          | Firmware startup         |
| 0x0030  | `serial_rx`      | Receive byte handler     |
| 0x0200  | `command_parser` | Robot command processing |


## Unknown Behavior

Any uncertain functionality should be marked:

Unknown Behavior

```C
// TODO: Hardware behavior not yet confirmed
// Original assembly accesses address 0x98
```

## SDCC and 8051 Hardware Definitions

The firmware must be developed using SDCC's 8051 target support.

All MCU-specific register definitions should use the SDCC-provided header:

```c
#include <8051.h>
```

The generated code should use the standard 8051 SFR definitions whenever possible instead of manually redefining registers.

Example:

```
#include <8051.h>

void serial_init(void)
{
    SCON = 0x50;     // Serial mode configuration
    TMOD |= 0x20;    // Timer 1 mode
}
```

## External Hardware Interfaces

The original ROB3 controller contains external peripherals connected to the Intel 8031 bus.

The firmware must identify and preserve all external hardware mappings.

### Intel 8255 Programmable Peripheral Interface (PPI)

The controller is believed to use an Intel 8255 PPI for motor and I/O control.

The reverse engineering process must identify:

- 8255 base address
- Port A usage
- Port B usage
- Port C usage
- Control register configuration
- Read/write access patterns

The generated C code should model the 8255 explicitly.

Example:

```c
#define IO8255_BASE 0x00

#define IO8255_PORT_A (*(volatile unsigned char *)(IO8255_BASE + 0))
#define IO8255_PORT_B (*(volatile unsigned char *)(IO8255_BASE + 1))
#define IO8255_PORT_C (*(volatile unsigned char *)(IO8255_BASE + 2))
#define IO8255_CONTROL (*(volatile unsigned char *)(IO8255_BASE + 3))
```

The exact addresses and meanings must be recovered from the original assembly code.

The 8255 interface should be isolated in:

```
include/ppi8255.h
src/ppi8255.c
```

Èxample API:

```
void ppi8255_init(void);

void ppi_write_port_a(uint8_t value);
void ppi_write_port_b(uint8_t value);
void ppi_write_port_c(uint8_t value);

uint8_t ppi_read_port_a(void);
uint8_t ppi_read_port_b(void);
uint8_t ppi_read_port_c(void);
```

Unknown hardware mappings must be documented rather than guessed.

## Kiro AI Development Instructions

- Treat the assembly firmware as the source of truth.
- Avoid redesigning the firmware architecture.
- Preserve original behavior.
- Ask for clarification when hardware behavior is unclear.
- Generate readable C code with comments.
- Maintain reverse engineering notes.
- Create incremental commits after each recovered subsystem.

## Success Criteria

The project is considered successful when:

- The complete 8031 firmware has been translated into C.
- The original robot control behavior is understood.
- Communication protocol is documented.
- Axis control logic is reconstructed.
- Hardware dependencies are identified.
- The resulting C code is maintainable and portable.


## Current Status

Initial phase:

- [ ] Import original 8031 disassembly
- [ ] Identify reset/startup code
- [ ] Map memory and registers
- [ ] Identify interrupts
- [ ] Recover communication protocol
- [ ] Convert functions incrementally
- [ ] Validate against original firmware behavior

## Build Environment

The reconstructed firmware must be compiled using **SDCC (Small Device C Compiler)** targeting the Intel 8051/MCS-51 architecture.

### Compiler Requirements

The Intel 8031 is a ROM-less member of the MCS-51 family. 
The generated code should remain compatible with the original memory and peripheral limitations.

- Compiler: `SDCC`
- Target architecture: Intel 8051 / MCS-51
- Original CPU: Intel 8031
- Language: Embedded C
- Memory model: Suitable for an 8-bit microcontroller with limited RAM/ROM

SDCC should be used to ensure compatibility with the original 8031 architecture.

### Build Rules

The build system should:

- Use `sdcc` as the default C compiler.
- Target the MCS-51 architecture.
- Avoid dynamic memory allocation.
- Avoid unsupported C extensions.
- Prefer static memory allocation.
- Keep code compatible with an 8 KB firmware size constraint.

Example build command:

```bash
sdcc \
    -mmcs51 \
    --model-small \
    -Iinclude \
    src/main.c \
    -o build/main.rel
```

## Project Build Structure


```
rob3/
|
├── Makefile
├── src/
├── include/
└── build/
```

Example Makefile:

```make
CC=sdcc

CFLAGS=\
	-mmcs51 \
	--model-small \
	-Iinclude

SRC=$(wildcard src/*.c)

TARGET=build/rob3

all:
	mkdir -p build
	$(CC) $(CFLAGS) $(SRC) -o $(TARGET).ihx

clean:
	rm -rf build
	rm -f *.asm *.lst *.rel *.map *.ihx
```

## Compiler Constraint

All generated C code must compile with `SDCC`.

Before introducing advanced C features, verify that they are supported by the compiler.

Prefer simple ANSI C style:
- explicit types
- static allocation
- no dynamic memory
- no unnecessary libraries

## Important: Target Platform

This is not a generic C port.

The target platform is an Intel 8031/MCS-51 microcontroller. 
All generated code must remain compatible with `SDCC` and the limitations of the original embedded hardware.

