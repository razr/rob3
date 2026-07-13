# Axis State Machine - ROB3 Firmware

## Overview

The ROB3 robot has 6 axes, each controlled by an independent state machine that runs within the External Interrupt 1 ISR. The ISR processes one axis per interrupt, cycling through all 6 in a round-robin pattern.

## Axis Numbering

| Index | Axis | Mechanical Function |
|-------|------|-------------------|
| 0 | Base | Base rotation (θ1) |
| 1 | Shoulder | Shoulder elevation (θ2) |
| 2 | Elbow | Elbow bend (θ3) |
| 3 | Wrist 1 | Wrist rotation (θ4) |
| 4 | Wrist 2 | Wrist pitch (θ5) |
| 5 | Gripper | Gripper open/close (θ6) |

## Data Structures Per Axis

Each axis N (0-5) uses the following RAM locations:

| Address | Variable | Description |
|---------|----------|-------------|
| 0x40+N | target | Target position (set by command/program) |
| 0x48+N | speed | Step rate / speed parameter |
| 0x50+N | current | Current position (host-visible) |
| 0x58+N | feedback | Raw feedback from hardware |
| 0x70+N | decel | Deceleration distance / profile |
| 0x78+N | state | ISR working state |

## Bit Masks (per axis)

The firmware uses rotating bit masks to identify individual axes:

| Axis | Mask Bit | Value |
|------|----------|-------|
| 0 | bit 0 | 0x01 |
| 1 | bit 1 | 0x02 |
| 2 | bit 2 | 0x04 |
| 3 | bit 3 | 0x08 |
| 4 | bit 4 | 0x10 |
| 5 | bit 5 | 0x20 |
| (all) | bits 0-5 | 0x3F |

### Axis Flag Registers

| Address | Register | Purpose |
|---------|----------|---------|
| 0x21 | axis_active | Bits set for axes requiring motion |
| 0x22 | axis_current | Rotating mask, indicates current axis in ISR |
| 0x2B | axis_need_move | Bits set for axes not yet at target |
| 0x2C | axis_moving | Bits set for axes currently stepping |
| 0x2D | axis_direction | Bits set for direction (1=positive, 0=negative) |

## State Machine (per axis, in ISR_EXT1)

```
┌──────────────────────────────────────────┐
│         ISR Entry (jump_00BF)            │
│  Save PSW, select bank 1                 │
│  Get current axis from R0 (0x48-0x4D)   │
│  Derive workspace pointer: R0 + 0x10    │
└────────────────────┬─────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────┐
│    Check if axis is active (22h.7)       │
│    OR check if timer update (22h.6)      │
├──────────YES───────┬─────────NO──────────┤
│                    │                      │
▼                    │                      ▼
┌──────────────┐     │     ┌──────────────────────┐
│ Read feedback│     │     │ Read motor command    │
│ from DPH=59 │     │     │ from lookup table     │
│ Store @R1    │     │     │ (DPH=0x58 indexed)   │
└──────┬───────┘     │     └──────────┬───────────┘
       │             │                │
       ▼             │                ▼
┌──────────────────┐ │  ┌─────────────────────────┐
│ Calculate error  │ │  │ Apply step table         │
│ target - current │ │  │ Compute phase output     │
│ Apply speed      │ │  │ Update motor shadow regs │
└──────┬───────────┘ │  │ (0x4E, 0x4F)            │
       │             │  └─────────────┬───────────┘
       ▼             │                │
┌──────────────────┐ │                │
│ Compute step     │ │                │
│ - Acceleration   │ │                │
│ - Deceleration   │ │                │
│ - Speed limit    │ │                │
└──────┬───────────┘ │                │
       │             │                │
       ▼             │                ▼
┌──────────────────────────────────────────┐
│         Update output registers          │
│  Write Port A shadow (0x4E) for axes 0-3│
│  Write Port C shadow (0x4F) for axes 4-5│
└────────────────────┬─────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────┐
│         Advance to next axis             │
│  Rotate 22h left                         │
│  R0 = next axis workspace               │
│  Write axis select to DPH=0x58          │
│  Restore PSW, RETI                       │
└──────────────────────────────────────────┘
```

## Axis Cycling (Round-Robin)

The register at 0x22 is a rotating mask that indicates the current axis:

```
Cycle: 0x01 → 0x02 → 0x04 → 0x08 → 0x10 → 0x20 → 0x01 → ...

mov A, 22h      ; Get current mask
rl A             ; Rotate left
mov 22h, A       ; Store back
mov A, R0        ; Get axis workspace pointer
inc A
anl A, #07h      ; Wrap around (0-7, but only 0-5 used)
mov 83h, #58h    ; Axis select device
movx @DPTR, A    ; Write axis number
orl A, #48h      ; Convert to RAM base (0x48-0x4D)
mov R0, A        ; Store for next interrupt
```

## Motion Control Flow

### Starting Motion
1. Host sends target positions → stored in 0x40-0x45
2. Host sends "go" command → sets 0x2B (need_move mask) and 0x2C (moving mask)
3. Main loop sets flag 25h.7 (motion active)
4. ISR begins processing axes

### During Motion
1. ISR reads feedback for current axis
2. Computes position error (target - feedback)
3. If error > deceleration threshold: accelerate/maintain speed
4. If error ≤ deceleration threshold: decelerate
5. If at target (error = 0): clear axis from 0x2B mask
6. When all bits in 0x2B are zero: motion complete

### Stopping Motion
- Normal stop: all axes reach target, 0x2B = 0x00
- Timeout stop: watchdog (0x19) expires → emergency halt
- Emergency: clear all outputs (Port A = 0, Port C = 0), disable motion flags

## Acceleration/Deceleration Profile

The ISR uses a lookup table accessed via `MOVC A, @A+PC` at approximately address 0x0145:

```
; Table maps error magnitude to step rate
; Small error → slow speed (deceleration)
; Large error → maximum speed (acceleration/cruise)
; Zero error → stop

; The table appears to be:
; Index 0: 0 (stopped)
; Index 1-3: low speeds (creep/decel)
; Index 4-8: medium speeds
; Index 9: maximum speed
; Bit 7 set: indicates direction flag
```

The profile involves:
1. Computing position error
2. Table lookup for speed based on error magnitude
3. Clamping to configured maximum speed (0x48+N)
4. Generating step pulses at the computed rate

## Motor Output Generation

### Phase Table
The motor drive signals appear to use a phase table (MOVC at ~0x01B9) that converts a step counter into motor phase patterns. This is consistent with stepper motor control where 2 or 4 bits represent the phase sequence (e.g., full-step, half-step).

```
; Output format per axis:
; 2 bits determine motor phase state
; Written to appropriate bits in Port A or Port C shadow
;
; Phase sequence (example, full-step):
; Step 0: 0b01
; Step 1: 0b11
; Step 2: 0b10
; Step 3: 0b00
; (repeats)
```

### Output Masking
Each axis occupies specific bits in the output port:
```asm
; Table at ~0x01C8 provides AND masks (clear bits)
; Table at ~0x01D0 provides OR masks (set bits)
; Together they update only the current axis's bits
; while preserving other axes' states

; AND mask clears the bits for current axis
; OR mask sets the new phase pattern for current axis
mov A, @R1         ; Get current phase for this axis
anl A, AND_TABLE   ; Clear old bits
mov @R1, A
mov A, R4
add A, R5
movc A, @A+PC      ; Look up new phase pattern
orl A, @R1         ; Set new bits
mov @R1, A
movx @DPTR, A      ; Write to hardware
```

## Axis Interaction with Motion Executor (jump_08FF)

The main loop calls jump_08FF to manage high-level motion:

```
motion_execute:
    if (motion_active flag 28h.4):
        write digital output
        check motion conditions:
            - all axes done? → clear motion flags
            - timeout? → stop
            - I/O condition met? → stop
    else if (program running):
        read next instruction
        execute instruction
        advance program counter
```

## Open Questions

1. **Step resolution:** How many steps per revolution for each axis motor?
2. **Gear ratios:** What mechanical reduction exists between motors and joints?
3. **Home sequence:** Is there a homing/calibration procedure? (Not found in firmware - may be host-driven)
4. **Limit switches:** How are limit switches read? Possibly via P1 (0x90) or through the axis feedback hardware.
5. **Gripper control:** Is axis 5 a continuous servo or a simple open/close solenoid?
