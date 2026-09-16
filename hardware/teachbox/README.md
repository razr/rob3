# Teachbox

## ℹ️ Introduction

The ROB3i's articulated arm has five axes and a gripper, all of which are powered by DC servo motors. The absolute position of all axes is determined by potentiometric rotary position transducers. The ROB3i's control system thus always knows the current position of all axes, even after a power failure.

The robot can be fitted with either an electrical or a pneumatic gripper, making it possible to perform an extremely wide range of different handling tasks. The integrated control system automatically identifies the gripper type and controls it accordingly.

The robot's integrated control system can be programmed directly via a special keypad unit, the Teachbox, using a simple, easy-to-learn instruction set. The robot is programmed by entering a sequence of instructions to move the arm to the desired positions; these instructions are then stored in memory as a control program.

Programs can be delimited or subdivided with labels, which are "address markers" inserted in the program code. This feature makes it possible to chain individual program units stored in memory. Subprograms identified by labels can also be called in response to the results of polling the status of the system's eight digital inputs, making it possible for you to program the ROB3i to respond intelligently to external events. Eight digital outputs are also included, so that you can program the ROB3i to control its working environment. But that's not all. In addition, you can choose from five different travel speeds, set delays and repeating or endless loops, and much more.

For people who enjoy working with computers, the ROB3i is also fitted with an RS-232 serial interface, making it possible to control and program the robot from any IBM-compatible personal computer. The software package available for this purpose provides the programmer with extensive support: It is menu-operated, and all the control language instructions are permanently displayed on the screen for direct selection. To add an instruction to the control program you are writing, you simply select it with the cursor keys. 

This approach eliminates the possibility of syntax errors. Together with the comprehensive help texts which can be displayed as needed, all these features give the system an optimally simple user interface.

For users who wish to develop their own robot control programs, software interfaces are available in the form of Include files in the languages BASIC, Pascal and C. These Include files contain subroutines for handling serial interface communication with the robot.

When IBM and Microsoft trademarks are mentioned in the text, this is understood to refer exclusively to the products of these companies. ROB is a registered trademark of P + P Elektronik GmbH, Nuremberg, West Germany.

## ⚙️ Technical Specifications

Travel within the working range of each of the ROB3i's six axes is divided into 512 individual steps.

> **Model scope — ROB3i vs ROB3.** The specifications in this section
> (POS 0..511, "512 individual steps", $512^5$ points) are transcribed from the
> **ROB3i** (newer model) documentation. The **original ROB3** firmware in this
> repository works in **8-bit position values (0..255)** — its axis target and
> feedback bytes are single bytes (see
> `../../firmware/src/annotated/ext1_axis_servo.annotated.asm`). So on a ROB3,
> read these 0..511 ranges as the ROB3i's higher-resolution scale, not as the
> range this ROM uses.

| Axis | | Relative End Position | | | Angular Range |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 1 Base rotation | right: | POS 0 | left: | POS 511 | 200 degrees |
| 2 Shoulder | up: | POS 0 | down: | POS 511 | 200 degrees |
| 3 Elbow | up: | POS 0 | down: | POS 511 | 200 degrees |
| 4 Wrist | up: | POS 0 | down: | POS 511 | 200 degrees |
| 5 Wrist roll | right: | POS 0 | left: | POS 511 | 400 degrees |
| only for electric gripper | | | |
| 6 Gripper | open: | POS 0 | closed: | POS 100 | 60 mm |
| only for pneumatic gripper | | | |
| 6 Gripper | open: | POS 0 | closed: | POS 1 | |

All axes can be moved simultaneously. The resolution of the axes makes it possible to access a total of $512^5$ points within the robot's reach. Gripper opening and closing also has a resolution of 100 steps.

In contrast to other robots, which always have a fixed home position, the ROB3i allows you to redefine the start position at the beginning of each program. This makes it possible to use the robot in the most difficult situations imaginable, for example when the home position is obstructed by an immovable object.


| Parameter | Value |
| :--- | :--- |
| Resolution, steps per axis | 512 |
| Repeatability | +/- 0.5 mm |
| Speeds | 5 |
| Maximum payload | 500 g |
| Maximum traversing speed | 750 mm per sec |
| Maximum continuous path speed | 90 mm per sec |
| Drive | DC servo motors |
| Feedback | Absolute value transducers |
| Weight | 13 kg |
| Ambient temperature | 10 - 40 degrees C (50 - 104 F) |
| Interface | RS-232 |
| External power supply | 24V DC at 8A, 9V DC at 3A |
| Digital outputs | 8 |
| Digital inputs | 8 |


Programming options: With IBM-compatible personal computers (PC, XT, AT) and the TBPS software package; as a stand-alone unit together with the Teachbox; or with your own programs, written with the help of the Include files (controlling the robot from the computer via the RS-232 interface).

## 📐 Dimensions and Axis Numbers

## 🎮 The ROB3i Teachbox

The ROB3i Teachbox makes it possible to operate and program the ROB3i without using a computer. It consists of a compact keypad unit with 25 keys, divided into three groups: 
- Numeric keys for entering single or multiple-digit decimal values,
- command keys for entering directly-executable commands,
- and instruction keys for entering control program instructions.

To program the robot, you simply connect the Teachbox to the ROB3i's I/O port; the unit can then be easily disconnected once the program has been started. The female connector on the Teachbox provides all the inputs and outputs necessary for interfacing with the ROB3i's I/O port. When the ROB3i is being operated with the Teachbox connected, only 3 digital outputs (DO 1-3) and 5 digital inputs (DI 1-5) are available. Each instruction key is fitted with an LED which lights up to confirm correct entry. If you make an invalid command or instruction entry, the `ERR` lamp will light up until you clear the incorrect entry by pressing `CLR`. All instructions and commands must be confirmed with the `ENT` key

```ascii
     ┌─────────┬─────────┬─────────┬─────────┬─────────┐
     │    ○    │    ○    │    ○    │    ○    │    o    │
     │  MARK   │  GOTO   │   IF    │    OUT  │   TIM   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │  ↓   +  │
     │   DEL   │    7    │    8    │    9    │  ←      │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │    ○    │
     │   INS   │    4    │    5    │    6    │   POS   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │    ○    │         │         │         │   ↑  -  │
     │   RUN   │    1    │    2    │    3    │   →     │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │    ○    │    ○    │         │
     │   STOP  │    0    │  • NOP  │ ERR CLR │   ENT   │
     └─────────┴─────────┴─────────┴─────────┴─────────┘
```

(Note: ○ indicates a status/feedback LED integrated into that specific key).

* Numerical Keys: Used for entering the axis designation numbers and position values.
* Command Keys:
  (`RUN`, `STOP`, `INS`, `DEL`, `POS`, `OUT`) : Commands are executed immediately.
* Instruction Keys:
  (`POS`, `TIM`, `OUT`, `MARK`, `IF`, `GOTO`, `NOP`) : When you enter instructions, they are stored in the robot's memory in the sequence in which you enter them. They are only executed in `RUN` or `STEP` mode.

## 🛠️ Operating Modes
The robot’s integrated control system has six different operating modes:

* `INPUT` Mode: For creating control programs by entering a sequence of instructions. This is the default mode which is activated whenever the system is powered up.
* `POSITION` Mode: This mode is selected by pressing one of the numerical keys `1`-`6`, which also selects the corresponding axis. You can then move the axis forwards or backwards with the `+` and `-` keys. In this mode, you can also position the axes directly with the sequence `POS (axis a) . (position n) ENT`. Pressing `CLR` returns you to the `INPUT` mode.
* `RUN` Mode: When you enter `RUN (label m) ENT`, ROB3i starts executing the sequence of instructions in its memory starting at label m.
* `BREAK` Mode: When the robot is in `RUN` mode, all keys except the `STOP` key are disabled. Pressing `STOP CLR` activates the `BREAK` mode. You can switch back to `RUN` mode with `RUN ENT` ( = CONTINUE). Pressing `STOP ENT` allows you to select any of the other modes.
* `STEP` Mode: Entering `RUN . (label m) ENT` switches on the `STEP` mode, starting at label `m` (provided that label `m` exists, of course). You can then run through the program one step at a time by pressing the `+` key. Pressing `CLR` exits the STEP mode.
* `DISPLAY` Mode: Entering `STOP . (label m) ENT` switches the system to the `DISPLAY` mode, starting at label `m`. When you press the `+` key, the next instruction stored in the sequence in memory is displayed (the corresponding LED on the Teachbox lights up), but the instruction is not executed on the ROB3i. Pressing `CLR` exits the `DISPLAY` mode.

## Summary of all Instructions and Commands

Instructions:

```
MARK m ENT . .       Set label m . . . . . . . . . . . . . . . . . . . . .  m = 0..118
POS ENT . . . . .    Store current position
TIM t ENT . . . .    Set delay period t (x 100ms) . . . . . . . . . . . . . t = 1..65535
GOTO m ENT . .       Go to label m . . . . . . . . . . . . . . . . . . . .  (endless loop)
GOTO m . n ENT .     Go to label m, n times . . . . . . . . . . . . . . . . n = 0..255
IF i ENT . . . . .   Wait until input i = low
IF i . m ENT . . . . If input i = low go to label m
. . . . . . . . . .  else continue with next instruction
OUT k +/- ENT . .    Set/clear digital output k . . . . . . . . . . . . . . k = 1..8
. ENT . . . . . . .  NOP instruction
STOP 0 ENT . . . .   Program start
INS . ENT . . . . .   Program end
DEL . ENT . . . . .   Halt instruction, used to separate two consecutive programs in memory
```

Commands:

```
a +/- ENT . . . . Move axis a in POSITION mode
POS a . n ENT . . Move axis a to position n . . . . . . . . . . . a = 1..6
OUT . k +/- ENT . Set/clear digital output k directly
RUN m ENT . . . . Run from label m
RUN . m ENT . . . Activate STEP mode starting at label m
RUN ENT . . . . . Continue (BREAK mode)
RUN . ENT . . . . Continue (STEP mode)
STOP CLR . . . .  Break, stop program execution, continue with RUN ENT
STOP ENT . . . .  Stop, switch to INPUT mode
STOP . ENT . . .  Activate DISPLAY mode
STOP .m ENT . . . Activate DISPLAY mode starting at label m
INS ENT . . . . . Insert instruction
DEL ENT . . . . . Delete instruction
CLR . . . . . . . Change mode, clear on error
```

Special features of the pneumatic gripper:

- `6 +/- ENT`
Pressing the `PLUS` or `MINUS` key once moves the gripper to the opposite end position.

- `POS 6 . n ENT`
An even value for `n` opens the gripper, an odd value closes it.

## Hardware Installation
The robot can be fitted with either an electrical or a pneumatic gripper, making it possible to perform an extremely wide range of different handling tasks. The integrated control system automatically identifies the gripper type and controls it accordingly.

Installing the electrical gripper is a simple mechanical operation. Proceed as follows:

* Snap the electrical gripper onto the gripper mounting flange in the position you wish to define as the center position.
* Insert the gripper plug into the matching socket and screw it into place. Arrange the spiral cable so that it will not obstruct the gripper.
* The ROB 3i is then ready for operation with the electrical gripper.

To install the pneumatic gripper, proceed as follows:

* Snap the pneumatic gripper onto the gripper mounting flange in the position you wish to define as the center position.
* Coil the black and blue hoses loosely around the gripper's rotary axis, then connect them to the gripper. Connect the blue hose to the connection which is closest to the gripper fingers.
* Insert the plug attached to the red and black cable into the matching socket and screw it into place.
* Mount the pressure reducing valve on the base of the robot, using two screws. Connect the blue compressed air hose from the base of the robot to the pressure reducing valve.
* Snap the FESTO PU3 compressed air hose onto the FESTO CN-M5-PK3 connector nipple (max. operating pressure 6 bar / 6000 hPa). The pressure reducing valve is set for a gripper operating pressure of 5 bar / 5000 hPa.
* The ROB3i is then ready for operation with the pneumatic gripper.

Hardware requirements:

- The ROB3i
- The power supply unit
- The Teachbox
- The RS-232 shorting connector

Connect the ROB3i to the power supply unit with the two power leads. Plug the Teachbox’s 25-pin male connector into the I/O port and the 9-pin shorting connector into the RS-232 port. Turn the power switch to ON, and press the RESET key on the ROB3i. Now you can enter a program or move the ROB3i’s arm directly with the appropriate instructions.

The ROB3i’s program memory is nonvolatile, and is powered by a long-life lithium battery; your programs will remain stored in the robot’s memory for around 10 years, even when the mains power is switched off.

## Digital Inputs and Outputs, EMERGENCY OFF Function

- Digital Inputs (TTL)

```
DI1: Pin 8                              +5V
DI2: Pin 20                              |
DI3: Pin 7                             [10KΩ Pull-up]
DI4: Pin 19                              |
DI5: Pin 6                         o-----o------[100K]------>| 1 |>o------ Output
DI6: Pin 18                        DI/                       4069
DI7: Pin 5                         o     
DI8: Pin 17                        |     
                                  GND     
```

All the digital inputs are active `LOW`


```
DO1: Pin 25                  +----------+
DO2: Pin 12                  |          |
DO3: Pin 24              ----| 74LS244  |+------------------o DO/
DO4: Pin 11                  |  Buffer  |                   o
DO5: Pin 23                  +----------+                   GND
DO6: Pin 10
DO7: Pin 22
DO8: Pin 9
```

All the digital outputs are active `LOW`.

### EMERGENCY OFF for the ROB3i

- `DI10: Pin 4`

The `EMERGENCY OFF` input is active `LOW`

The emergency off function is realized with an NOC across pins 4 and 1 of the robot’s I/O port. Activation of the function switches off the ROB3i’s motors. After eliminating the problem, you must execute a `RESET` on the ROB3i unit, then you can restart the control program.

### Power Supply

- Gnd : Pin 1
- 5V Pins 2/13    I <= 50mA

The power supply unit is only suitable for the connection of optocouplers. Any external driver stages must be provided with their own power supply. Please note that the ground lines should NOT be connected when optocouplers are being used.

## Exercises with the Teachbox

Connect the ROB3i and switch it on as described in Section 8, Hardware Installation. Before you begin the exercises, we suggest that you first move the robot's arm to the following home position:

```text
Axis . . . . . . . . . Position
 1 . . . . . . . . . . 255
 2 . . . . . . . . . . 255
 3 . . . . . . . . . . 255
 4 . . . . . . . . . . 255
 5 . . . . . . . . . . 255
 6 . . . . . . . . . . 0 (electric or pneumatic gripper is open)
```

To position the first axis, enter the following key sequence: POS 1 (decimal point). ENT. When you press ENT, axis 1 of the ROB3i will immediately move into position 255, which is the central position. Repeat the procedure with the appropriate values for the remaining five axes.
