---
name: rob3-arduino-bringup
description: >
  ROB3-specific Arduino UNO bench rigs that recreate the Teachbox (74LS138
  5x5 key matrix + multiplexed LEDs on a DB25) and a single robot axis (L293
  DC-servo + 5k pot feedback): the exact DB25<->UNO pin maps, the four sketches
  (led_test / keypad_test / pot_reader / motor_control), the per-axis ADC
  calibration, and where they live. Use when building or running the ROB3
  hardware bring-up sketches or confirming a ROB3 hardware claim on the bench.
metadata:
  origin: ROB3
  globs: ["hardware/teachbox/arduino/**", "hardware/motors/arduino/**"]
---

# ROB3 Arduino Bring-up Rigs

> ROB3-specific counterpart to `arduino-hardware-bringup` (generic toolchain,
> serial permissions, pyserial monitor, active-LOW/L293 patterns, and the
> compile-vs-run verification convention — see there for anything not
> ROB3-specific). For the chips these rigs exercise see `rob3-hardware`; the
> narrative write-ups are `hardware/teachbox/test.md` and
> `hardware/motors/test.md`.

These sketches drive a ROB3 interface **directly from an UNO**, with the
original 8031 out of the loop, to confirm hardware claims used in the firmware
RE (the keypad column-read path, the ADC channels/scaling, the 6-motor L293
wiring). All decoder outputs and digital inputs are **active-LOW**; the UNO's
`INPUT_PULLUP` replaces the board's 10k/100k pull-up arrays.

## Teachbox rig — `hardware/teachbox/arduino/`

Recreates the DB25 Teachbox: a 74LS138-scanned 5×5 key matrix + multiplexed
indicator LEDs. Sketches: `led_test` (cycles the 8 decoder LEDs + NOP LED) and
`keypad_test` (scans the matrix + STOP line). Shared header `teachbox_pins.h`
(source of truth in `led_test/`, duplicated into `keypad_test/`).

### DB25 (female) ↔ UNO pin map (verified vs `board.md`/`led.md`)

| Signal              | DB25 pin | UNO pin | Direction |
| :------------------ | :------: | :-----: | :-------- |
| VCC (+5V)           | 13       | 5V      | power     |
| GND                 | 3        | GND     | ground    |
| A0 (addr bit 0)     | 23       | D2      | UNO → 138 |
| A1 (addr bit 1)     | 10       | D3      | UNO → 138 |
| A2 (addr bit 2)     | 22       | D4      | UNO → 138 |
| /E1,/E2 (strobe)    | 9        | D5      | UNO → 138 (drive LOW to enable) |
| NOP LED (direct)    | 11       | D6      | UNO → LED |
| Column group 1      | 5        | D7      | 138 → UNO |
| Column group 2      | 18       | D8      | 138 → UNO |
| Column group 3      | 17       | D9      | 138 → UNO |
| STOP button         | 4        | D12     | → UNO     |

- Sketches use `delayMicroseconds` settle gaps and disable the decoder while
  changing address lines to avoid ghosting.
- `led_test` prints each `[A2 A1 A0]` and the LED it lights; `keypad_test`
  prints the pressed key label, e.g. `-> key: [ RUN ] (/Y7, group 3)` and
  `-> key: [ STOP ] (direct line)`.
- Note the column groups (group 1/2/3) mirror the firmware's P1.5/6/7 read path
  — this rig is what confirmed the scan reads **P1 (0x90)**, not 8255 Port B.

## Motors rig — `hardware/motors/arduino/`

Characterises/drives **one** ROB3 axis: a Bühler DC-servo through an L293 with a
5 kΩ feedback pot. Sketches: `pot_reader` (raw ADC + ROB3 8-bit scale) and
`motor_control` (keyboard jog + ±80° soft limits + auto-center). Shared header
`rob3_axis.h` (source of truth in `pot_reader/`).

### Single-axis wiring

| Signal            | UNO | Connects to |
| :---------------- | :-: | :---------- |
| L293 IN1 (dir A)  | D2  | L293 pin 2 (IN1) |
| L293 IN2 (dir B)  | D3  | L293 pin 7 (IN2) |
| L293 EN           | 5V  | L293 pin 1 (EN1, tied high) |
| L293 VCC1 (logic) | 5V  | L293 pin 16 |
| L293 VCC2 (motor) | ext +9V | L293 pin 8 |
| Motor +/−         | —   | L293 OUT1/OUT2 → ROB3 connector pins 6 / 5 |
| Pot wiper         | A0  | ROB3 connector pin 1 |
| Pot +5V / GND     | 5V / GND | ROB3 connector pins 2 / 4 |
| GND (common)      | GND | L293 pins 4/5/12/13, motor-supply GND |

> **Safety:** motor supply (+9V) must share GND with the UNO. `motor_control`
> enforces ±80° soft travel limits from pot feedback and treats unknown keys as
> e-stop, but keep a hand near the power switch on first bring-up.

### Per-axis ADC calibration

`rob3_axis.h` carries the measured raw-ADC calibration points from
`hardware/motors/test.md` as `AXIS_CAL[0..5]` = ROB3 axes 1..6. `pot_reader`
prints `Raw ADC (0-1023) | ROB3 (0-255) | HEX`; `motor_control` uses axis 1's
values — index `AXIS_CAL` (or edit the constants atop `motor_control.ino`) to
drive a different axis. These 8-bit ROB3 scales tie back to the firmware axis
data (current pos `IRAM 0x50..0x55`, feedback `0x58..0x5D`) — see
`rob3-firmware-map`.

## Toolchain, ports, host monitor

Identical to the generic flow — `arduino-cli`/IDE, `dialout` permissions,
`host/monitor.py` at **9600 baud**, `compile` as a smoke test. Full steps live
in `hardware/teachbox/arduino/INSTALL.md` (the motors project references it).
See `arduino-hardware-bringup`.

## When to use this skill

- Building/running the ROB3 teachbox or motor bring-up sketches.
- Looking up the exact DB25↔UNO wiring or per-axis ADC calibration.
- Confirming a ROB3 hardware/firmware claim on the bench with the UNO.
