---
name: arduino-hardware-bringup
description: >
  Bench bring-up of hardware with an Arduino UNO (AVR): buildable diagnostic
  sketches, the arduino-cli / Arduino IDE toolchain, serial-port permissions,
  a pyserial host monitor, and the compile-only smoke-test convention. Covers
  active-LOW matrix/decoder scanning (74LS138), INPUT_PULLUP for inputs, and
  L293 H-bridge motor + potentiometer feedback rigs. Use when validating a
  peripheral or interface on real hardware independently of its target MCU.
metadata:
  globs: ["**/arduino/**", "**/*.ino", "**/*.ino.h", "**/monitor.py"]
---

# Arduino Hardware Bring-up (UNO / AVR)

> Generic reference for standing up small Arduino diagnostic rigs to validate
> real hardware (key matrices, LED decoders, motors, sensors) on the bench,
> before or instead of trusting the target MCU's firmware. Project-specific
> wiring maps, pin headers, and calibration constants belong in a project skill.

## Why an Arduino bring-up

When reverse-engineering or repairing a board, a small UNO sketch that drives
one interface directly is the fastest way to **confirm a hardware claim** (a
decoder's address map, a matrix's active level, an ADC channel, a motor's
direction) without the original CPU/firmware in the loop. Treat each sketch as
a single, focused experiment with human-readable serial output.

## Project layout that works with the Arduino build system

The Arduino toolchain compiles **one sketch folder at a time**, and a sketch's
`.ino` plus its helper headers must live in that folder. A clean layout:

```
arduino/
├── README.md                 # wiring + quick reference
├── INSTALL.md                # toolchain/port/permissions (can be shared)
├── <test_a>/
│   ├── <test_a>.ino
│   └── pins.h                # shared pin map (source of truth)
├── <test_b>/
│   ├── <test_b>.ino
│   └── pins.h                # DUPLICATE of the above — keep in sync
└── host/
    └── monitor.py            # PC-side serial reader (pyserial)
```

> **Shared header gotcha.** Because Arduino builds per folder, a common header
> (`pins.h`, calibration) must be **copied into each sketch folder**. Pick one
> copy as the source of truth and note it in the README, or symlink if your OS
> and the IDE tolerate it.

## Toolchain — two paths (need only one)

### arduino-cli (recommended, reproducible)

```bash
# install (Linux/macOS)
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
# one-time core
arduino-cli config init
arduino-cli core update-index
arduino-cli core install arduino:avr        # AVR core = UNO / Nano / Mega

arduino-cli board list                      # find Port + FQBN (arduino:avr:uno)
arduino-cli compile --fqbn arduino:avr:uno <sketch>
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 <sketch>
arduino-cli monitor -p /dev/ttyACM0 -c baudrate=9600
```

> **`compile` alone is a smoke test** — it verifies the sketch builds even with
> no board attached. Useful in CI/dev containers.

### Arduino IDE (graphical)

Open `<sketch>/<sketch>.ino`, **Tools → Board → Arduino UNO**, select **Port**,
click **Upload**; read output in **Tools → Serial Monitor**.

## Serial-port permissions & port names

| OS | Port name | Access note |
| :- | :-------- | :---------- |
| Linux | `/dev/ttyACM0` (UNO), `/dev/ttyUSB0` (CH340/FTDI clones) | user must be in **`dialout`**: `sudo usermod -aG dialout "$USER"`, then re-login |
| macOS | `/dev/cu.usbmodemXXXX` (or `cu.usbserial-XXXX`) | no group change |
| Windows | `COMx` | install CH340 driver for some clones |

## Host serial monitor (pyserial)

A ~30-line `monitor.py` (print + optional log + optional interactive keys) is
usually enough:

```bash
python3 -m pip install pyserial
python3 host/monitor.py --port /dev/ttyACM0                 # print
python3 host/monitor.py --port /dev/ttyACM0 --log run.log   # print + log
python3 host/monitor.py --port /dev/ttyACM0 --interactive   # send keystrokes
```

Match the sketch's baud (commonly **9600**) on both ends.

## Common bring-up patterns

### Active-LOW decoder / matrix scan (e.g. 74LS138)

Decoder outputs and many digital inputs are **active-LOW**. Drive the address
lines, **disable the decoder while changing them** (assert the strobe inactive),
settle, then enable — this avoids ghosting/glitches during transitions.

```c
// pseudo: select one of 8 lines, active-LOW enable
digitalWrite(EN, HIGH);          // disable during address change
setAddress(a);                   // A2..A0
delayMicroseconds(5);            // settle
digitalWrite(EN, LOW);           // enable (active-LOW)
```

Use the UNO's internal **`INPUT_PULLUP`** on column/return lines to replace the
original board's pull-up arrays — no external resistors needed. A pressed key /
active output then reads LOW.

### L293 H-bridge motor + pot feedback rig

- IN1/IN2 = direction, EN tied to +5V (or a PWM pin for speed); **VCC1 = logic
  5V, VCC2 = motor supply**; the motor supply **must share GND** with the UNO.
- Read the feedback pot on an analog pin (`analogRead` → 0..1023); scale to the
  target's units for comparison.
- **Enforce soft travel limits** from the feedback in the sketch (refuse to
  drive past a min/max), and keep an e-stop key. Keep a hand near the power
  switch on first power-up.

## Verification convention (bench, not silicon claims)

- **Syntax/compile check without hardware:** `arduino-cli compile` (or, in a
  container with no AVR core, a host `g++ -fsyntax-only` against minimal Arduino
  stubs) proves the sketch is well-formed. Say so — a compile check is **not** a
  run on hardware.
- **Behavioral check on hardware:** actually upload and read the serial output;
  only then is a hardware claim confirmed.
- `py_compile` the host scripts to catch Python errors.
- Label each result with how it was verified (compiled vs run-on-hardware), the
  same discipline used for firmware provenance.

## Troubleshooting (quick table)

| Symptom | Fix |
| :------ | :-- |
| `Permission denied` on port (Linux) | add to `dialout`, re-login |
| Board not listed | different cable/port; install CH340/FTDI driver; `arduino-cli board list` |
| `avrdude: stk500_recv` on upload | wrong port or port busy — close Serial Monitor, reselect, retry |
| Only one sketch compiles | compile each folder separately (per-folder build) |
| Garbage in monitor | set baud to the sketch's rate (often 9600) |
| Nothing lights / no response | recheck wiring; remember active-LOW enables/strobes must be driven LOW |

## When to use this skill

- Writing/building UNO diagnostic sketches to validate a peripheral on the bench.
- Setting up arduino-cli / IDE, port permissions, or a pyserial host monitor.
- Scanning an active-LOW decoder/matrix or driving an L293 + pot rig.
- Confirming a reverse-engineering hardware claim independently of target firmware.
