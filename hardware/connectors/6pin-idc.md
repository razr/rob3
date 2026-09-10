# IDC 6 pin connector
```
                         Top View
    Row B:  [ Pin 2 ]   [ Pin 4 ]   [ Pin 6 ]  <-- (Even conductors: 2, 4, 6)
    Row A:  [ Pin 1 ]   [ Pin 3 ]   [ Pin 5 ]  <-- (Odd conductors: 1, 3, 5)
                            U
                      (Key slot side)
```

## Connector 1

```txt
                        GND
pin 2 potentiometer   ┌ pin 1 potentiometer
                 5V ┐ | ┌ pin 3 L293D #1
                    ● ● ●
                    2 4 6
                    1 3 5
                    ● ● ●
pin 3 potentiometer ┘ | └ motor 6V -
         pin 25 ADC   |   pin 6 L293D #1
                      └ GND 
```

## Connector 2

```txt
                        GND
                      ┌ pin 1 potentiometer
                      |
                 5V   |   pin 14 L293 #1
pin 2 potentiometer ┐ | ┌ motor 6V + 
                    ● ● ●
                    2 4 6
                    1 3 5
                    ● ● ●
pin 3 potentiometer ┘ | └ motor 6V -
         pin 26 ADC   |   pin 11 L293 #1
                      |
                      └ not connected
                        GND
```

```
                                +--------[ 103 CAPACITOR ]--------+

                                |            (0.01 uF)            |
                                |                                 |
Connector 2 [ Pin 5 ] ----------+----[ JUNCTION A ]               +----[ JUNCTION B ] ---------- Connector 2 [ Pin 6 ]
  (Motor Wire A)                           |                                 |              (Motor Wire B)

                                           |                                 |
                             +-------------+-------------+     +-------------+-------------+

                             |                           |     |                           |
                             v                           v     v                           v
                       [DIODE PAIR 1]              [DIODE PAIR 2] [DIODE PAIR 3]              [DIODE PAIR 4]
                        Anode-Cathode               Anode-Cathode  Anode-Cathode               Anode-Cathode
                         +---|>|---+                 +---|>|---+    +---|>|---+                 +---|>|---+
                         +---|>|---+                 +---|>|---+    +---|>|---+                 +---|>|---+

                             |                           |              |                           |
                             +-------------+-------------+              +-------------+-------------+

                                           |                                          |
                                           v                                          v
                                   Pin 8 of L293 (9V)                            Ground (GND)
```

## How This 1-Capacitor, 4-Diode Team Works

When a DC motor spins, its internal brushes constantly scratch against the rotor, creating a storm of tiny, rapid electrical sparks. These sparks try to travel down both wires (Pin 5 and Pin 6) to glitch your electronics.

Here is how your specific layout defeats them:

- The Single Capacitor Eats the Spark Noise:Because high-frequency spark noise is AC energy, it loves capacitors. The noise jumps into Pin 5, sees the 103 capacitor, passes right through it to Pin 6, and loops back into the motor coils. The capacitor completely traps the radio interference inside the motor wires so it never reaches the rest of the circuit board.
- Diode Pairs 1 & 2 Protect Pin 5:If you stop the motor and Pin 5 tries to spike dangerously high, Diode Pair 1 opens up and dumps it into the 9V line. If Pin 5 drops dangerously below zero, Diode Pair 2 pulls current from Ground to save it.
- Diode Pairs 3 & 4 Protect Pin 6:The exact same thing happens on the other side. If Pin 6 spikes when reversing, Diode Pair 3 redirects the heavy energy to 9V, and Diode Pair 4 protects it against negative spikes by clamping it to Ground.

## Connector 3

```txt
            ┌ GND
       5V ┐ | ┌ 
          ● ● ●
          1 3 5
          2 4 6
          ● ● ●
pin 27    ┘ | └ 
28 pins IC  └ GND 
```

## Connector 4

```txt
            ┌ GND
       5V ┐ | ┌ 
          ● ● ●
          1 3 5
          2 4 6
          ● ● ●
pin 28    ┘ | └ 
28 pins IC  └ GND 
```

## Connector 5

```txt
            ┌ GND
       5V ┐ | ┌ 
          ● ● ●
          1 3 5
          2 4 6
          ● ● ●
pin 1     ┘ | └ 
28 pins IC  └ GND 
```

## Connector 6

```txt
            ┌ GND
       5V ┐ | ┌ 
          ● ● ●
          1 3 5
          2 4 6
          ● ● ●
pin 2     ┘ | └ 
28 pins IC  └ GND 
```

## References

* https://de.rs-online.com/web/p/idc-steckverbinder/6935630
