// keypad_test.ino
//
// ROB3 Teachbox — 5x5 key-matrix bring-up test.
//
// Uses the 74LS138 (driven by A0/A1/A2 + enable) to strobe one matrix row
// (/Y0../Y7) at a time, then reads the three column groups. A pressed key
// pulls its column group LOW (INPUT_PULLUP). The standalone STOP button is
// polled directly. Detected keys are printed to serial at 9600 baud.
//
// Target: Arduino UNO R3 (ATmega328P).
// Wiring: see teachbox_pins.h and hardware/teachbox/board.md.
//
// Key layout per row (/Yn) and column group, from board.md:
//   Group 1 (DB25 5) : 8, 9, NOP, UP/RIGHT, DOWN/LEFT, ENT, ERR CLR, DEL
//   Group 2 (DB25 18): 0, 1, 2, 3, 4, 5, 6, 7
//   Group 3 (DB25 17): INS, OUT, POS, TIM, MARK, GOTO, IF, RUN

#include "teachbox_pins.h"

// Row (/Yn) -> key label, per column group. Index [group-1][row].
static const char* const KEY_MAP[3][8] = {
  // Group 1 (DB25 pin 5)
  { "8", "9", "NOP", "UP/RIGHT (^ -/+)", "DOWN/LEFT (v +/-)", "ENT", "ERR CLR", "DEL" },
  // Group 2 (DB25 pin 18)
  { "0", "1", "2", "3", "4", "5", "6", "7" },
  // Group 3 (DB25 pin 17)
  { "INS", "OUT", "POS", "TIM", "MARK", "GOTO", "IF", "RUN" }
};

void reportKey(int row, int group) {
  const char* name = (group >= 1 && group <= 3) ? KEY_MAP[group - 1][row] : "UNKNOWN";
  Serial.print(F("-> key: [ "));
  Serial.print(name);
  Serial.print(F(" ]  (/Y"));
  Serial.print(row);
  Serial.print(F(", group "));
  Serial.print(group);
  Serial.println(F(")"));
}

void setup() {
  Serial.begin(9600);
  Serial.println(F("=================================================="));
  Serial.println(F(" ROB3 Teachbox key-matrix test"));
  Serial.println(F("=================================================="));

  pinMode(PIN_A0, OUTPUT);
  pinMode(PIN_A1, OUTPUT);
  pinMode(PIN_A2, OUTPUT);
  pinMode(PIN_EN, OUTPUT);
  digitalWrite(PIN_EN, HIGH); // decoder disabled at start

  pinMode(PIN_GROUP1, INPUT_PULLUP);
  pinMode(PIN_GROUP2, INPUT_PULLUP);
  pinMode(PIN_GROUP3, INPUT_PULLUP);
  pinMode(PIN_STOP, INPUT_PULLUP);
}

// Confirm a column-group line is still LOW after a short settle (debounce).
static bool confirmed(int pin) {
  delayMicroseconds(60);
  return digitalRead(pin) == LOW;
}

void loop() {
  // 1) Standalone STOP line (active-LOW), independent of the matrix.
  if (digitalRead(PIN_STOP) == LOW) {
    Serial.println(F("-> key: [ STOP ] (direct line)"));
    delay(300);
    return;
  }

  // 2) Scan decoder rows /Y0../Y7.
  for (int row = 0; row < 8; row++) {
    // Disable the decoder before changing the address (avoid ghosting).
    digitalWrite(PIN_EN, HIGH);
    delayMicroseconds(5);
    teachboxSetAddress(row);
    delayMicroseconds(5);

    // Enable the decoder: the selected row is pulled LOW.
    digitalWrite(PIN_EN, LOW);
    delayMicroseconds(50);

    if (digitalRead(PIN_GROUP1) == LOW && confirmed(PIN_GROUP1)) {
      reportKey(row, 1); delay(300); break;
    }
    if (digitalRead(PIN_GROUP2) == LOW && confirmed(PIN_GROUP2)) {
      reportKey(row, 2); delay(300); break;
    }
    if (digitalRead(PIN_GROUP3) == LOW && confirmed(PIN_GROUP3)) {
      reportKey(row, 3); delay(300); break;
    }
  }

  delay(10); // matrix polling pace
}
