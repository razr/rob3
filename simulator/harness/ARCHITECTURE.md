# ROB3 simulation architecture: ucSim = bus chips, plant = external

This note fixes the boundary between what the ucSim simulation models and what
lives outside it, so the same firmware image can run against a Python plant, a
robotics simulator (ROS2 / Gazebo / Isaac), or the real bench hardware without
any change to the ROM or to ucSim.

## Principle

**ucSim models only what the 8031 can address on its bus.** Everything the CPU
cannot read or write directly — motors, gearing, joints, potentiometers, the
physical arm — is *plant*, and lives **outside** ucSim.

The ROB3 signal chain, annotated by who owns each stage:

```
8031 ──bus──▶ 8255 Port A/C ──▶ L293 ──▶ motor ──▶ joint ──▶ pot ──▶ ADC0808 ──bus──▶ 8031
   \________ addressable by CPU ________/    \_____ PLANT, not on the bus _____/  \_ addressable _/
        (ucSim: XRAM / cl_8255)                     (external harness)              (ucSim: cl_adc)
```

Only the **8255** and the **ADC0808** sit on the external bus. The L293, motor,
joint and pot are analog/mechanical: the firmware never touches them directly.
It writes *Port A/C bits* (the 8255) and reads *the ADC*. So:

- **In ucSim (`cl_hw` modules):** `cl_adc` (and, if desired, `cl_8255`; XRAM
  covers Port A/C today). These are bus devices — they respond to MOVX and, for
  the ADC, raise INT1.
- **Not in ucSim:** the axis/motor/pot physics. Modelling it as a `cl_hw` would
  be a category error (it is not a CPU-addressable peripheral). It is a *plant*
  the ADC samples.

## The firmware learns position ONLY from the pot

The 8031 has no encoder, step counter, or motor-feedback line. Its sole position
sensor is the **potentiometer read through the ADC**. The servo is therefore a
pure closed loop (servo ISR `0x00C0`):

```
set target (0x40+N) -> drive motor (Port A/C -> L293)
                    -> read pot via ADC (0x5900 -> 0x58+N)
                    -> compare feedback vs target (SUBB, 0x00EE)
                    -> repeat until feedback ~= target
```

There is no open-loop "move N steps." Consequence for any plant model:

> The pot value the ADC returns must move when (and only when) the motor is
> driven, in the commanded direction, and stop when the motor is off.

Get that right and the firmware converges exactly as it does against the real
arm.

## The bridge contract: 6 bytes out, 6 bytes in

The entire firmware<->world interface per servo cycle is:

| Direction | Signal | Where |
| :-------- | :----- | :---- |
| MCU -> world | `motor[6]` (direction/enable) | 8255 Port A `0x5000` + Port C `0x5200` |
| world -> MCU | `pot[6]` (axis feedback, 0..255) | served by `cl_adc` (one channel per conversion) |

Any plant plugs into these two ports. The 8031 cannot tell a Python model from
Gazebo from real silicon — it is reading a pot either way.

```
        +-------------- ucSim (real 8031 ROM) --------------+
        |  8255 Port A/C (motor cmd)      cl_adc (pot in)   |
        +------+----------------------------------^---------+
               | motor[6]                         | pot[6]
        +------v----------------------------------+---------+
        |                 BRIDGE (transport)                |
        |   pipe / -S UART socket / cl_hw over TCP          |
        +------+----------------------------------^---------+
               v                                  |
   +----------------+   +-----------------------+   +--------------+
   | Python plant   |   | ROS2 / Gazebo / Isaac |   | real bench HW |
   +----------------+   +-----------------------+   +--------------+
```

## Responsibilities

- **`cl_adc` (ucSim):** pure sensor + interrupt source. Serves the pot value it
  was last given for the selected channel; asserts EOC -> INT1. Holds **no**
  physics — only the current channel and a per-channel value cache written from
  outside.
- **Plant (external):** owns `true_pos[6]`. Each conversion: read `motor[6]`
  from Port A/C, decode `(direction, enable)` per axis, integrate `true_pos`,
  clamp to the joint's mechanical range, and hand the result back to `cl_adc` as
  the pot reading.
- **Bridge (transport):** moves `motor[6]` out and `pot[6]` in. For batch demos
  the Python harness driving `set hardware adc` suffices; for live
  co-simulation, a small `cl_hw` "bridge" peripheral carrying the two frames
  over a socket lets an external simulator be the plant with zero firmware
  changes.

## What must be exact vs. what can be approximate

- **Direction + enable — must be correct.** If the pot moves the wrong way for a
  given motor command, the servo diverges (drives to a rail). This is the L293
  bit map; it needs `[SIM]` verification, not a guess.
- **Speed (integration step) — may be approximate.** A faster/slower pot only
  changes how many conversions the axis takes to settle, not *whether* it
  converges. So a working closed-loop demo does **not** require the exact
  accel/decel curve — only the right direction sign. The exact motion law can be
  refined later when the servo algorithm is fully reverse-engineered.

## Unit mapping

ucSim traffics in raw 8-bit pot codes (0..255). Mapping code <-> joint angle
(q1 +80..-80 deg, q2 +70..-30, q3 0..-100, q4/q5 +/-100, gripper 0..60 mm — see
the README axis table) is the **plant's** job, keeping ucSim physics-agnostic.

## Verified structure of the motor-output stage (servo ISR)

From disassembly ([SIM]/[BYTE], exact bit values still [INFER]):

- `0x01A2 JBC ACC.2,0x01B4` — ACC.2 selects the Port C path vs the Port A path.
- Port A path `0x01A5`: `DPH=0x50` (window `0x5000`), `R1=0x4E` (Port A shadow).
- Port C path `0x01B4`: `DPH=0x52` (window `0x5200`), `R1=0x4F` (Port C shadow).
- `0x01B9..0x01C2`: two `MOVC` mask lookups build the byte — `ANL A,@R1`
  (clear field) then `ORL A,@R1` (set field) — then `MOVX @DPTR,A` writes the
  8255. `R4` carries the direction code (set by the compare at `0x00EE`).

The per-axis field bit positions and the direction encoding are the one piece
still to be pinned to `[SIM]` (the "direction trace"); until then the plant's
L293 decode is `[INFER]`.

### Direction-trace findings (2026-09, partial)

An attempt to extract the direction bit-map by driving the servo with a static
pot value established that this is **not** a simple probe — it is entangled with
the accel/decel state machine:

- The compare at `0x00EE` is `SUBB A,R4` where **`R4` is an accel/decel-
  transformed target**, not the raw target byte (observed `R4=0x38` for a raw
  target of `0xE0`), and `A`/`R5` is the feedback. So the servo does not compare
  feedback to the raw `0x40+N` target directly.
- With a **static** feedback value, the ISR consistently takes the compare
  branch at `0x0118`/`0x0129` and exits toward `0x0154` — it **never reaches**
  the motor-write `MOVX @DPTR` at `0x01C2`. The motor-output stage is reached
  only from a different servo sub-state that depends on accel/decel history
  accumulated across successive ISR invocations.

Conclusion: establishing the direction bit-map requires reproducing the
stateful accel/decel algorithm (per-axis workspace `0x78+`, bank-1 registers),
i.e. the same deep RE task the harness README flags. It is a deliberate
follow-up, not a quick trace. Until then the plant uses an `[INFER]` direction
map and the closed loop demonstrates *plumbing*, not certified servo direction.

## Status / next steps

1. `cl_adc`: pure pot conduit + EOC->INT1 (remove the coarse in-module
   integrator). — see `../ucsim-modules/adc/`.
2. Direction trace: establish which Port A/C bit pattern increases vs decreases
   the pot per axis ([SIM]).
3. Python plant + interactive ucSim driver: the reference "other side"; proves
   the loop closes.
4. Bridge transport (later): a `cl_hw` carrying `motor[6]`/`pot[6]` over a
   socket, so ROS2 / Gazebo / Isaac / real HW can be the plant unchanged.
