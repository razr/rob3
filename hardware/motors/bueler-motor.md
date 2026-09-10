# DC Motor

```
Motor SpecificationsManufacturer: Bühler (Nürnberg, W.-Germany / Raleigh, N.C., USA)
Operating Voltage: 6 VDC (Direct Current)
Model / Part Number: 31.042.303-1
Production Era: The "Made in W.-Germany" print dates this component to before the German reunification (prior to 1990). 
```

This aligns perfectly with the vintage of the original ROB3 educational robot arms.

```
       MOTOR LINE 1 (From Control Unit)
            |

            |     +----+---->|----+     (Parallel Inline Filter)
            |     |   1N4007 Diode|     [Locks reverse back-current]
            +-----+               +-----+

                  |   1R5 Cap     |     
                  +-----[|]-------+     [Shunts high-frequency noise]
                                  |
                                  v
                       (TOP Solder Terminal)
                                  |
                                  +------------+

                                  |            |
                             +---------+       |

                             |  BÜHLER |      ---
                             |  MOTOR  |     /   \   GE 2221 VARISTOR
                             |  COILS  |    | VAR |  [Bridges both lines]
                             +---------+     \   /   [Clamps massive surges]
                                  |           ---
                                  +------------+
                                  |
                       (BOTTOM Solder Terminal)
                                  |
                                  v
       MOTOR LINE 2 (From Control Unit)
```


### How this exact combination protects your ROB3:

#### 1. The Inline Guard (Diode & Capacitor Parallel on Line 1)
Because the **1N4007 Diode** and the **1R5 Capacitor** are wired side-by-side right on the main input line, they act like a specialized filter checkpoint before electricity even enters the top terminal:
* **The 1N4007 Diode** acts as a heavy-duty check valve [1N4007 Specification Sheet]. It forces the incoming 6V driving power to flow forward cleanly into the motor, but instantly slams shut if the motor tries to kick a high-voltage inductive spike backward up that specific line [1N4007 Specification Sheet].
* **The 1R5 (1.5 pF) Capacitor** sits right next to it to handle the radio noise. While the diode handles the raw power, this tiny capacitor catches the ultra-high-frequency "fuzz" caused by the internal motor brushes and dissolves it right at the terminal so it cannot travel back up into the robot's ribbon cables.

#### 2. The Line-to-Line Shield (The Red GE 2221 Varistor)
Because the **Red Varistor** bridges both motor lines directly, it acts as a global safety net for the entire joint:
* When the ROB3 control box tells the arm to slam the brakes or instantly switch directions, a massive voltage differential is created between Line 1 and Line 2.
* The varistor stands watch across that gap. The millisecond that cross-line voltage spikes past a safe threshold, the varistor turns into a temporary short-circuit, letting the giant energy surge loop harmlessly between the two motor wires until it dies down, keeping it completely isolated away from your expensive main controller chips.

Here's a simplified ASCII block diagram.

```ascii
        +----------------------+
        |       8031 MCU       |
        |                      |
        |  Data Bus (8-bit)    |
        |  Address & Control   |
        +----------+-----------+
                   |
                   |            +----------------+
                   +----------->|    8255 PPI     |
                                | (3 ports x 8bit)|
                                +---+--+--+---+---+
                                    |  |  |   |
                    Port A --------+  |  |   +--> Enable Lines (PWM or tied High)
                    Port B -----------+  |
                    Port C -------------+
                                    |
        +--------------------------+---------------------------+
        |                          |                           |
  +-----+----+              +------+-----+             +-------+-----+
  |  L293D #1 |             |  L293D #2  |             |  L293D #3   |
  |  (2 motors)             |  (2 motors)|             |  (2 motors) |
  +----+-----+              +-----+-----+             +------+------+
       |                          |                          |
   Motor 1,2                  Motor 3,4                  Motor 5,6
```

### Why the ROB3 Uses Two Base Motors

Both of these motors sit at the base and work together to control the primary arm linkages through a mechanical configuration known as a **parallel linkage mechanism**. 

The motor on the left does not move Joint 2 directly from that spot. Instead, it is structurally kept down at the base to optimize weight distribution.

#### 1. Axis Control Breakdown
* **The Right Motor (Shoulder Axis):** This drives the lower arm linkage directly, swinging the main red beam up and down relative to the structural base.
* **The Left Motor (Elbow / Forearm Axis):** This controls the upper forearm linkage. Because it sits stationary inside the base, it uses an internal parallel metal bar or belt system to reach up and pivot the elbow joint remotely.

#### 2. Key Engineering Advantages
* **Mass Reduction:** If the second motor were physically mounted up at the elbow joint, the shoulder motor would waste lifting capacity carrying that extra dead weight. Placing both motors at the base keeps the moving parts of the arm lightweight.
* **Parallel Orientation:** This mechanical linkage automatically keeps the end-effector (the robot's gripper) at a consistent angle relative to the floor. When the shoulder tilts the main arm up, the mechanical linkage automatically compensates to keep the forearm leveled.


Notes:

- Intel 8031 connects to 8255 via data/address/control bus.
- Intel 8255 outputs 24 lines over Port A, B, C to control L293Ds.

Each L293D gets:
- 4 inputs from 8255 (2 per motor for direction)
- Enable pins can be controlled from 8255 or tied high
- All 8 motors can be driven simultaneously.

```ascii
         +--------------------+
         |     8031 MCU       |
         +--------------------+
                |||| Data/Address/Control
                VV
         +--------------------+
         |     8255 PPI       |
         |--------------------|
         | Port A: PA0–PA7    | --> L293D #1, #2 inputs
         | Port B: PB0–PB7    | --> L293D #3, #4 inputs
         | Port C: PC0–PC3    | --> EN1/EN2 of each L293D
         |        PC4–PC7     | --> (unused or general I/O)
         +--------------------+

Now to each motor driver:

    L293D #1 (Motor 1 & 2)
    -----------------------
    IN1  <- PA0      (Motor 1 direction A)
    IN2  <- PA1      (Motor 1 direction B)
    IN3  <- PA2      (Motor 2 direction A)
    IN4  <- PA3      (Motor 2 direction B)
    EN1  <- PC0      (PWM or logic high)
    EN2  <- PC0      (can be tied together if same PWM)
    
    L293D #2 (Motor 3 & 4)
    -----------------------
    IN1  <- PA4
    IN2  <- PA5
    IN3  <- PA6
    IN4  <- PA7
    EN1  <- PC1
    EN2  <- PC1

    L293D #3 (Motor 5 & 6)
    -----------------------
    IN1  <- PB0
    IN2  <- PB1
    IN3  <- PB2
    IN4  <- PB3
    EN1  <- PC2
    EN2  <- PC2

    L293D #4 (Motor 7 & 8)
    -----------------------
    IN1  <- PB4
    IN2  <- PB5
    IN3  <- PB6
    IN4  <- PB7
    EN1  <- PC3
    EN2  <- PC3
```

## References

* https://www.buehlermotor.de/produkte-maerkte/industrial/industrial-produkte/motoren.html
