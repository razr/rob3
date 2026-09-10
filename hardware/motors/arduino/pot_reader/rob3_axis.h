// rob3_axis.h
//
// Shared pin map + per-axis calibration for the ROB3 motor/feedback bring-up.
//
// Each ROB3 axis is a DC servo motor driven by an L293 H-bridge, with an
// absolute 5 kOhm potentiometer for position feedback. These sketches drive
// ONE axis at a time from an Arduino UNO:
//
//   L293 IN1  <- Arduino D2   (direction A)
//   L293 IN2  <- Arduino D3   (direction B)
//   L293 EN   <- +5V          (enable tied high; speed not PWM here)
//   L293 OUT1/OUT2 -> motor terminals (ROB3 connector pins 6 / 5)
//   Pot wiper -> Arduino A0   (ROB3 connector pin 1); pot +5V/GND = pins 2/4
//
// Calibration values are the measured raw 10-bit ADC readings from
// hardware/motors/test.md. The Arduino's 10-bit ADC (0..1023) maps to the
// ROB3 native 8-bit scale (0..255) via map(raw,0,1023,0,255).

#ifndef ROB3_AXIS_H
#define ROB3_AXIS_H

// --- Pin map (single-axis rig) ----------------------------------------------
#define PIN_MOTOR_IN1  2   // -> L293 IN1 (direction A)
#define PIN_MOTOR_IN2  3   // -> L293 IN2 (direction B)
#define PIN_POT        A0  // <- potentiometer wiper (ROB3 connector pin 1)

// --- Per-axis potentiometer calibration (raw 10-bit ADC), from test.md ------
// Not every axis has all three points characterised; use what test.md records.
struct AxisCal {
  const char* name;
  int adc_min;   // raw ADC at one mechanical limit
  int adc_mid;   // raw ADC at the reference/center position
  int adc_max;   // raw ADC at the other mechanical limit
};

// Index 0..5 == ROB3 axes 1..6.
static const AxisCal AXIS_CAL[6] = {
  // name,             adc_min, adc_mid, adc_max
  { "1 Base",           185,     482,     779 },  // +90 / 0 / -90 deg
  { "2 Shoulder",       513,     620,     756 },  // +70 / 0 / -44 deg
  { "3 Elbow",          271,     271,     639 },  //  0 (ref) / .. / -110 deg
  { "4 Wrist",            0,     512,    1023 },  // uncalibrated (full range)
  { "5 Wrist roll",     162,     506,     862 },  // +90 / 0 / -90 (approx)
  { "6 Gripper",        206,     486,     765 },  // closed .. open (206/765)
};

// Map an Arduino 10-bit ADC reading to the ROB3 native 8-bit scale.
inline int rob3Scale(int raw10) {
  return map(raw10, 0, 1023, 0, 255);
}

#endif // ROB3_AXIS_H
