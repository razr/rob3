# Motor Test

> **Runnable project:** the buildable sketches and host console live in
> [`arduino/`](arduino/) — `arduino/pot_reader/pot_reader.ino` (read a feedback
> potentiometer) and `arduino/motor_control/motor_control.ino` (keyboard drive
> with ±80° watchdog + auto-center), plus `arduino/host/monitor.py`. See
> [`arduino/README.md`](arduino/README.md) for wiring, build, and run steps
> (toolchain install: `../teachbox/arduino/INSTALL.md`). The per-axis
> calibration tables below are the measured data those sketches use
> (`AXIS_CAL` in `arduino/pot_reader/rob3_axis.h`); the listings in this
> document are a narrative walkthrough — treat the files under `arduino/` as
> authoritative.

## L293 (L293D) driver pinout

```txt
                                 ---u---
        (Speed Motor 1)  EN 1 --|1     16|-- VCC1 (Logic Power: +5V from Arduino)
      (Direction 1A)  INPUT 1 --|2     15|-- INPUT 4 (Direction 2B)
         (Motor 1 -) OUTPUT 1 --|3     14|-- OUTPUT 4 (Motor 2 -)
                          GND --|4     13|-- GND
                          GND --|5     12|-- GND
         (Motor 1 +) OUTPUT 2 --|6     11|-- OUTPUT 3 (Motor 2 +)
      (Direction 1B)  INPUT 2 --|7     10|-- INPUT 3 (Direction 2A)
  (Motor Power: +9V)     VCC2 --|8      9|-- EN 2 (Speed Motor 2 / Your Channel #2)
                                 -------
```

## 💻 Minimalist Potentiometer Reader Sketch

```bash
               +-----------------------------------+
               |        ARDUINO UNO BOARD          |
               |      5V         GND         A0    |
               +------+-----------+-----------+----+
  6-PIN CONNECTOR     |           |           |
  TO ROB3 AXIS 1      |           |           |
               +------+-----------+-----------+----+
               |    Pin 2       Pin 4       Pin 1  |
               |    [5V]        [GND]    [Signal]  |
               +------+-----------+-----------+----+
  5kΩ PRECISION       |           |           |
  POTENTIOMETER       |           |           |
               +------v-----------v-----------v----+
               |  Resistor     Resistor     Wiper  |
               |   High (+)    Low (-)     Signal  |
               +-----------------------------------+
```

### Channel #1

| Physical Position | Raw 10-bit ADC (Arduino `0...1023`) | ROB3 8-bit Scale (Decimal `0...255`) | ROB3 8-bit Scale (HEX `0x00...0xFF`) |
| :--- | :--- | :--- | :--- |
| **First Limit (+90°)** | `185` | `46` | `0x2E` |
| **Center Position (0°)** | `482` | `120` | `0x78` |
| **Second Limit (-90°)** | `779` | `194` | `0xC2` |

## Channel 2

| Physical Position | Real Angle | Raw 10-bit ADC | ROB3 8-bit Scale (DEC) | ROB3 8-bit Scale (HEX) |
| :--- | :--- | :--- | :--- | :--- |
| **Max Upper Limit** | **`+70.0°`** | `513` | `127` | `0x7F` |
| **Horizontal Reference**| **`0.0°`** | `620` | `154` | `0x9A` |
| **Max Lower Limit** | **`-44.0°`** | `756` | `188` | `0xBC` |

## Channel 3

| Physical Position | Real Target Angle | Raw 10-bit ADC (Arduino) | ROB3 8-bit Scale (DEC) | ROB3 8-bit Scale (HEX) |
| :--- | :--- | :--- | :--- | :--- |
| **Horizontal Reference**| **`0.0°`** | `271` | `67` | `0x43` |
| **Downward Pitch**     | **`-90.0°`** | `572` | `142` | `0x8E` |
| **Max Physical Floor**  | **`-110.0°`** | `639` | `159` | `0x9F` |

## Channel 4

The motor works, the potentiometer can rotate from 0 to 1023. Set it back. Now it needs a calibration.

## Channel 5

| Point Label | Coordinate X | Coordinate Y | Offset from 0 (Δ X, Δ Y) | Direction | Calculated Angle |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Center Zero (0°)** | 506 | 126 | (0, 0) | Reference Center | **0°** |
| **First 90°** | 162 | 40 | (-344, -86) | Up-Left | **+90°** |
| **First x** | 95 | 23 | (-411, -103) | Up-Left (further out) | **+107.5°** |
| **Second 90°** | 862 | 214 | (+356, +88) | Down-Right | **-90°** |
| **Second x** | 922 | 229 | (+416, +103) | Down-Right (further out) | **-105.2°** |

# Channel 6

| State | Coordinate | Distance |
| :--- | :--- | :--- |
| **Opened / Closed (Base)** | 765 | **0 mm** |
| **Closed / Opened (Target)** | 206 | **60 mm** |

## Angle/position ↔ ROB3 count mapping (worked examples)

The ROB3 firmware commands and servos axes in **raw 8-bit ADC counts (0..255)**,
not in degrees or mm (see
`../../firmware/src/annotated/ext1_axis_servo.annotated.asm`). The pots are
**absolute** transducers, so there is no homing — a count *is* the position.
Converting a physical angle/position to a `POS a . <count>` value (or a reading
back to an angle) is a **per-axis linear interpolation** between two measured
points:

```
count  = count_A + (angle - angle_A) * (count_B - count_A) / (angle_B - angle_A)
angle  = angle_A + (count - count_A) * (angle_B - angle_A) / (count_B - count_A)
```

where (angle_A, count_A) and (angle_B, count_B) are two measured calibration
points for that axis. The ROB3 count = Arduino 10-bit reading / 4.

Key gotchas the measured data shows: **0° is NOT count 128**, each axis uses only
a **sub-range** of 0..255, and the **direction can be inverted** (higher count =
more negative). So every axis needs its OWN two measured points.

### Example A — Shoulder (axis 2), from measured data above  [HW-bench]

Points: +70° → 127 (0x7F), 0° → 154 (0x9A), −44° → 188 (0xBC).
Slope over the span = (188 − 127) / (−44 − 70) ≈ **−0.535 count/deg** (note: count
*rises* as angle goes negative).

- Command **+35°**: count = 127 + (35 − 70)(−0.535) ≈ **146 (0x92)** → `POS 2 . 146`
- Read **170** back: angle = 70 + (170 − 127)/(−0.535) ≈ **−10°**

### Example B — Gripper (axis 6), from measured data above  [HW-bench]

Points: 0 mm → raw 765 → **191 (0xBF)**, 60 mm → raw 206 → **52 (0x34)**.
Slope = (52 − 191) / (60 − 0) ≈ **−2.32 count/mm** (count falls as it opens).

- Command **30 mm**: count = 191 + 30(−2.32) ≈ **122 (0x7A)** → `POS 6 . 122`

### Example C — a ±130° axis (NOT yet measured — MEASURE ME)

If you have an axis with, say, a **−130° … +130°** range, its endpoint counts are
**unknown until measured** — do NOT assume 0° = 128 or a full 0..255 span. Drive
the joint to each limit, read the count with `pot_reader`, then interpolate.
Illustrative ONLY (placeholder counts, not real):

```
measure:  -130° -> count 30 ,  +130° -> count 225        (EXAMPLE numbers)
slope   = (225 - 30) / (130 - (-130)) = 195 / 260 = 0.75 count/deg
0°   -> 30 + (0 - (-130)) * 0.75  = 128 (0x80)
+65° -> 30 + (65 + 130) * 0.75    = 176 (0xB0)
```

Replace the placeholder 30/225 with the axis's real measured endpoints before
trusting any result. These per-axis points are what `arduino/pot_reader/rob3_axis.h`
stores in `AXIS_CAL[0..5]`.

## ⚠️ Safety: the firmware does NOT enforce per-axis travel limits

Traced in `../../firmware/src/main.asm` (the `POS a . n ENT` value-entry path):
the firmware validates only that **the value is 0..255** (the decimal
accumulator at `jump_0D65`/`jump_0D78` does `*10 + digit` and jumps to the ERR
handler `jump_0D23` on byte overflow) and that **the axis is 1..6**
(`jump_0CA3`: `dec A / cjne #06 / jnc -> ERR`). The accepted 0..255 value is then
stored **straight into target[a] with NO per-axis min/max check**. [BYTE]

Consequences — do NOT treat 0..255 as safe:

- 0..255 is the **electrical pot range**, which is **wider than an axis's usable
  mechanical travel**. Each axis only sweeps a **sub-range** of 0..255 (e.g. the
  measured shoulder ~127..188, elbow ~67..159 above).
- Commanding a count outside that axis's usable window drives the joint **into a
  hard stop**: the servo chases a target the pot can never read, so the motor
  keeps driving and **stalls against the endstop** (overcurrent/heat).
- There are **no software soft-limits** in the ROM. YOU must keep every
  `POS a . n` within that axis's measured `[min_count, max_count]`. This is
  exactly why the Arduino `motor_control` sketch adds its own ±limit watchdog.

Practical rule: for each axis, measure the count at both **safe** mechanical
limits with `pot_reader`, record `[min_count, max_count]`, and only issue counts
inside that window. (Provenance: the "value 0..255 + axis 1..6, no position
clamp" behavior is [BYTE]; "no clamp anywhere in the ROM" is [INFER] — the
POS-entry, axis-select, and target-store paths were traced, but a negative
across the entire ROM is not exhaustively proven.)

### Sketch

```cpp
/*
  ROB3 Axis 1: Pure Potentiometer Measurement
  
  Connections:
  - Potentiometer 5V     -> Arduino 5V
  - Potentiometer GND    -> Arduino GND
  - Potentiometer Signal -> Arduino A0
*/

const int POT_PIN = A0; // Analog input pin connected to your potentiometer signal

void setup() {
  // Start the USB serial communication at 9600 baud
  Serial.begin(9600);
  
  Serial.println("");
  Serial.println("=============================================");
  Serial.println("   ROB3 AXIS 1: POTENTIOMETER TEST MODE      ");
  Serial.println("   Move the robot joint manually to test...  ");
  Serial.println("=============================================");
}

void loop() {
  // 1. Read the raw 10-bit value from Arduino's ADC (0 to 1023)
  int rawAdc = analogRead(POT_PIN);
  
  // 2. Convert the 10-bit raw value to ROB3's native 8-bit scale (0 to 255)
  int rob3Resolution = map(rawAdc, 0, 1023, 0, 255);

  // 3. Print the results clearly to the Serial Monitor
  Serial.print("Raw ADC (0-1023): ");
  Serial.print(rawAdc);
  
  Serial.print("\t| ROB3 Resolution (0-255): ");
  Serial.print(rob3Resolution);
  
  Serial.print("\t| HEX: 0x");
  if(rob3Resolution < 16) Serial.print("0"); // Add leading zero for clean formatting
  Serial.println(rob3Resolution, HEX);

  // Wait 150 milliseconds before taking the next reading
  delay(150); 
}
```

## 🎯 Summary Table for Motor #1

| L293D Pin # | Pin Name | Connected To | Functional Description |
| :--- | :--- | :--- | :--- |
| **Pin 1** | `EN 1` | **Arduino 5V** | Master Enable Switch. Turns on the left half of the chip. |
| **Pin 2** | `INPUT 1` | **Arduino Digital D2** | Direction Control Input A. |
| **Pin 3** | `OUTPUT 1` | **ROB3 Connector Pin 6** | Motor (+) Power Output line. |
| **Pin 4** | `GND` | **Common Ground** | Shared Ground connection for the circuit. |
| **Pin 5** | `GND` | **Common Ground** | Shared Ground connection for the circuit. |
| **Pin 6** | `OUTPUT 2` | **ROB3 Connector Pin 5** | Motor (-) Power Output line. |
| **Pin 7** | `INPUT 2` | **Arduino Digital D3** | Direction Control Input B. |
| **Pin 8** | `VCC 2` | **External 9V Power (+)** | High-voltage supply dedicated to spinning the motor. |
| **Pin 16** | `VCC 1` | **Arduino 5V** | Low-voltage supply to power the chip's internal logic. |


```cpp
/*
  ROB3 Axis 1: Keyboard Control, Strict +/- 80° Watchdog & Auto-Zero Target
  
  HOW TO OPERATE IN SERIAL MONITOR:
  - Type 'F' / 'f' -> Move FORWARD continuously
  - Type 'B' / 'b' -> Move BACKWARD continuously
  - Type '0'       -> Automatically target and drive to Center position (0°)
  - Any other key  -> INSTANT EMERGENCY STOP
*/

const int MOTOR_IN1  = 2;  // Connects to L293D Pin 2
const int MOTOR_IN2  = 3;  // Connects to L293D Pin 7
const int POT_PIN    = A0; // Feedback Signal (ROB3 Connector Pin 1)

// Master Physical Potentiometer Calibration Data
const int ADC_AT_PLUS_90  = 185; 
const int ADC_AT_MINUS_90 = 779; 

// Enforced Boundaries and Reference Points
const int HARD_LIMIT_POS_80 = 218; // Target Positive Limit (+80°)
const int HARD_LIMIT_NEG_80 = 746; // Target Negative Limit (-80°)
const int ADC_CENTER_0      = 482; // Target Center Position (0°)

// Hysteresis window to stop the motor from rapidly shuddering at 0°
const int ZERO_THRESHOLD_BUFFER = 5; 

// Tracking states
enum MotorState { MOTOR_STOP, MOTOR_FORWARD, MOTOR_BACKWARD };
MotorState currentDirection = MOTOR_STOP;
bool isAutoCentering = false;

void setup() {
  pinMode(MOTOR_IN1, OUTPUT);
  pinMode(MOTOR_IN2, OUTPUT);
  
  stopMotor(); // Enforce absolute halt at boot
  
  Serial.begin(9600);
  Serial.println("\n=============================================");
  Serial.println("   ROB3 AXIS 1: AUTO-ZERO SETPOINT ACTIVE    ");
  Serial.println("=============================================");
  Serial.println(" COMMANDS: [F] = Forward, [B] = Backward     ");
  Serial.println("           [0] = Auto-Center to 0°           ");
  Serial.println("           Any other key = EMERGENCY STOP    ");
  Serial.println("=============================================");
}

void loop() {
  int currentAdc = analogRead(POT_PIN);
  float currentAngle = mapFloat(currentAdc, ADC_AT_PLUS_90, ADC_AT_MINUS_90, 90.0, -90.0);

  // --- 1. KEYBOARD INPUT PROCESSING ---
  if (Serial.available() > 0) {
    char inputChar = Serial.read();

    if (inputChar != '\n' && inputChar != '\r') {
      
      // Handle Auto-Center Request
      if (inputChar == '0') {
        Serial.println("\n[AUTO] Auto-centering routine engaged. Targeting 0°...");
        isAutoCentering = true;
      }
      
      // Handle Manual Forward
      else if (inputChar == 'f' || inputChar == 'F') {
        isAutoCentering = false; // Interrupted by manual command
        if (currentAdc < HARD_LIMIT_POS_80) {
          Serial.println("\n[BLOCKED] Cannot move Forward! Past +80° limit.");
        } else {
          Serial.println("\n[COMMAND] Driving FORWARD...");
          moveMotorDigital(true);
        }
      } 
      
      // Handle Manual Backward
      else if (inputChar == 'b' || inputChar == 'B') {
        isAutoCentering = false; // Interrupted by manual command
        if (currentAdc > HARD_LIMIT_NEG_80) {
          Serial.println("\n[BLOCKED] Cannot move Backward! Past -80° limit.");
        } else {
          Serial.println("\n[COMMAND] Driving BACKWARD...");
          moveMotorDigital(false);
        }
      } 
      
      // Handle Manual Halt (Any other key)
      else {
        Serial.println("\n[COMMAND] -> EMERGENCY STOP REQUESTED");
        isAutoCentering = false;
        stopMotor();
      }
    }
  }

  // --- 2. AUTOMATIC CENTERING CONTROLLER ENGINE ---
  if (isAutoCentering) {
    int currentError = currentAdc - ADC_CENTER_0;

    // Check if the arm has arrived inside our acceptable deadband around 0°
    if (abs(currentError) <= ZERO_THRESHOLD_BUFFER) {
      stopMotor();
      isAutoCentering = false;
      Serial.println("\n[AUTO] Target Achieved! Motor braked smoothly at center (0°).");
    } 
    else {
      // Remember: +90° is Low ADC (185) and -90° is High ADC (779)
      if (currentError > 0) {
        // We are on the Negative side (High ADC). Must move FORWARD to decrease ADC towards center.
        if (currentDirection != MOTOR_FORWARD) {
          moveMotorDigital(true);
        }
      } 
      else {
        // We are on the Positive side (Low ADC). Must move BACKWARD to increase ADC towards center.
        if (currentDirection != MOTOR_BACKWARD) {
          moveMotorDigital(false);
        }
      }
    }
  }

  // --- 3. INTELLIGENT DIRECTIONAL WATCHDOG ---
  if (currentAdc > HARD_LIMIT_NEG_80 && currentDirection != MOTOR_FORWARD) {
    stopMotor();
    isAutoCentering = false; // Kill auto routine if safety is breached
    static unsigned long lastHaltAlert = 0;
    if (millis() - lastHaltAlert > 2000) {
      Serial.print("\n[WATCHDOG HALT] Past -80° limit! (ADC: "); Serial.print(currentAdc);
      Serial.println("). PRESS 'F' or '0' TO RECOVER.");
      lastHaltAlert = millis();
    }
  }
  else if (currentAdc < HARD_LIMIT_POS_80 && currentDirection != MOTOR_BACKWARD) {
    stopMotor();
    isAutoCentering = false; // Kill auto routine if safety is breached
    static unsigned long lastHaltAlert = 0;
    if (millis() - lastHaltAlert > 2000) {
      Serial.print("\n[WATCHDOG HALT] Past +80° limit! (ADC: "); Serial.print(currentAdc);
      Serial.println("). PRESS 'B' or '0' TO RECOVER.");
      lastHaltAlert = millis();
    }
  }

  // Print telemetry dashboard updates every 400ms
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint > 400) {
    Serial.print("Raw ADC: "); Serial.print(currentAdc);
    Serial.print("\t| Angle: "); Serial.print(currentAngle, 1);
    Serial.print("°\t| Engine: ");
    if (isAutoCentering) Serial.print("AUTO-ALIGNING (");
    else Serial.print("MANUAL (");
    
    if (currentDirection == MOTOR_FORWARD) Serial.println("FORWARD)");
    else if (currentDirection == MOTOR_BACKWARD) Serial.println("BACKWARD)");
    else Serial.println("STOPPED)");
    
    lastPrint = millis();
  }
}

void moveMotorDigital(bool forward) {
  if (forward) {
    digitalWrite(MOTOR_IN1, HIGH);
    digitalWrite(MOTOR_IN2, LOW);
    currentDirection = MOTOR_FORWARD;
  } else {
    digitalWrite(MOTOR_IN1, LOW);
    digitalWrite(MOTOR_IN2, HIGH);
    currentDirection = MOTOR_BACKWARD;
  }
}

void stopMotor() {
  digitalWrite(MOTOR_IN1, LOW);
  digitalWrite(MOTOR_IN2, LOW);
  currentDirection = MOTOR_STOP;
}

float mapFloat(float x, float in_min, float in_max, float out_min, float out_max) {
  return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}
```

## References

* https://www.winford.com/products/brk2x3.php
