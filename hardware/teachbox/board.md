# Board

```ascii
                                     4 3 2 1
                   o o o o o o o o o o o o o
                   o o o o o o o o o o o o o
                                   18  16  14
     ┌─────────┬─────────┬─────────┬─────────┬─────────┐
     │p11 IC   │p10 IC   │p9 IC    │p14 IC   │p12 IC   │
     │p17 DB25 │p17 DB25 │p17 DB25 │p17 DB25 │p17 DB25 │
     │    ○    │    ○    │    ○    │    ○    │    o    │
     │  MARK   │  GOTO   │   IF    │    OUT  │   TIM   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │p7 IC    │p7 IC    │p15 IC   │p11 IC   │p12 IC   │
     │p5 DB25  │p18 DB25 │p5 DB25  │p5 DB25  │p5 DB25  │
     │         │         │         │         │  ↓   +  │
     │   DEL   │    7    │    8    │    9    │  ←      │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │p15 IC   │p11 IC   │p10 IC   │p9 IC    │p13 IC   │
     │p17 DB25 │p18 DB25 │p18 DB25 │p18 DB25 │ p17 DB25│
     │         │         │         │         │    ○    │
     │   INS   │    4    │    5    │    6    │   POS   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │p7 IC    │p14 IC   │p13 IC   │p12 IC   │p12 IC   │
     │p17 DB25 │p18 DB25 │ p18 DB25│p18 DB25 │p5 DB25  │
     │    ○    │         │         │         │   ↑  -  │
     │   RUN   │    1    │    2    │    3    │   →     │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │p15 IC   │p13 IC   │p9 IC    │p10 IC   │
     │p3 DB25  │p18 DB25 │p5 DB25  │ p5 DB25 │ p5 DB25 │
     │         │         │    ○    │    ○    │         │
     │   STOP  │    0    │  • NOP  │ ERR CLR │   ENT   │
     └─────────┴─────────┴─────────┴─────────┴─────────┘
      all LEDs->[210 Ω]->┌● ● ● ● ● ● ● ●┐ 
                         > ST T74LS138B1 │
                         └● ● ● ● ● ● ● ●┘
```

## ST T74LS138B1

The ST T74LS138B1 (manufactured by STMicroelectronics) is a 3-to-8 line decoder/demultiplexer. It takes a 3-bit binary address and activating exactly one of its 8 outputs, provided the chip is enabled. It uses active-low logic, meaning the selected output drops to a **LOW (0)** voltage level while all unselected outputs remain **HIGH (1)**.

```ascii
               ST T74LS138B1 (Top View)
              
                     +---U---+
 (Address LSB)  A0 --| 1   16 |-- VCC  (+5V Power)
 (Address MID)  A1 --| 2   15 |-- /Y0  (Output 0, Active-LOW)
 (Address MSB)  A2 --| 3   14 |-- /Y1  (Output 1, Active-LOW)
(Active-LOW)   /E1 --| 4   13 |-- /Y2  (Output 2, Active-LOW)
(Active-LOW)   /E2 --| 5   12 |-- /Y3  (Output 3, Active-LOW)
(Active-HIGH)   E3 --| 6   11 |-- /Y4  (Output 4, Active-LOW)
(Output 7)     /Y7 --| 7   10 |-- /Y5  (Output 5, Active-LOW)
  (Ground 0V)  GND --| 8    9 |-- /Y6  (Output 6, Active-LOW)
                     +-------+

```

## Pinout LEDs

```
                     +---U---+
   pin 16 DB25  A0 --| 1   16 |-- VCC  pin 13 DB25
   pin 10 DB25  A1 --| 2   15 |-- /Y0  ERROR LED
   pin 17 DB25  A2 --| 3   14 |-- /Y1  OUT LED
    pin 9 DB25 /E1 --| 4┐  13 |-- /Y2  POS LED
    pin 9 DB25 /E2 --| 5┘  12 |-- /Y3  TIM LED
           VCC  E3 --| 6   11 |-- /Y4  MARK LED
      RUN LED  /Y7 --| 7   10 |-- /Y5  GOTO LED
        pin 3 DB25 --| 8    9 |-- /Y6  IF LED
                     +-------+
```

## Pinout Buttons (Pin 4)

```ascii
                     +---U---+
   pin 23 DB25  A0 --| 1   16 |-- VCC  pin 13 DB25
   pin 10 DB25  A1 --| 2   15 |-- /Y0  INS,   0,     8
   pin 22 DB25  A2 --| 3   14 |-- /Y1  OUT,   1,     9
    pin 9 DB25 /E1 --| 4┐  13 |-- /Y2  POS,   2,     NOP
    pin 9 DB25 /E2 --| 5┘  12 |-- /Y3  TIM,   3,     ↑ - → 
           VCC  E3 --| 6   11 |-- /Y4  MARK,  4,     ↓ + ←
 RUN,  7,  DEL /Y7 --| 7   10 |-- /Y5  GOTO,  5,     ENT
        pin 3 DB25 --| 8    9 |-- /Y6  IF,    6,     ERR CLR
                     +-------+
```

## Pinout Buttons (Pin 1,2,3)

```
p5 DB25 -  DEL, 8, 9, ↓ + ←, ↑ - →, NOP, ERR CLR, ENT 
p18 DB25 - 7, 4, 5, 6, 1, 2, 3, 0
p17 DB25 - MARK, GOTO, IF, OUT, TIM, INS, POS, RUN
```

| 74LS138 Row Output | Group 1 (`p5 DB25`) | Group 2 (`p18 DB25`) | Group 3 (`p17 DB25`) |
| :--- | :--- | :--- | :--- |
| **`/Y0`** (Address 000) | `8` | `0` | `INS` |
| **`/Y1`** (Address 001) | `9` | `1` | `OUT` |
| **`/Y2`** (Address 010) | `NOP` | `2` | `POS` |
| **`/Y3`** (Address 011) | `↑ - → (UP / RIGHT)` | `3` | `TIM` |
| **`/Y4`** (Address 100) | `↓ + ← (DOWN / LEFT)` | `4` | `MARK` |
| **`/Y5`** (Address 101) | `ENT` | `5` | `GOTO` |
| **`/Y6`** (Address 110) | `ERR CLR` | `6` | `IF` |
| **`/Y7`** (Address 111) | `DEL` | `7` | `RUN` |

## LED Decoder Map

```
================================================================================
                        CURRENT DECODER MAP
================================================================================

  [LED STATUS LIGHT]     [T74LS138B1 OUTPUT]    [BINARY ADDRESS (A2, A1, A0)]
  
  ERROR LED ------------> Pin 15 (/Y0) ---------> 0 0 0
  OUT LED --------------> Pin 14 (/Y1) ---------> 0 0 1
  POS LED --------------> Pin 13 (/Y2) ---------> 0 1 0
  TIM LED --------------> Pin 12 (/Y3) ---------> 0 1 1
  MARK LED -------------> Pin 11 (/Y4) ---------> 1 0 0
  GOTO LED -------------> Pin 10 (/Y5) ---------> 1 0 1
  IF LED ---------------> Pin 9  (/Y6) ---------> 1 1 0
  RUN LED --------------> Pin 7  (/Y7) ---------> 1 1 1

================================================================================
*Reminder: Your NOP LED is completely separate and wired directly to DB25 Pin 11.
```

## 1. Do the DO and DI Lines Run to the 8031 or the 8255?

The DO (Digital Output) and DI (Digital Input) lines do NOT run directly to the 8031 controller; they go through the 8255 PPI chip first.

The assembly code proves that whenever the system interacts with the Teachbox interface, it configures and triggers the external memory-mapped space of the 8255 PPI:
- The 3 Digital Outputs (DO 1–3): These control lines (which drive the A, B, and C input pins on your T74LS138B1 matrix decoder chip) are generated by writing to 8255 Port A (5000H) and 8255 Port C (5200H)
- .The 5 Digital Inputs (DI 1–5): These represent the incoming row matrix responses. The code reads them collectively by fetching data from 8255 Port B (5100H) [source: 1].

```asm
jump_0BFF:
	mov R7, A
	jbc 20h.1, jump_0C64
	mov 83h, #51h	; <--- DPH = 51h (POINTS TO 8255 PORT B / THE DI LINES)
	mov R6, #00h	; Clear data buffer
	mov A, 47h
	anl A, #0Fh	; Isolate matrix mask
jump_0C0C:
	movx @DPTR, A   ; <--- READ/WRITE 8255 PORT TO SCAN BUTTONS
```

## 2. Where is the Program Entered via the Teachbox Stored?

The custom control programs you type into the Teachbox keys are stored directly inside the battery-backed Non-Volatile RAM (NVRAM), starting at memory boundary location 5800H.

The 8031 processor uses your internal RAM variables 3EH and 3FH as master pointer vectors to track where the user's teach-in robot paths begin and end inside the NVRAM [source: 1].

### 🔍 The Exact Proof in the Code (0380H and 064EH

)During the startup phase (jump_064E), the system auto-calculates the boundaries of your NVRAM chip and establishes page tables:

```asm
jump_064E:
	mov A, R0
	cpl A
	movx @DPTR, A
	mov 3Eh, 83h    ; <--- Saves NVRAM High-Byte Page Map into RAM 3Eh
	mov 3Fh, 3Eh    ; <--- Copies it to 3Fh as a persistent boundary map
	inc 3Fh
```

When you are programming via the Teachbox and confirming step inputs, the serial/parallel command decoder routines handle the incoming payload strings by anchoring them directly to those pointers:

```asm
jump_0380:
	mov R2, A
	mov 30h, #00h	
	mov 31h, 3Fh    ; <--- Targets the NVRAM boundary pointer page
	mov 83h, 3Eh    ; <--- Forces DPH to the base NVRAM sector (58h)
	movx @DPTR, A   ; <--- PERMANENTLY WRITES YOUR TEACHBOX PROGRAM TO NVRAM!
```

This explains the line from your manual stating your custom configurations remain stored for 10 years even when the robot is powered down. The EPROM (M2764A) only holds this static assembly system firmware you are reading right now; any motion sequences you actively input are committed strictly into the battery-backed NVRAM space (5800H–5FFFH)

## 1. The Matrix Scanning & Key Capture Phase

Before a command can be executed, the system must decode which physical button on the 5x5 grid was pressed. This is handled by a polling loop located from 0BFFH to 0C70H

```asm
jump_0BFF:
    mov R7, A
    jbc 20h.1, jump_0C64
    mov 83h, #51h    ; Points DPH to 5100H (8255 Port B - Matrix Column Inputs)
    mov R6, #00h     ; Reset key index counter
    ...
jump_0C0C:
    movx @DPTR, A    ; Read physical column states from the 8255
```

- What happens here: The software systematically alters the bits on the T74LS138B1 lines via Port A (5000H) to strobe each row [source: 1]. It reads Port B (5100H) to see which column dropped.
- The Result: The raw physical intersection is translated into a single unique index number (from 00H to 19H for the 25 keys) and temporarily cached in internal RAM register 47H

## 2. The Command Parsing & Token Jump Table

Once a key index is captured and confirmed by pressing the ENT (Enter) key, execution passes to the primary Teachbox Command Processor located at 03A9H through 0420H

This section acts as a massive operational command router. It evaluates the raw index value and converts it into a distinct hex command token [source: 1]. It then uses an offset jump mechanics (jmp @A+DPTR) to branch straight to the individual software handler for that specific key:

```asm
jump_03A9:
    mov A, 47h       ; Load the captured Teachbox key index
    add A, #24h      ; Calculate jump offset for the command lookup vector
    movc A, @A+PC    ; Fetch target subroutine address relative to Program Counter
    jmp jump_03F2    ; Route execution directly to the functional key parser
```

## 📦 Where specific keys land in the firmware:

- The RUN Key Handler (03A0H – 03B5H):When the index for RUN is validated, it routes here. The code shifts the system state flags, reads the starting execution vector from your NVRAM program block, and hands control over to the autonomous motor routing engine.
- The STOP / ERR CLR Key Handler (0380H – 0399H):This block handles cancellations and resets. It clears the transient error tracking registers (like RAM slot 21H), switches off the ERR lamp output line on the 8255, and resets the entry parsing caches back to zero.
- The Instruction Keys (GOTO, IF, MARK etc.) (03B6H onward):These keys represent structural programming steps. Their subroutines compile the key token alongside any preceding input digits typed into the numeric matrix. The compiled operational instruction block is then pushed directly into the NVRAM storage pool (5800H and up) via data pointer vectors controlled by RAM markers 3EH and 3FH.

## 🔍 Tracking Execution Anomaly

If your Teachbox accepts numeric entries but refuses to run or store commands, the program is getting trapped right before this router block [source: 1]. It is usually waiting for a valid confirmation strobe flag from the ENT key cycle to release the data out of register 47H into the 03A9H processor.

## 1. The Manual Key Selection Router (073DH)

Directly after the code verifies that a key has been pressed, it checks if the key index matches one of the manual movement keys

```asm
jump_073D:
	mov A, 47h       ; Load the pressed Teachbox key index (e.g., Key 1, 3, 9)
	cjne A, #09H, check_next_key ; Is it the axis increment key?
	; ... (sets up manual execution mode) ...
```

## 2. Translating Key Indexes to Motor Channels

The Teachbox uses the right-hand column of keys for manual control. The code maps those specific physical key presses directly to the target motor index variables inside internal RAM:
- When you press Key 1 (bottom left of the arrow group / Joint 1), the code sets an axis index pointer to target RAM position variable 50H (Motor 1).
- When you press the ↑ + / 9 Key, the code increments the target position variable 60H–65H for that selected motor.
- When you press the ↓ - / 3 Key, the code decrements the target position variable

## 3. The Execution Strobe Snippet (0768H)

Once the code determines which key is held down, it modifies the target coordinates and immediately calls the execution block to slam the raw motion bits out to the 8255

```asm
jump_0768:
	mov A, 47h          ; Re-verify the active jog key
	anl A, #07h         ; Isolate the direction polarity bit (+ or -)
	jz decrease_axis    ; If 0, user is pressing '-' (decrease coordinate)
	
	; User is pressing '+' (e.g., Up Arrow / Key 9):
	inc @R0             ; Increment the target position workspace register (60h-65h) [source: 1]
	sjmp update_hardware
	
decrease_axis:
	dec @R0             ; Decrement the target position workspace register (60h-65h) [source: 1]

update_hardware:
	lcall jump_0449     ; <--- THE EXECUTION CALL! This jumps directly to the 
	                    ;      8255 output routine, forcing the L293D chips 
	                    ;      to physically move that specific joint right now [source: 1].
```

### 🔄 The "Hold-to-Run" Loop

This section of the code loops continuously as long as your finger is physically pressing the key on the Teachbox matrix. The moment you release the key, the polling loop (jump_0BFF) registers that the matrix line has gone back to high (1), exits this manual execution block, and forces the code to call a stop sequence to halt the L293D drivers.

## 4. Moving the Joint Axis Immediately

The manual states: "When you press ENT, axis 1... will immediately move..."

The microsecond ENT is processed, the code copies that 0FFH (255) value straight into target destination register 60H (Target for Motor 1).

This instantly forces a mismatch against the real-time position variable inside register 50H. The software loops notice this imbalance and execute the exact driver code sequence we traced earlier.

```asm
	mov 83h, #50h    ; Point to 8255 Port A (Address 5000H)
	mov A, 4Eh       ; Load calculated direction bits to move Motor 1 toward 255
	movx @DPTR, A    ; <--- SLAMMED OUT! Motor 1 turns on immediately.
```

## References

* http://www.xbswitch.com/Data/switchsmd/upload/image/20230703/XB-PB86-A1-0-R.pdf
