# Motor Test

## L293N

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
