// teachbox_pins.h
//
// Shared pin map for the ROB3 Teachbox bring-up sketches.
//
// The ROB3 Teachbox exposes its 74LS138-scanned 5x5 key matrix and its
// multiplexed indicator LEDs on a DB25 connector. This header captures the
// verified DB25 <-> Arduino UNO wiring used by both test sketches so the two
// stay in sync.
//
// Wiring verified against hardware/teachbox/board.md and led.md:
//   A0 = DB25 pin 23, A1 = DB25 pin 10, A2 = DB25 pin 22  (74LS138 address)
//   /E1,/E2 = DB25 pin 9  (active-LOW strobe/enable)
//   NOP LED = DB25 pin 11 (driven directly, not via the decoder)
//   Column groups: G1 = DB25 pin 5, G2 = DB25 pin 18, G3 = DB25 pin 17
//   STOP = DB25 pin 4 (standalone, active-LOW)
//   VCC = DB25 pin 13, GND = DB25 pin 3
//
// NOTE: all decoder outputs (/Y0../Y7) and the digital inputs are ACTIVE-LOW.

#ifndef TEACHBOX_PINS_H
#define TEACHBOX_PINS_H

// --- 74LS138 address + enable (outputs from the Arduino) ---------------------
#define PIN_A0   2   // -> DB25 pin 23  (address bit 0, LSB)
#define PIN_A1   3   // -> DB25 pin 10  (address bit 1)
#define PIN_A2   4   // -> DB25 pin 22  (address bit 2, MSB)
#define PIN_EN   5   // -> DB25 pin 9   (/E1,/E2 strobe; LOW = enabled)

// --- LED-only line -----------------------------------------------------------
#define PIN_NOP  6   // -> DB25 pin 11  (NOP LED, direct drive)

// --- Keypad column groups (inputs, INPUT_PULLUP; pressed = LOW) ---------------
#define PIN_GROUP1 7 // <- DB25 pin 5   (DEL,8,9,arrows,NOP,ERR,ENT)
#define PIN_GROUP2 8 // <- DB25 pin 18  (7,4,5,6,1,2,3,0)
#define PIN_GROUP3 9 // <- DB25 pin 17  (RUN,IF,GOTO,MARK,TIM,POS,OUT,INS)

// --- Standalone STOP button --------------------------------------------------
#define PIN_STOP 12  // <- DB25 pin 4   (active-LOW)

// Decoder-output (/Y0../Y7) -> indicator LED names, indexed by 3-bit address.
static const char* const LED_NAMES[8] = {
  "ERROR LED", // /Y0  (A2 A1 A0 = 0 0 0)
  "OUT LED",   // /Y1  (0 0 1)
  "POS LED",   // /Y2  (0 1 0)
  "TIM LED",   // /Y3  (0 1 1)
  "MARK LED",  // /Y4  (1 0 0)
  "GOTO LED",  // /Y5  (1 0 1)
  "IF LED",    // /Y6  (1 1 0)
  "RUN LED"    // /Y7  (1 1 1)
};

// Drive the 3 address lines for a given 0..7 decoder output.
inline void teachboxSetAddress(int address) {
  digitalWrite(PIN_A0, (address & 0x01) ? HIGH : LOW);
  digitalWrite(PIN_A1, (address & 0x02) ? HIGH : LOW);
  digitalWrite(PIN_A2, (address & 0x04) ? HIGH : LOW);
}

#endif // TEACHBOX_PINS_H
