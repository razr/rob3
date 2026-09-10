// led_test.ino
//
// ROB3 Teachbox — indicator-LED bring-up test.
//
// Cycles the 74LS138 through all eight decoder outputs (/Y0../Y7), lighting
// each multiplexed indicator LED in turn, then pulses the directly-driven
// NOP LED. Progress is printed to the serial monitor at 9600 baud.
//
// Target: Arduino UNO R3 (ATmega328P).
// Wiring: see teachbox_pins.h and hardware/teachbox/board.md.
//
// The decoder is disabled (EN HIGH) while the address lines change, to avoid
// briefly lighting the wrong LED ("ghosting") during transitions.

#include "teachbox_pins.h"

void setup() {
  Serial.begin(9600);
  Serial.println(F("=================================================="));
  Serial.println(F(" ROB3 Teachbox LED test (incl. direct NOP LED)"));
  Serial.println(F("=================================================="));

  pinMode(PIN_A0, OUTPUT);
  pinMode(PIN_A1, OUTPUT);
  pinMode(PIN_A2, OUTPUT);
  pinMode(PIN_EN, OUTPUT);
  pinMode(PIN_NOP, OUTPUT);

  // Start with the decoder disabled and the NOP LED off.
  digitalWrite(PIN_EN, HIGH);
  digitalWrite(PIN_NOP, LOW);
}

void loop() {
  // Walk the eight decoder outputs.
  for (int address = 0; address < 8; address++) {
    // Disable the decoder while switching the address (prevents ghosting).
    digitalWrite(PIN_EN, HIGH);
    teachboxSetAddress(address);

    Serial.print(F("Address [A2 A1 A0]: "));
    Serial.print((address & 0x04) ? F("1 ") : F("0 "));
    Serial.print((address & 0x02) ? F("1 ") : F("0 "));
    Serial.print((address & 0x01) ? F("1 ") : F("0 "));
    Serial.print(F(" -> "));
    Serial.println(LED_NAMES[address]);

    // Enable the decoder: the selected LED turns on (active-LOW output).
    digitalWrite(PIN_EN, LOW);
    delay(500);
  }

  // Decoder LEDs off, then exercise the standalone NOP LED.
  digitalWrite(PIN_EN, HIGH);
  Serial.println(F("-> NOP LED (direct drive)"));
  digitalWrite(PIN_NOP, HIGH);
  delay(1000);
  digitalWrite(PIN_NOP, LOW);

  Serial.println(F("--- loop complete; restarting ---"));
  delay(1000);
}
