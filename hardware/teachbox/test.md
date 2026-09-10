# 5x5 Teachbox Keypad Test Project

This project recreates the interface of a vintage 1985 Industrial Teachbox using an ELEGOO UNO R3 (ATmega328P) and a Python script running on a modern PC.

The original host controller interface utilizes a T74LS138B1 3-to-8 line decoder combined with passive resistor pull-ups on the mainboard to drive a 5x5 scanning button matrix and multiplexed indicator LEDs over a standard DB25 connector.
By leveraging the Arduino's internal INPUT_PULLUP resistors, this setup interfaces safely with modern hardware without needing the original mainboard's 10kΩ/100kΩ resistor arrays.

> **Runnable project:** the buildable sketches and host script live in
> [`arduino/`](arduino/) — `arduino/led_test/led_test.ino`,
> `arduino/keypad_test/keypad_test.ino`, and `arduino/host/monitor.py`. See
> [`arduino/README.md`](arduino/README.md) for build/upload/run instructions
> (arduino-cli or the Arduino IDE). The listings in this document are a
> narrative walkthrough; treat the files under `arduino/` as authoritative.

## 🛠️ Hardware Requirements

- ELEGOO UNO R3 (or any standard Arduino Uno R3)
- Futheda Lötfreies D-sub DB25 Breakout Board (Female/Buchse)
- Jumper Wires (Male-to-Male" from the Elegoo Super Starter Kit)
- USB Type-B Cable (To connect the Elegoo board to your PC)

## 🔌 LED Hardware Wiring Map

| Decoder Signal | Physical DB25 Pin | Arduino UNO Pin | Role in the System |
| :--- | :---: | :---: | :--- |
| **+5V** (VCC) | **13** | **5V** | Power supply for the logic chips |
| **GND** (Ground) | **3** | **GND** | Common ground reference |
| **A0** (Address Bit 0) | **23** | **Digital 2** | Toggles the lowest address bit |
| **A1** (Address Bit 1) | **10** | **Digital 3** | Toggles the middle address bit |
| **A2** (Address Bit 2) | **22** | **Digital 4** | Toggles the highest address bit |
| **/E1, /E2** (Enable) | **9** | **Digital 5** | Strobe line (Activates the 74LS138) |
| **DO4 (NOP LED)** | **11** | **Digital 6** | Direct control line for NOP LED |

```text
       ARDUINO UNO R3                                     DB25 FEMALE CONNECTOR
    +------------------+                                      (Rear Solder View)
    |                  |                                   
    |               5V |==============================+   \ 13  12  11  10   9   8   7   6   5   4   3   2   1   /
    |              GND |==========================+   |    \ o   o   o   o   o   o   o   o   o   o   o   o   o  /
    |                  |                          |   |     \                                                  /
    |        Digital 2 |======================+   |   |      \  o   o   o   o   o   o   o   o   o   o   o   o /
    |        Digital 3 |==================+   |   |   |       \25  24  23  22  21  20  19  18  17  16  15  14/
    |        Digital 4 |==============+   |   |   |   |        ----------------------------------------------
    |        Digital 5 |==========+   |   |   |   |   |        
    |        Digital 6 |======+   |   |   |   |   |   |        
    +------------------+      |   |   |   |   |   |   |
                              |   |   |   |   |   |   |        
                              |   |   |   |   |   |   +=========> Pin 13 (VCC Logics)
                              |   |   |   |   |   +=============> Pin 3  (GND System Reference)
                              |   |   |   |   +=================> Pin 23 (Address Bit A0)
                              |   |   |   +=====================> Pin 10 (Address Bit A1)
                              |   |   +=========================> Pin 22 (Address Bit A2)
                              |   +=============================> Pin 9  (Strobe /Enable)
                              +=================================> Pin 11 (Direct NOP LED Input)
```

## ⚙️ LED Software

```cpp
// Assign Arduino pins according to your DB25 connection map
const int pin_A0  = 2; // Connected to DB25 pin 23 (Line DO5 / Address A0)
const int pin_A1  = 3; // Connected to DB25 pin 10 (Line DO6 / Address A1)
const int pin_A2  = 4; // Connected to DB25 pin 22 (Line DO7 / Address A2)
const int pin_EN  = 5; // Connected to DB25 pin 9  (Enable line /E1, /E2)
const int pin_NOP = 6; // Connected to DB25 pin 11 (Line DO4 / Direct NOP LED)

// List of teachbox LED names for serial monitor debugging output
const char* ledNames[] = {
  "🔴 ERROR LED", // Address 000 (Output /Y0)
  "🟡 OUT LED",   // Address 001 (Output /Y1)
  "🟡 POS LED",   // Address 010 (Output /Y2)
  "🟡 TIM LED",   // Address 011 (Output /Y3)
  "🟡 MARK LED",  // Address 100 (Output /Y4)
  "🟡 GOTO LED",  // Address 101 (Output /Y5)
  "🟡 IF LED",    // Address 110 (Output /Y6)
  "🟢 RUN LED"    // Address 111 (Output /Y7)
};

void setup() {
  // Initialize serial communication with PC for testing monitoring
  Serial.begin(9600);
  Serial.println("==================================================");
  Serial.println(" Starting ROB3 Teachbox LED Test with NOP LED Included ");
  Serial.println("==================================================");

  // Configure control pins as outputs
  pinMode(pin_A0, OUTPUT);
  pinMode(pin_A1, OUTPUT);
  pinMode(pin_A2, OUTPUT);
  pinMode(pin_EN, OUTPUT);
  pinMode(pin_NOP, OUTPUT); // Configure NOP LED pin as output

  // Disable the decoder and turn off NOP LED on startup
  digitalWrite(pin_EN, HIGH); 
  digitalWrite(pin_NOP, LOW);
}

void loop() {
  // Loop through values from 0 to 7 (8 sequential LEDs total)
  for (int address = 0; address < 8; address++) {
    
    // Temporarily turn off the decoder to avoid ghosting/glitches while switching addresses
    digitalWrite(pin_EN, HIGH);

    // Split the current decimal number (0-7) into 3 independent binary bits (0 or 1):
    // Check bit 0 and set HIGH or LOW on Arduino Pin 2 (goes to DB25 pin 23)
    digitalWrite(pin_A0, (address & 0x01) ? HIGH : LOW); 
    
    // Check bit 1 and set HIGH or LOW on Arduino Pin 3 (goes to DB25 pin 10)
    digitalWrite(pin_A1, (address & 0x02) ? HIGH : LOW); 
    
    // Check bit 2 and set HIGH or LOW on Arduino Pin 4 (goes to DB25 pin 22)
    digitalWrite(pin_A2, (address & 0x04) ? HIGH : LOW); 

    // Print current state info to the Serial Monitor
    Serial.print("Address [A2 A1 A0]: ");
    Serial.print((address & 0x04) ? "1 " : "0 ");
    Serial.print((address & 0x02) ? "1 " : "0 ");
    Serial.print((address & 0x01) ? "1 " : "0 ");
    Serial.print(" -> Activating: ");
    Serial.println(ledNames[address]);

    // Enable the decoder (send LOW to DB25 pin 9) - the selected LED turns ON
    digitalWrite(pin_EN, LOW);

    // Keep the LED turned on for 500 milliseconds (half a second)
    delay(500); 
  }

  // --- End of the 74LS138 loop: Turn off decoder LEDs and test the independent NOP LED ---
  digitalWrite(pin_EN, HIGH); // Turn off all 74LS138 decoder LEDs
  
  Serial.println("-> Activating: 🔵 NOP LED (Direct Control)");
  digitalWrite(pin_NOP, HIGH); // Turn ON the NOP LED directly via Pin 6
  delay(1000);                 // Keep it on for 1 second

  digitalWrite(pin_NOP, LOW);  // Turn OFF the NOP LED
  Serial.println("--- Loop completed. Short pause before restart ---");
  delay(1000);
}
```

## 🔢 Keypad 5x5


| Decoder/Input Signal | Physical DB25 Pin | Arduino UNO Pin | System Role |
| :--- | :---: | :---: | :--- |
| **+5V** (VCC) | **13** | **5V** | Power supply for all logic chips |
| **GND** (Ground) | **3** | **GND** | Common system ground reference |
| **A0** (Address Bit 0) | **23** | **Digital 2** | Matrix row selection bit 0 |
| **A1** (Address Bit 1) | **10** | **Digital 3** | Matrix row selection bit 1 |
| **A2** (Address Bit 2) | **22** | **Digital 4** | Matrix row selection bit 2 |
| **/E1, /E2** (Enable)| **9** | **Digital 5** | Activates the 74LS138 row scanner |
| *[ RESERVED FOR LED ]*| — | *Digital 6* | *Left empty for your future LED project* |
| **Col Group 1** | **5** | **Digital 7** | Read Group 1 (Arrows, DEL, NOP, 8, 9, ENT, ERR) |
| **Col Group 2** | **18** | **Digital 8** | Read Group 2 (Numeric keys 0 to 7) |
| **Col Group 3** | **17** | **Digital 9** | Read Group 3 (System mode keys INS to RUN) |
| **STOP Button Input** | **4** | **Digital 12** | Direct standalone safety input line |


```cpp
// Control pins for the 74LS138 row decoder matrix scanner
const int pin_A0 = 2;  // Connected to DB25 pin 23 (Address A0)
const int pin_A1 = 3;  // Connected to DB25 pin 10 (Address A1)
const int pin_A2 = 4;  // Connected to DB25 pin 22 (Address A2)
const int pin_EN = 5;  // Connected to DB25 pin 9  (Enable line /E1, /E2)

// Input pins for reading column groups (Leaves Digital 6 empty)
const int pin_Group1 = 7; // Connected to DB25 pin 5  (DEL, 8, 9, arrows, NOP, ERR, ENT)
const int pin_Group2 = 8; // Connected to DB25 pin 18 (7, 4, 5, 6, 1, 2, 3, 0)
const int pin_Group3 = 9; // Connected to DB25 pin 17 (RUN, IF, GOTO, MARK, TIM, POS, OUT, INS)

// Dedicated input pin for the standalone STOP button
const int pin_STOP = 12; // Connected to DB25 pin 4

void setup() {
  // Initialize serial communication with PC at 9600 baud
  Serial.begin(9600);
  Serial.println("==================================================");
  Serial.println(" ROB3 Teachbox Button Test (Glitch-Free LED Mode) ");
  Serial.println("==================================================");

  // Configure row decoder pins strictly as outputs
  pinMode(pin_A0, OUTPUT);
  pinMode(pin_A1, OUTPUT);
  pinMode(pin_A2, OUTPUT);
  pinMode(pin_EN, OUTPUT);
  
  digitalWrite(pin_EN, HIGH); // Disable decoder initially

  // Secure all input lines with internal pullups to destroy static noise
  pinMode(pin_Group1, INPUT_PULLUP); 
  pinMode(pin_Group2, INPUT_PULLUP); 
  pinMode(pin_Group3, INPUT_PULLUP); 
  pinMode(pin_STOP, INPUT_PULLUP);   
}

// Function to decode and print the exact button label
void processKeyPress(int row, int group) {
  String keyName = "UNKNOWN KEY";

  if (group == 1) { // DB25 Pin 5 Group (Commands & Arrows)
    if (row == 0) keyName = "8";
    if (row == 1) keyName = "9";
    if (row == 2) keyName = "NOP";
    if (row == 3) keyName = "↑ - → (UP / RIGHT)";
    if (row == 4) keyName = "↓ + ← (DOWN / LEFT)";
    if (row == 5) keyName = "ENT";
    if (row == 6) keyName = "ERR CLR";
    if (row == 7) keyName = "DEL";
  } 
  else if (group == 2) { // DB25 Pin 18 Group (Numeric Keys)
    if (row == 0) keyName = "0";
    if (row == 1) keyName = "1";
    if (row == 2) keyName = "2";
    if (row == 3) keyName = "3";
    if (row == 4) keyName = "4";
    if (row == 5) keyName = "5";
    if (row == 6) keyName = "6";
    if (row == 7) keyName = "7";
  } 
  else if (group == 3) { // DB25 Pin 17 Group (System Mode Keys)
    if (row == 0) keyName = "INS";
    if (row == 1) keyName = "OUT";
    if (row == 2) keyName = "POS";
    if (row == 3) keyName = "TIM";
    if (row == 4) keyName = "MARK";
    if (row == 5) keyName = "GOTO";
    if (row == 6) keyName = "IF";
    if (row == 7) keyName = "RUN";
  }

  Serial.print("-> Pressed Button: [ ");
  Serial.print(keyName);
  Serial.print(" ] (Row /Y");
  Serial.print(row);
  Serial.print(", Group ");
  Serial.print(group);
  Serial.println(")");
}

void loop() {
  // 1. Poll the standalone STOP line (Active LOW)
  if (digitalRead(pin_STOP) == LOW) {
    Serial.println("-> Pressed Button: [ STOP ] (Direct Line)");
    delay(300);
    return; 
  }

  // 2. Scan through decoder rows /Y0 to /Y7
  for (int row = 0; row < 8; row++) {
    
    // CRITICAL FIX: Explicitly shut down the decoder before changing bits
    // This blocks any voltage leaks or "ghosting" to the LEDs during transition
    digitalWrite(pin_EN, HIGH); 
    delayMicroseconds(5); // Give the IC logic gates a moment to completely clear

    // Drive binary address states cleanly while the chip is sleeping
    digitalWrite(pin_A0, (row & 0x01) ? HIGH : LOW);
    digitalWrite(pin_A1, (row & 0x02) ? HIGH : LOW);
    digitalWrite(pin_A2, (row & 0x04) ? HIGH : LOW);
    delayMicroseconds(5); // Let the new address settle perfectly on the copper wires

    // Wake up the decoder safely to ground the target matrix row node
    digitalWrite(pin_EN, LOW);
    delayMicroseconds(50); // Settle buffer for reading paths

    // Read all 3 Groups simultaneously (Active press = LOW under INPUT_PULLUP)
    int statusG1 = digitalRead(pin_Group1);
    int statusG2 = digitalRead(pin_Group2);
    int statusG3 = digitalRead(pin_Group3);

    // Filter signals and execute matching hits
    if (statusG1 == LOW) { 
      delayMicroseconds(60); // Double-check stability to filter out spark spikes
      if (digitalRead(pin_Group1) == LOW) { processKeyPress(row, 1); delay(300); break; }
    }
    if (statusG2 == LOW) { 
      delayMicroseconds(60); 
      if (digitalRead(pin_Group2) == LOW) { processKeyPress(row, 2); delay(300); break; }
    }
    if (statusG3 == LOW) { 
      delayMicroseconds(60); 
      if (digitalRead(pin_Group3) == LOW) { processKeyPress(row, 3); delay(300); break; }
    }
  }
  
  delay(10); // Matrix polling loop frequency pace anchor
}
```
