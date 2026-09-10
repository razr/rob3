# LED

**The LEDs are controlled using a combination of signals** on the DB25 pins connected to `A0`, `A1`, and `A2`. These pins act as a binary "address" that determines which specific LED lights up, while pin 9 acts as a master switch to enable or disable all LEDs at once.

The chip on your diagram is the 74LS138 (a 3-to-8 line decoder). It takes a binary code from the computer and connects exactly one of its eight outputs to Ground (0V).

## 🛠 How the Control Logic Works

The outputs of the chip (labeled `/Y0` through `/Y7`) are active-low (indicated by the slash `/`). This means an output pin must drop to **0 Volts (Low)** to turn an LED on.

## 🔌 Electrical Path

Each LED is wired in series with a 210 Ohm resistor. The electrical current flows like this:
- $V_{CC}$ (+5V) ➡️ 210 Ohm Resistor ➡️ LED Anode (+) ➡️ LED Cathode (-) ➡️ Decoder Output (`/Yx`).
- When the 74LS138 activates an output, it completes the circuit to `GND` (pin 8 of the chip), allowing current to flow and lighting up the LED.

### 1. The Master Switch (Enable Pins)

For the chip to respond to any commands, its enable pins (`/E1`, `/E2`, `E3`) must be properly activated:
- `E3` is permanently tied to $V_{CC}$ (+5V) (always enabled).
- `/E1` and `/E2` are tied together and connected to pin 9 of the `DB25`.
- **The Rule:** To turn any LED `on`, the computer must send a `Low` signal (0V) to `pin 9`. If pin 9 is `High` (+5V), all LEDs will instantly turn off.

## 2. Selecting the LED (Addressing)

When pin 9 is Low, you can choose which LED lights up by changing the signals on pin 22, pin 10, and pin 23 of the DB25 connector:

| DB25 pin 22 (A2) | DB25 pin 10 (A1) | DB25 pin 23 (A0) | Active Output | LED that turns ON |
| :---: | :---: | :---: | :---: | :--- |
| 0 | 0 | 0 | `/Y0` (pin 15) | 🔴 ERROR LED |
| 0 | 0 | 1 | `/Y1` (pin 14) | 🟡 OUT LED |
| 0 | 1 | 0 | `/Y2` (pin 13) | 🟡 POS LED |
| 0 | 1 | 1 | `/Y3` (pin 12) | 🟡 TIM LED |
| 1 | 0 | 0 | `/Y4` (pin 11) | 🟡 MARK LED |
| 1 | 0 | 1 | `/Y5` (pin 10) | 🟡 GOTO LED |
| 1 | 1 | 0 | `/Y6` (pin 9)  | 🟡 IF LED |
| 1 | 1 | 1 | `/Y7` (pin 7)  | 🟡 RUN LED |

Note: NOP LED	is connected directly to pin 11

## 210 Ohm resistor

The 210 Ohm resistor is needed for two critical reasons: it limits the electrical current to protect the LED from burning out, and it prevents the 74LS138 chip from overheating.
Without this resistor, the components would draw too much current and permanently fail within seconds.

### 📉 1. Protecting the LED (Current Limiting)

LEDs have a very low internal resistance once they start conducting light. If you connect an LED directly to a 5-Volt power supply:
- The LED will attempt to draw as much current as the power supply can give.
- This excessive current creates intense heat inside the tiny LED semiconductor crystal.
- The crystal melts instantly, destroying the LED.

The resistor acts as a "dam" in the electrical river, restricting the flow of current to a safe level.

### 🧮 2. The Math Behind the 210 Ohm Value

We can calculate exactly why 210 Ohms is used by using Ohm's Law ($I = \frac{V}{R}$):
- Supply Voltage ($V_{CC}$): 5.0 Volts (standard for the 74LS series).
- LED Forward Voltage ($V_{F}$): A typical standard red LED drops about 2.0 Volts across itself to turn on.
- Remaining Voltage: The resistor must absorb the rest of the voltage:\($5.0\text{V} - 2.0\text{V} = 3.0\text{V}$)
- Target Current (I): Standard indicator LEDs shine brightly at around 14 to 15 milliamperes (0.014 A – 0.015 A).

Now, we calculate the required resistance ($R = \frac{V}{I} \implies R = \frac{3.0\text{V}}{0.0143\text{A}} \approx 210\,\Omega$)

### ⚡ 3. Protecting the 74LS138 Chip

The 74LS138 Integrated Circuit has maximum limits on how much current its output pins can handle.
- According to official datasheets, a standard 74LS138 pin can safely sink a maximum of 8 to 16 mA (milliamperes) of current.
- The 210 Ohm resistor guarantees that the current stays right around 14 mA, which keeps the chip operating safely within its limits without overheating the output transistors.

