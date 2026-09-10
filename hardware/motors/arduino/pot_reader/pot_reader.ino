// pot_reader.ino
//
// ROB3 axis — pure potentiometer measurement.
//
// Reads one axis feedback potentiometer on A0 and prints the raw 10-bit ADC
// value alongside the ROB3 native 8-bit scale (0..255) and its hex form.
// Move the joint by hand and watch the values track.
//
// Target: Arduino UNO R3. Wiring: see rob3_axis.h and ../README.md.

#include "rob3_axis.h"

void setup() {
  Serial.begin(9600);
  Serial.println();
  Serial.println(F("============================================="));
  Serial.println(F("   ROB3 axis: POTENTIOMETER TEST MODE"));
  Serial.println(F("   Move the joint by hand to test..."));
  Serial.println(F("============================================="));
}

void loop() {
  int raw = analogRead(PIN_POT);   // 0..1023
  int scaled = rob3Scale(raw);     // 0..255 (ROB3 native)

  Serial.print(F("Raw ADC (0-1023): "));
  Serial.print(raw);
  Serial.print(F("\t| ROB3 (0-255): "));
  Serial.print(scaled);
  Serial.print(F("\t| HEX: 0x"));
  if (scaled < 16) Serial.print('0');   // leading zero
  Serial.println(scaled, HEX);

  delay(150);
}
