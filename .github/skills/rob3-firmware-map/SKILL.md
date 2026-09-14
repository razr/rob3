---
name: rob3-firmware-map
description: >
  ROB3 8031 firmware domain map: the interrupt/vector layout, the IRAM
  data-structure map (per-axis targets/speeds/positions/feedback/decel/state
  and the flag bytes), the external MOVX device windows, the five subsystems
  (axis servo, RS232 binary protocol, teach-pendant editor, program interpreter,
  motion executor), the axis/joint limits, and the [BYTE]/[SIM]/[HW]/[INFER]
  provenance convention. Use when annotating, extending, or reasoning about what
  the ROB3 firmware does (not how to build/simulate it).
metadata:
  origin: ROB3
  globs: ["firmware/**", "docs/**", "**/*.asm", "**/*.a51"]
---

# ROB3 Firmware Domain Map

> The *what-the-firmware-does* layer. For the instruction set see
> `mcs51-assembly`; for build/verify/simulate mechanics, the `@`-gotcha, and the
> teachbox sim module see `rob3-firmware-sim`; for the chips/memory-map decode
> see `rob3-hardware`. Authoritative live docs:
> `docs/reverse_engineering_notes.md`, `docs/axis_state_machine.md`,
> `docs/8031_sfr_map.md`, `docs/8255_mapping.md`, and the annotated listings
> `firmware/src/annotated/*.annotated.asm`. This skill is the fast index; the docs are the
> detail.

## Provenance convention (apply to EVERY firmware claim)

Tag every statement about the firmware with how it was established:

- **[BYTE]** — verified from the ROM bytes (byte-exact / golden match).
- **[SIM]** — verified by running the ROM in ucSim and observing state.
- **[HW]** — confirmed against a hardware doc or a bench bring-up.
- **[INFER]** — hypothesis, not yet proven. Never state as fact.

Keep unproven claims tagged and separate from verified ones. If you can't tag
it, you haven't verified it. (This convention is also in steering so it applies
by default.)

## Firmware at a glance

- 8 KB M2764A EPROM; real code `0x0000–0x0FDE`, rest is `0xFF` padding
  (disassembles as `MOV R7,A` — do not annotate it). [BYTE]
- Architecture: interrupt-driven cooperative multitasking; a polling main loop
  at **`0x074D`** services flags set by four ISRs. [BYTE]
- **Confirm entry addresses from ROM bytes, not disasm labels** (padding shifts
  boundaries: the old `jump_05FF`/`jump_02FF`/`lcall 0x22FE` were artifacts).

## Vectors & ISRs [BYTE]

| Vector | Addr    | Target   | Role |
| :----- | :------ | :------- | :--- |
| Reset  | `0x0000`| `0x0600` | `LJMP 0x0600` init (`02 06 00`) |
| INT0   | `0x0003`| `0x0040` | **EMERGENCY-OFF** handler (P3.2, active-LOW, level-trig; bank 1) |
| Timer0 | `0x000B`| `0x0080` | ~5.5 ms system tick (reload TL0=0x11/TH0=0xE8) |
| INT1   | `0x0013`| `0x00C0` | **Axis servo** state machine (ADC EOC → pin 13; bank 1) |
| Timer1 | `0x001B`| — (gap)  | ET1 never enabled; Timer1 is baud-gen only |
| Serial | `0x0023`| `0x0300` | 0xFF slot falls through to `LJMP 0x0300` at `0x0035` (UART RX/TX) |

## IRAM data-structure map (128 B, `0x00–0x7F`)

Register banks: 0 = main (`0x00`), 1 = ISRs INT0/INT1 (`0x08`), 2 = serial ISR
(`0x10`). Per-axis arrays are indexed `N = 0..5`:

| Base    | Meaning | | Byte | Meaning |
| :------ | :------ |-| :--- | :------ |
| `0x40+N`| axis **target** position | | `0x1F` | digital-out latch shadow (Port B) |
| `0x48+N`| axis **speed**/step rate | | `0x46` | teach-pendant strobe pattern |
| `0x50+N`| axis **current** pos (host view) | | `0x47` | LED/row **display** output latch |
| `0x58+N`| axis **feedback** (ADC) | | `0x4E` | Port A motor shadow (axes 0-3) |
| `0x70+N`| **decel** profile | | `0x4F` | Port C motor shadow (axes 4-5) |
| `0x78+N`| ISR **workspace** | | `0x56–57` | keypad debounce state |
| `0x60–65`| serial RX buffer (6 axis bytes) | | `0x66–67` | program counter (ext-RAM offset) |
| `0x68–6E`| serial command buffer | | `0x3E/0x3F` | ext-RAM program page hi / +1 |

### Bit-flag bytes (`0x20–0x2F`, bit-addressable) [BYTE]/[INFER mixed]

| Byte | Role |
| :--- | :--- |
| `0x20`| system flags: .0 axis-enable, .1 kbd-event, .2 baud-detected, .3/.4 timer toggles |
| `0x21`| axis-active mask (one bit per axis, `0x3F` = all) |
| `0x22`| **current-axis rotating mask** used by the INT1 servo ISR (`0x01→0x02→…→0x20→…`) |
| `0x2B`| axis "need-move" mask (cleared per axis as it reaches target) |
| `0x2C`| axis "moving" mask |
| `0x2D`| axis direction mask (1=positive) |
| `0x28`| system state: .1 program-loaded, .2 running, .3 motion-active, .4 conditional [INFER] |
| `0x29`| editor mode / sub-state (key handler) |

> Byte-vs-bit reminder: e.g. the init gate `JB 0x22.0` tests **bit 0 of the
> one-hot axis mask byte 0x22**, not RAM byte 0x22 as a whole.

## External MOVX device windows (DPH selects) [HW]

| DPH | Device |
| :-- | :----- |
| `0x48` | aux / axis-select latch (74LS138 Y2/Y3 region) |
| `0x50/0x51/0x52/0x53` | 8255 Port A / Port B / Port C / Control |
| `0x58` | ADC channel-select/START (A8 = ADD-A channel) |
| `0x59` | ADC converted-data read |
| `≥0xA0` (A15) | external SRAM (program storage) |

Details and the decode logic are in `rob3-hardware`. Feedback is **analog via
ADC0808/0809**, EOC → INT1 — *not* a quadrature encoder. [HW]

## The five subsystems

1. **Axis servo controller** (INT1 ISR `0x00C0`) — round-robin over 6 axes via
   the `0x22` mask; per axis: read ADC feedback (`DPH=0x59`), compare to target,
   apply an accel/decel profile (MOVC table ~`0x0145`), write the motor shadow
   (`0x4E`/`0x4F`) out to 8255 Port A/C, then advance the mask/channel and
   `RETI`. **Stateful across invocations** (per-axis workspace `0x78+` + bank-1
   regs) — see `rob3-firmware-sim` for why a single-pass sim of it is not
   faithful. [BYTE]/[SIM]
2. **RS232 binary protocol** (UART ISR `0x0300`, TX helper `0x0541`) — Mode-1
   8-bit UART, `SCON=0x50`; baud auto-detect or fixed via P3.0. Host command
   bytes have bit7=1; bit6 = axis/position vs system/program class; low bits =
   axis 0-5 or `0x07`=all. `0x81` = data-block marker; `0x89–0x8F` = program
   download; responses framed with `0x03` (ETX). Command decode is partly
   [INFER].
3. **Teach-pendant editor** (scanner `0x0C00`, handler `0x0C80`) — scans the 5×5
   matrix (strobe via 8255, read columns on **P1/0x90**), debounces, returns a
   key index; the handler does axis jog, program edit, run/stop, position teach,
   and display update via `0x47`. [BYTE]/[SIM] Verified specifics:
   key **index = row+1 + (group−1)×8**; **axis-select = index 0x02..0x07**
   (group 1, rows 1..6) → axis 0..5, each setting mode `0x29=0x40` (POSITION).
   Debounce **accept = release-then-hold**: the accept path (`0x0C41`) is gated
   by `JNB 0x20.6`, and `0x20.6` is set only by the release path — so a key
   dispatches only after a prior release then a held press. In ucSim the ROM
   only reaches the poll (`tb_poll` `0x07C4`) with the P3.2/P3.4 gates satisfied
   (loopback module) — see `rob3-firmware-sim`. POS-digit value entry
   (`pos_digit` 0x0D65 / `pos_commit` 0x0D9F) is `[BYTE]` but not yet mapped as a
   black-box key sequence.
4. **Program interpreter** (`0x0941`) — executes stored motion programs from
   external SRAM: 8-byte instructions (opcode, 6 axis targets, speed/flags),
   PC in `0x66:0x67`, end marker `0x83`. Instruction set only partly decoded
   [INFER].
5. **Motion executor** (`0x08FF`, called from the main loop) — high-level:
   detects all-axes-done / timeout / I/O conditions, drives program stepping.

## Axis / joint reference [HW]

| Idx | Joint | Range | | Idx | Joint | Range |
| :-- | :---- | :---- |-| :-- | :---- | :---- |
| 0 | Base rot. (q1) | +80°..−80° | | 3 | Wrist pitch (q4) | +100°..−100° |
| 1 | Shoulder (q2) | +70°..−30° | | 4 | Wrist roll (q5) | +100°..−100° |
| 2 | Elbow (q3) | 0°..−100° | | 5 | Gripper | 0–60 mm |

All positions 8-bit (0–255); firmware is zero-based, robot docs are one-based.

## Named entry points (proposed labels) [BYTE addresses]

`0x0600` sys_init · `0x0040` emergency_off (INT0, P3.2) · `0x0080` isr_timer0 (tick)
· `0x00C0` isr_ext1 (axis servo) · `0x0300` isr_serial · `0x0541` serial_tx ·
`0x074D` main_loop · `0x07D0` write_digital_out · `0x0802` program_load ·
`0x08FF` motion_execute · `0x0941` program_step · `0x0C00` keyboard_scan ·
`0x0C80` keyboard_handler.

## Known-tentative items (do NOT assert) [INFER]

- **Port A/C exact bit → axis mapping** for the 6 motors.
- Any **"stepper phase table"** language in the older docs: the Port A/C bits are
  DC-motor **direction/enable** into the L293s, not stepper phases; the
  phase-table description in `axis_state_machine.md` is a tentative hypothesis
  pending decode.
- Exact servo gains / accel-decel table contents (`~0x0145`, `~0x01B9`).
- `DPH=0x48` latch's exact function (region known, role open).

## When to use this skill

- Annotating or extending any ROB3 firmware region (know the subsystem, the
  data structures it touches, and the correct provenance tag).
- Looking up an IRAM address, a flag bit, a vector target, or a device window.
- Reasoning about the servo/protocol/interpreter behavior before writing tests
  (pair with `rob3-firmware-sim`).
