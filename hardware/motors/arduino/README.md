# ROB3 Motors — Arduino bring-up tests

Buildable Arduino sketches to characterise and drive a single ROB3 axis (DC
servo motor + 5 kΩ feedback potentiometer) from an Arduino UNO R3, plus a
Python host console. This is the runnable version of
[`../test.md`](../test.md).

Motor/feedback background: [`../README.md`](../README.md),
[`../bueler-motor.md`](../bueler-motor.md),
[`../VP12-5kΩ-potentiometer.md`](../VP12-5kΩ-potentiometer.md).

## Contents

```
arduino/
├── README.md                  # this file
├── pot_reader/
│   ├── pot_reader.ino         # read one axis pot; print raw + ROB3 8-bit scale
│   └── rob3_axis.h            # shared pin map + per-axis calibration
├── motor_control/
│   ├── motor_control.ino      # keyboard drive + ±80° watchdog + auto-center
│   └── rob3_axis.h            # (same header; Arduino builds per sketch folder)
└── host/
    └── monitor.py             # PC serial console (telemetry + interactive keys)
```

> `rob3_axis.h` is duplicated per sketch folder (Arduino compiles one folder at
> a time). Keep them in sync; `pot_reader/rob3_axis.h` is the source of truth.

## Wiring (single-axis rig)

| Signal            | Arduino UNO | Connects to |
| :---------------- | :---------: | :---------- |
| L293 IN1 (dir A)  | D2          | L293 pin 2 (IN1) |
| L293 IN2 (dir B)  | D3          | L293 pin 7 (IN2) |
| L293 EN           | 5V          | L293 pin 1 (EN1, tied high) |
| L293 VCC1 (logic) | 5V          | L293 pin 16 |
| L293 VCC2 (motor) | ext. +9V    | L293 pin 8  |
| Motor + / −       | —           | L293 OUT1/OUT2 → ROB3 connector pins 6 / 5 |
| Pot wiper (signal)| A0          | ROB3 connector pin 1 |
| Pot +5V / GND     | 5V / GND    | ROB3 connector pins 2 / 4 |
| GND (common)      | GND         | L293 pins 4/5/12/13, motor supply GND |

> **Safety:** the motor supply (+9V) must share GND with the Arduino. The
> `motor_control` sketch enforces soft ±80° travel limits from the pot feedback,
> but keep a hand near the power switch during first bring-up.

## Build, upload, run

Toolchain install and detailed steps are identical to the teachbox project —
see **[`../../teachbox/arduino/INSTALL.md`](../../teachbox/arduino/INSTALL.md)**
(arduino-cli / IDE, serial permissions, troubleshooting).

```bash
# from this directory
arduino-cli compile --fqbn arduino:avr:uno pot_reader
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 pot_reader
# or the motor driver:
arduino-cli compile --fqbn arduino:avr:uno motor_control
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 motor_control
```

Run / interact (9600 baud):

```bash
pip install pyserial
python3 host/monitor.py --port /dev/ttyACM0                 # watch telemetry
python3 host/monitor.py --port /dev/ttyACM0 --interactive   # drive: type F/B/0, Enter; q quits
```

- **pot_reader** prints `Raw ADC (0-1023) | ROB3 (0-255) | HEX` — move the joint
  by hand and confirm the values track (and match the calibration in
  `../test.md`).
- **motor_control** drives axis 1: `F`/`B` jog, `0` auto-centers, any other key
  is an emergency stop; it refuses to cross the ±80° soft limits.

## Calibration

`rob3_axis.h` carries the per-axis raw-ADC calibration points measured in
`../test.md` (`AXIS_CAL[0..5]` = ROB3 axes 1..6). `motor_control` uses axis 1's
values; adapt the constants at the top of `motor_control.ino` (or index
`AXIS_CAL`) to drive a different axis.
