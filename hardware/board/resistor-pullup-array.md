# 10kΩ SIP-10 resistor pullup array

This section documents the board's 10kΩ SIP-10 pullup array used around the input conditioning and logic interface lines.

```text
+5V
│
10 kΩ
│
STOP line ── 100 kΩ ── MM74C04 input
│
STOP button
│
GND
```

```text
               o-- Vcc
DB25 pin 4-----o--|100 kΩ|--pin 5 MM74C04N #1
DB25 pin 20----o--|100 kΩ|--pin 13 MM74C04N #2
DB25 pin 5-----o--|100 kΩ|--pin 1 MM74C04N #1
DB25 pin 19----o--|100 kΩ|--pin 11 MM74C04N #2
DB25 pin 6-----o--|100 kΩ|--pin 5 MM74C04N #2
DB25 pin 18----o--|100 kΩ|--pin 9 MM74C04N #2
DB25 pin 7-----o--|100 kΩ|--pin 3 MM74C04N #2
DB25 pin 17----o--|100 kΩ|--pin 3 MM74C04N #1
DB25 pin 8-----o--|100 kΩ|--pin 1 MM74C04N #2
```

## Notes

- The array provides a defined default state for external lines and prevents floating inputs.
- It is particularly important for digital control pins and switch inputs that may be connected to external equipment or DB25 wiring.
- In the ROB3 system, these pullups help maintain stable logic levels before the signal reaches the inverter and conditioning logic.
