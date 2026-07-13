# Intel 8255 PPI Mapping - ROB3 Controller

## Address Decoding

The 8255 is accessed via MOVX instructions where:
- DPH (0x83) acts as a chip/register select
- DPL (0x82) is not used for 8255 selection (kept at 0x00 or don't care)

| DPH Value | 8255 Register | R/W |
|-----------|---------------|-----|
| 0x50      | Port A        | R/W |
| 0x51      | Port B        | R/W |
| 0x52      | Port C        | R/W |
| 0x53      | Control       | W   |

**Note:** This is unusual for a standard 8255. Normally A0/A1 select registers. Here the address decoding appears to use DPH bits to generate independent chip selects or the address space is decoded with wider spacing. The 8031 external bus address lines (from P0/P2) likely have hardware decoding that maps these DPH values to the 8255's A0, A1, and CS pins.

## Control Register Configuration

### Initialization (at 0x0615)
```
Control = 0x80
```

Binary: `1_00_0_0_0_0_0`
- Bit 7 = 1: Mode set flag (active)
- Group A: Mode 0, Port A = Output
- Group B: Mode 0, Port B = Output
- Port C upper = Output
- Port C lower = Output

**All ports configured as outputs in Mode 0 (simple I/O).**

## Port A (DPH = 0x50) - Stepper Motor Output 1

### Function
- Drives stepper motor phase signals for one set of axes
- Updated by External Interrupt 0 ISR (motor pulse handler)
- Shadow register: Internal RAM address 0x4E

### Initialization
```
Port A = 0x00  (all motor outputs inactive)
```

### Access Pattern
```asm
mov 83h, #50h    ; Select Port A
mov A, 4Eh       ; Load shadow register
movx @DPTR, A    ; Write to hardware
```

### Bit Assignment (TENTATIVE - needs hardware verification)
| Bit | Function |
|-----|----------|
| 7-6 | Axis 0 phase signals (base rotation) |
| 5-4 | Axis 1 phase signals (shoulder) |
| 3-2 | Axis 2 phase signals (elbow) |
| 1-0 | Axis 3 phase signals (wrist 1) |

## Port B (DPH = 0x51) - Digital Output

### Function
- General purpose digital output port
- Used for:
  - LED/display control
  - Teach pendant interface
  - External I/O signals
- Shadow register: Internal RAM address 0x1F
- Managed by helper function at jump_07D0

### Initialization
```
Port B = 0xFF  (all outputs high / active-low inactive)
```

### Access Functions (jump_07D0)
The firmware provides four operations controlled by parameter in ACC bits 1-0:
| Value | Operation | Formula |
|-------|-----------|---------|
| 0x01  | OR (set bits) | output = output OR data |
| 0x02  | AND (clear bits) | output = output AND data |
| 0x03  | XOR (toggle bits) | output = output XOR data |
| 0x00  | WRITE (replace) | output = data |

### Bit Assignment (TENTATIVE)
| Bit | Function |
|-----|----------|
| 7-5 | Teach pendant display/LED signals |
| 4-3 | Status indicators |
| 2-0 | External digital outputs |

## Port C (DPH = 0x52) - Stepper Motor Output 2

### Function
- Drives stepper motor phase signals for second set of axes
- Updated by External Interrupt 0 ISR (motor pulse handler)
- Shadow register: Internal RAM address 0x4F

### Initialization
```
Port C = 0x00  (all motor outputs inactive)
```

### Access Pattern
```asm
mov 83h, #52h    ; Select Port C
mov A, 4Fh       ; Load shadow register
movx @DPTR, A    ; Write to hardware
```

### Bit Assignment (TENTATIVE)
| Bit | Function |
|-----|----------|
| 7-6 | Axis 4 phase signals (wrist 2) |
| 5-4 | Axis 5 phase signals (gripper) |
| 3-0 | Additional control signals (enable, direction?) |

## Additional External Devices

### Axis Select Register (DPH = 0x48)
- Write-only latch
- Selects which axis the feedback hardware reports on DPH=0x58/0x59
- Written with values 0-7

### Axis Feedback Input (DPH = 0x58)
- Read: returns data from currently selected axis
- Write: axis select (alternative to DPH=0x48?)
- Used in External Interrupt 1 ISR for position feedback

### Axis Feedback Input 2 (DPH = 0x59)
- Read: returns position/encoder data for selected axis
- Write: initialization value (0x01 written during startup)

## Hardware Interface Summary

```
┌──────────┐     ┌──────────┐     ┌─────────────┐
│  8031    │     │   8255   │     │   Motors    │
│          │     │          │     │             │
│ P0 (bus) ├────►│ Port A   ├────►│ Axes 0-3   │
│ P2 (addr)├────►│ Port B   ├────►│ Digital I/O │
│          │     │ Port C   ├────►│ Axes 4-5   │
│          │     │ Control  │     └─────────────┘
│          │     └──────────┘
│          │     ┌──────────┐     ┌─────────────┐
│          ├────►│Axis Sel  │     │  Encoders   │
│          │     │(DPH=48)  ├────►│  (6 axes)   │
│          │     └──────────┘     │             │
│          │◄────┤Feedback  │◄────┤             │
│          │     │(DPH=58/59)     └─────────────┘
│          │     └──────────┘
│          │     ┌──────────┐
│          ├────►│Ext RAM   │  Program storage
│          │◄────┤(DPH≥A0)  │
│          │     └──────────┘
└──────────┘
```

## Open Questions

1. **Address decoding logic:** How are DPH values 0x48-0x53 decoded to physical chip selects? Is there a GAL/PAL, 74138, or other decoder?

2. **Motor type:** Are these stepper motors (phase-driven) or DC servo motors (PWM + direction)? The ISR structure with phase tables suggests steppers.

3. **Feedback type:** What generates the External Interrupt 1 signal? Could be:
   - Encoder index pulse
   - External timer/counter overflow
   - Position comparison circuit

4. **Port B exact mapping:** Which bits drive teach pendant LED segments vs external outputs?

5. **8255 BSR mode:** The control byte 0x80 does not use Bit Set/Reset mode, but the firmware may use BSR commands elsewhere (control writes with bit 7 = 0).
