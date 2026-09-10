# ROB3 Teachbox — Arduino bring-up tests

Real, buildable Arduino sketches that recreate and exercise the ROB3 Teachbox
interface (a 74LS138-scanned 5x5 key matrix + multiplexed indicator LEDs on a
DB25 connector) using an Arduino UNO R3, plus a Python serial monitor for the
host PC.

This is the runnable version of the project written up in
[`../test.md`](../test.md). Wiring is documented in [`../board.md`](../board.md)
and [`../led.md`](../led.md).

> **New here?** For step-by-step toolchain install, board/port setup, serial
> permissions, and running the sketches, see **[`INSTALL.md`](INSTALL.md)**.
> The sections below are a quick reference.

## Contents

```
arduino/
├── README.md                  # this file (quick reference)
├── INSTALL.md                 # full install + run guide
├── led_test/
│   ├── led_test.ino           # cycles the 8 decoder LEDs + NOP LED
│   └── teachbox_pins.h        # shared DB25<->UNO pin map
├── keypad_test/
│   ├── keypad_test.ino        # scans the 5x5 key matrix + STOP line
│   └── teachbox_pins.h        # (same header; Arduino needs it per-sketch)
└── host/
    └── monitor.py             # PC-side serial monitor (pyserial)
```

> `teachbox_pins.h` is duplicated in each sketch folder because the Arduino
> build system compiles one sketch folder at a time. Keep the two copies in
> sync; `led_test/teachbox_pins.h` is the source of truth.

## Wiring (DB25 female ↔ Arduino UNO)

Verified against `board.md` / `led.md`. All decoder outputs and digital inputs
are **active-LOW**.

| Signal              | DB25 pin | UNO pin | Direction |
| :------------------ | :------: | :-----: | :-------- |
| VCC (+5V)           | 13       | 5V      | power     |
| GND                 | 3        | GND     | ground    |
| A0 (addr bit 0)     | 23       | D2      | UNO → 138 |
| A1 (addr bit 1)     | 10       | D3      | UNO → 138 |
| A2 (addr bit 2)     | 22       | D4      | UNO → 138 |
| /E1,/E2 (strobe)    | 9        | D5      | UNO → 138 |
| NOP LED (direct)    | 11       | D6      | UNO → LED |
| Column group 1      | 5        | D7      | 138 → UNO |
| Column group 2      | 18       | D8      | 138 → UNO |
| Column group 3      | 17       | D9      | 138 → UNO |
| STOP button         | 4        | D12     | → UNO     |

The UNO's internal `INPUT_PULLUP` resistors stand in for the original board's
10kΩ/100kΩ pull-up arrays, so no external resistors are needed for the inputs.

## Build & upload

### Option A — arduino-cli

```bash
# one-time setup
arduino-cli core update-index
arduino-cli core install arduino:avr

# find your board's port
arduino-cli board list

# compile
arduino-cli compile --fqbn arduino:avr:uno led_test
arduino-cli compile --fqbn arduino:avr:uno keypad_test

# upload (replace the port)
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 led_test
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 keypad_test
```

### Option B — Arduino IDE

Open `led_test/led_test.ino` (or `keypad_test/keypad_test.ino`), select
**Tools → Board → Arduino UNO** and the correct **Port**, then **Upload**.

## Run

Open the Serial Monitor at **9600 baud** (Arduino IDE), or use the host script:

```bash
pip install pyserial
python3 host/monitor.py --port /dev/ttyACM0            # print
python3 host/monitor.py --port /dev/ttyACM0 --log run.log   # print + log
```

- **led_test** prints each address `[A2 A1 A0]` and the LED it activates, then
  pulses the NOP LED. Watch the Teachbox LEDs light in sequence.
- **keypad_test** prints the label of any key you press (and `STOP` on the
  direct line). Press keys on the Teachbox and confirm the reported labels.

## Notes

- Sketches use `delayMicroseconds` settle gaps and disable the decoder while
  changing the address lines to avoid ghosting/glitches during transitions.
- Only 3 digital outputs (DO1-3) and 5 digital inputs (DI1-5) are available at
  the Teachbox I/O port when connected to the ROB3i (per `../README.md`); these
  bring-up sketches drive the interface directly from the UNO instead.
