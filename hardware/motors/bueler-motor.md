# Bühler DC Motor

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
* **The 1R5 Capacitor** sits right next to it to handle the radio noise. (The `1R5` marking nominally reads 1.5; the unit is uncertain from the marking alone — for brush noise suppression a value in the nF range is typical rather than pF. **[value tentative — verify on the physical part]**) While the diode handles the raw power, this capacitor catches the ultra-high-frequency "fuzz" caused by the internal motor brushes and dissolves it right at the terminal so it cannot travel back up into the robot's ribbon cables.

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
                                    |  |      |
                    Port A --------+  |      +--> Port C -> L293 #3 direction
                    (L293 #1,#2)      |
                    Port B -----------+--> DB25 digital I/O (via 74LS244), NOT motors
                                    |
        +--------------------------+---------------------------+
        |                          |                           |
  +-----+----+              +------+-----+             +-------+-----+
  |  L293 #1  |             |  L293 #2   |             |  L293 #3    |
  |  (2 motors)             |  (2 motors)|             |  (2 motors) |
  |  EN = VCC |             |  EN = VCC  |             |  EN = VCC   |
  +----+-----+              +-----+-----+             +------+------+
       |                          |                          |
   Motor 1,2                  Motor 3,4                  Motor 5,6

  (A 4th L293 footprint exists on the PCB but is NOT soldered / unpopulated.)
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
- Intel 8255 drives the L293 direction inputs over Port A and Port C.

On the ROB3 board there are **three populated L293s** (6 motors). A fourth
L293 footprint (`#4`) exists on the PCB but is **not soldered** — it is an
unpopulated position, so motors 7 & 8 do not exist. The verified 8255 → L293
mapping (see `../board/8255.md` and `../board/L293.md`) is:

- **Port A (PA0–PA7)** → direction inputs of **L293 #1 and #2** (motors 1–4).
- **Port C (PC4–PC7)** → direction inputs of **L293 #3** (motors 5–6).
- **Enable pins (1,2EN / 3,4EN)** are **tied to VCC (+5V)** on each populated
  L293 — they are not PWM-driven; speed is done in firmware by pulse timing.
- **Port B** does **not** drive motors — it is the general digital I/O port,
  buffered to the DB25 connector through the 74LS244 (see `../connectors/db25.md`).

```ascii
    L293 #1 (Motors 1 & 2)  <- 8255 Port A (PA4/PA5/PA6/PA7), EN = VCC
    L293 #2 (Motors 3 & 4)  <- 8255 Port A (PA0/PA1/PA2/PA3), EN = VCC
    L293 #3 (Motors 5 & 6)  <- 8255 Port C (PC4/PC5/PC6/PC7), EN = VCC
    L293 #4 (NOT POPULATED) -- footprint present on PCB, not soldered
```

> For the exact 8255-pin ↔ L293-pin wiring per motor, see the reciprocal tables
> in `../board/L293.md` and `../board/8255.md`. The mapping above is by port; the
> board docs give the pin-level detail.

## References

* https://www.buehlermotor.de/produkte-maerkte/industrial/industrial-produkte/motoren.html
