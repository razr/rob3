# INSTALL — Arduino toolchain for the ROB3 Teachbox tests

How to install the Arduino toolchain, build/upload the bring-up sketches in this
folder, and read their output. For the wiring and what each sketch does, see
[`README.md`](README.md).

There are two supported paths: **arduino-cli** (command line, recommended for
reproducibility) and the **Arduino IDE** (graphical). You only need one.

---

## 1. Prerequisites

- An **Arduino UNO R3** (or compatible, e.g. ELEGOO UNO R3) and a USB Type-B cable.
- The Teachbox wired to the UNO per [`README.md`](README.md).
- A host PC (Linux / macOS / Windows).
- For the host serial monitor: **Python 3** and **pyserial**.

---

## 2A. Install arduino-cli (recommended)

### Linux / macOS

```bash
# Install into ~/bin (or /usr/local/bin if you prefer, with sudo)
curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | sh
# The script drops the binary in ./bin by default; move it onto your PATH:
sudo mv bin/arduino-cli /usr/local/bin/    # optional
arduino-cli version
```

Alternatively on macOS with Homebrew:

```bash
brew install arduino-cli
```

### Windows

- Download the Windows zip from <https://arduino.github.io/arduino-cli/latest/installation/>
  and add `arduino-cli.exe` to your `PATH`, **or** `winget install ArduinoSA.CLI`.

### One-time core install (all platforms)

```bash
arduino-cli config init
arduino-cli core update-index
arduino-cli core install arduino:avr      # AVR core = UNO / Nano / Mega
```

---

## 2B. Install the Arduino IDE (alternative)

- Download from <https://www.arduino.cc/en/software> (2.x recommended).
- Linux (Ubuntu): the IDE ships as an AppImage — `chmod +x` it and run, or use
  the Flatpak/Snap if you prefer.
- On first launch, the IDE installs the AVR core automatically.

---

## 3. Serial-port permissions

### Linux (Ubuntu 24.04)

The UNO enumerates as `/dev/ttyACM0` (or `/dev/ttyUSB0` for clones with a
CH340/FTDI chip). Your user must be in the **`dialout`** group to access it:

```bash
sudo usermod -aG dialout "$USER"
# log out and back in (or reboot) for the group change to take effect
groups | tr ' ' '\n' | grep dialout    # verify
```

If you skip this you will get `Permission denied` on the port.

### macOS

No group changes needed. The port appears as `/dev/cu.usbmodemXXXX`
(or `/dev/cu.usbserial-XXXX` for clones).

### Windows

Windows assigns a `COMx` port. If an UNO clone with a CH340 chip is not
recognized, install the CH340 driver from the vendor.

---

## 4. Find your board and port

### arduino-cli

```bash
arduino-cli board list
```

Look for the entry whose Board Name is "Arduino Uno"; note its Port
(e.g. `/dev/ttyACM0`, `/dev/cu.usbmodem1101`, or `COM3`) and FQBN
(`arduino:avr:uno`).

### IDE

**Tools → Board → Arduino AVR Boards → Arduino UNO**, then **Tools → Port**.

---

## 5. Build & upload

Run these from **this `arduino/` directory**. Replace the port with yours.

### arduino-cli

```bash
# LED test
arduino-cli compile --fqbn arduino:avr:uno led_test
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 led_test

# Keypad test
arduino-cli compile --fqbn arduino:avr:uno keypad_test
arduino-cli upload  --fqbn arduino:avr:uno -p /dev/ttyACM0 keypad_test
```

`compile` alone is a good smoke test even without a board attached.

### IDE

Open `led_test/led_test.ino` (or `keypad_test/keypad_test.ino`), pick the board
and port, and click **Upload** (the right-arrow button).

---

## 6. Run / read the output

Both sketches print at **9600 baud**.

### Option A — the host script (this repo)

```bash
python3 -m pip install pyserial
python3 host/monitor.py --port /dev/ttyACM0                 # print
python3 host/monitor.py --port /dev/ttyACM0 --log run.log   # print + append to file
```

### Option B — arduino-cli monitor

```bash
arduino-cli monitor -p /dev/ttyACM0 -c baudrate=9600
```

### Option C — IDE Serial Monitor

**Tools → Serial Monitor**, set the baud dropdown to **9600**.

Expected output:

- **led_test** — a repeating sweep, e.g.
  `Address [A2 A1 A0]: 0 0 0 -> ERROR LED` … through `RUN LED`, then `NOP LED`.
  The corresponding Teachbox LEDs light in sequence.
- **keypad_test** — prints the label of any key you press, e.g.
  `-> key: [ RUN ] (/Y7, group 3)`, and `-> key: [ STOP ] (direct line)` for STOP.

---

## 7. Troubleshooting

| Symptom | Fix |
| :------ | :-- |
| `Permission denied` on the port (Linux) | Add yourself to `dialout` and re-login (step 3). |
| Port not listed / no board found | Try another USB cable/port; for clones install the CH340/FTDI driver; check `arduino-cli board list`. |
| Upload fails with `avrdude: stk500_recv` | Wrong port or board busy — close any open Serial Monitor, re-select the port, retry. |
| Only one sketch compiles | Compile each folder separately; Arduino builds one sketch folder at a time. |
| Garbage in the serial monitor | Set the baud to **9600** (both sketches use it). |
| `pyserial` import error | `python3 -m pip install pyserial`. |
| Nothing lights up | Recheck DB25↔UNO wiring in [`README.md`](README.md); remember decoder outputs are **active-LOW** and the strobe (pin 9 / D5) must be driven LOW to enable. |

---

## 8. Uninstall / cleanup

- arduino-cli: remove the binary and `~/.arduino15` (its config/cores).
- IDE: delete the app; sketches in this repo are untouched.
