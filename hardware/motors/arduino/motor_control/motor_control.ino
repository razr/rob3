// motor_control.ino
//
// ROB3 axis 1 (Base) — keyboard-driven motor control with a software travel
// limit ("watchdog") and an auto-center routine, using potentiometer feedback.
//
// This is a bring-up / safety demo: it drives ONE axis via an L293 H-bridge
// and refuses to move past soft +/-80 deg limits, mirroring how the real
// firmware servos an axis toward a target using the ADC feedback.
//
// SERIAL COMMANDS (9600 baud):
//   'F'/'f' -> drive FORWARD (toward +90 / lower ADC)
//   'B'/'b' -> drive BACKWARD (toward -90 / higher ADC)
//   '0'     -> auto-center to 0 deg
//   any other key -> EMERGENCY STOP
//
// Target: Arduino UNO R3. Wiring: see rob3_axis.h and ../README.md.
// Calibration below matches AXIS_CAL[0] (axis 1) in rob3_axis.h / test.md.

#include "rob3_axis.h"

// Axis-1 calibration (raw 10-bit ADC). +90 deg is LOW ADC, -90 deg is HIGH ADC.
static const int ADC_AT_PLUS_90  = 185;
static const int ADC_AT_MINUS_90 = 779;
static const int ADC_CENTER_0    = 482;

// Soft travel limits (+/-80 deg) and center deadband.
static const int HARD_LIMIT_POS_80 = 218; // near +80 deg (low ADC side)
static const int HARD_LIMIT_NEG_80 = 746; // near -80 deg (high ADC side)
static const int ZERO_THRESHOLD    = 5;   // deadband around center

enum MotorState { MOTOR_STOP, MOTOR_FORWARD, MOTOR_BACKWARD };
static MotorState currentDirection = MOTOR_STOP;
static bool isAutoCentering = false;

static float mapFloat(float x, float inMin, float inMax, float outMin, float outMax) {
  return (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin;
}

static void moveMotor(bool forward) {
  digitalWrite(PIN_MOTOR_IN1, forward ? HIGH : LOW);
  digitalWrite(PIN_MOTOR_IN2, forward ? LOW  : HIGH);
  currentDirection = forward ? MOTOR_FORWARD : MOTOR_BACKWARD;
}

static void stopMotor() {
  digitalWrite(PIN_MOTOR_IN1, LOW);
  digitalWrite(PIN_MOTOR_IN2, LOW);
  currentDirection = MOTOR_STOP;
}

void setup() {
  pinMode(PIN_MOTOR_IN1, OUTPUT);
  pinMode(PIN_MOTOR_IN2, OUTPUT);
  stopMotor();

  Serial.begin(9600);
  Serial.println();
  Serial.println(F("============================================="));
  Serial.println(F("   ROB3 AXIS 1: keyboard control + watchdog"));
  Serial.println(F("============================================="));
  Serial.println(F(" [F]=Forward  [B]=Backward  [0]=Auto-center"));
  Serial.println(F(" any other key = EMERGENCY STOP"));
  Serial.println(F("============================================="));
}

void loop() {
  int adc = analogRead(PIN_POT);
  float angle = mapFloat(adc, ADC_AT_PLUS_90, ADC_AT_MINUS_90, 90.0, -90.0);

  // --- 1) keyboard input --------------------------------------------------
  if (Serial.available() > 0) {
    char c = Serial.read();
    if (c != '\n' && c != '\r') {
      if (c == '0') {
        Serial.println(F("\n[AUTO] centering to 0 deg..."));
        isAutoCentering = true;
      } else if (c == 'f' || c == 'F') {
        isAutoCentering = false;
        if (adc < HARD_LIMIT_POS_80) Serial.println(F("\n[BLOCKED] past +80 deg limit"));
        else { Serial.println(F("\n[CMD] FORWARD")); moveMotor(true); }
      } else if (c == 'b' || c == 'B') {
        isAutoCentering = false;
        if (adc > HARD_LIMIT_NEG_80) Serial.println(F("\n[BLOCKED] past -80 deg limit"));
        else { Serial.println(F("\n[CMD] BACKWARD")); moveMotor(false); }
      } else {
        Serial.println(F("\n[CMD] EMERGENCY STOP"));
        isAutoCentering = false;
        stopMotor();
      }
    }
  }

  // --- 2) auto-center controller ------------------------------------------
  if (isAutoCentering) {
    int err = adc - ADC_CENTER_0;
    if (abs(err) <= ZERO_THRESHOLD) {
      stopMotor();
      isAutoCentering = false;
      Serial.println(F("\n[AUTO] centered at 0 deg."));
    } else if (err > 0) {
      // high ADC = negative side -> move FORWARD to lower ADC
      if (currentDirection != MOTOR_FORWARD) moveMotor(true);
    } else {
      // low ADC = positive side -> move BACKWARD to raise ADC
      if (currentDirection != MOTOR_BACKWARD) moveMotor(false);
    }
  }

  // --- 3) directional travel-limit watchdog -------------------------------
  if (adc > HARD_LIMIT_NEG_80 && currentDirection != MOTOR_FORWARD) {
    stopMotor();
    isAutoCentering = false;
    static unsigned long last = 0;
    if (millis() - last > 2000) {
      Serial.print(F("\n[WATCHDOG] past -80 deg (ADC "));
      Serial.print(adc); Serial.println(F("). Press F or 0 to recover."));
      last = millis();
    }
  } else if (adc < HARD_LIMIT_POS_80 && currentDirection != MOTOR_BACKWARD) {
    stopMotor();
    isAutoCentering = false;
    static unsigned long last = 0;
    if (millis() - last > 2000) {
      Serial.print(F("\n[WATCHDOG] past +80 deg (ADC "));
      Serial.print(adc); Serial.println(F("). Press B or 0 to recover."));
      last = millis();
    }
  }

  // --- 4) telemetry -------------------------------------------------------
  static unsigned long lastPrint = 0;
  if (millis() - lastPrint > 400) {
    Serial.print(F("ADC: ")); Serial.print(adc);
    Serial.print(F("\t| angle: ")); Serial.print(angle, 1);
    Serial.print(F(" deg\t| "));
    if (isAutoCentering) Serial.print(F("AUTO ("));
    else Serial.print(F("MANUAL ("));
    if (currentDirection == MOTOR_FORWARD) Serial.println(F("FORWARD)"));
    else if (currentDirection == MOTOR_BACKWARD) Serial.println(F("BACKWARD)"));
    else Serial.println(F("STOPPED)"));
    lastPrint = millis();
  }
}
