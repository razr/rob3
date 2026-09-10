# ADC

The ADC is the board's analog sampling stage. It reads the sensor and potentiometer inputs and forwards converted values to the 8031 through the bus and interrupt logic.

## Pinout

```text
                            +----U----+
            Analog input 4 ─|1      28|─ Analog input 3
            Analog input 5 ─|2      27|─ Analog input 2
            Analog input 6 ─┤3      26├─ Analog input 1
            Analog input 7 ─┤4      25├─ Analog input 0
                           ─|5      24|─ 
                           ─|6      23|─ 
           D7 / data bit 7 ─┤7      22├─ ALE
           D6 / data bit 6 ─┤8      21├─ OUTPUT ENABLE
           D5 / data bit 5 ─┤9      20├─ ADD A
           D4 / data bit 4 ─┤10     19├─ START
           D3 / data bit 3 ─┤11     18├─ 
           D2 / data bit 2 ─┤12     17├─ CLOCK
           D1 / data bit 1 ─┤13     16├─ EOC
           D0 / data bit 0 ─┤14     15├─ 
                            +---------+
```

## Board connections

```text
                                +----U----+
           Connector #5 pin 1 ──|1      28|── Connector #4 pin 1 <- potentiometer pin 3
           Connector #6 pin 1 ──|2      27|── Connector #3 pin 1 <- potentiometer pin 3
      M34004 pin 6/7 via 10kΩ ──|3      26|── Connector #2 pin 1 <- potentiometer pin 3
      M34004 pin 8/9 via 10kΩ ──|4      25|── Connector #1 pin 1 <- potentiometer pin 3
                    VCC (+5V) ──|5      24|── GND
                          GND ──|6      23|── VCC (+5V)
              8255 pin 27 (D7) ─┤7      22├── 74LS138 pin 7
              8255 pin 28 (D6) ─┤8      21├── 8255 pin 5 /RD
              8255 pin 29 (D5) ─┤9      20├── 8031 pin 21, 8255 pin 9
              8255 pin 30 (D4) ─┤10     19├── 8031 pin 16 /WR
              8255 pin 31 (D3) ─┤11     18├── VCC (+5V)
              8255 pin 32 (D2) ─┤12     17├── 8031 pin 30 ALE
              8255 pin 33 (D1) ─┤13     16├── 8031 pin 13 /INT1
              8255 pin 34 (D0) ─┤14     15├── VCC (+5V)
                                +---------+
```

## Notes

- The ADC is tied to the sensor network and multiplexed channel logic.
- ADC pin 15 (`VREF(+)`) is tied to VCC (+5V), the same rail used by the L293 enable inputs.
- The conversion and channel-switch behavior is managed by the 8031 interrupt routine and the decoder bus.

## Reverse-engineering relevance

The ADC block is a critical clue for mapping firmware behavior to robot state. Every conversion channel and interrupt event reflects a physical sensor or actuator variable, which means the binary can be correlated to actual robot telemetry.

When reconstructing the firmware, treat the ADC read path as the board's measurement channel decoder: the 8031 cycles through analog inputs, stores the values in RAM, and then interprets them as sensor positions, thresholds, or command feedback.

```asm
jump_00BF:
	mov R7, A        ; Catch the Accumulator immediately in Bank 0's R7
	push 0D0h        ; Save the main program's PSW (including its Register Bank choice)
	setb 0D0h.3      ; Set Bit 3 of PSW (address 0D0h) to 1. This bit is RS0!
    mov R2, A        ; Copy the Accumulator safely into Bank 1's R2
	mov A, R0        ; Copy the value of Register R0 into the Accumulator
	add A, #10h	     ; Add the literal hex value 16 (10h) to the Accumulator
	mov R1, A        ; R1 now contains the exact value of R0 + 10h
	jb 22h.7, jump_00D5  ; jump if 22h.7 == 1
	jnb 22h.6, jump_00DC ; jump if 22h.6 == 0
	mov C, 23h.4         ; 
	mov 23h.3, C         ; copy 23h.4 to 23h.3
	clr 23h.4            ; and clear 23h.4

jump_00D5:
	mov 83h, #59h
	movx A, @DPTR
	mov @R1, A
	ajmp jump_0278

jump_00DC:
	mov 83h, #58h	;  88 'X'
	rl A
	add A, R1
	add A, #0DEh	; 222  -34 'Þ'
	mov R4, A
	movc A, @A + PC
	xch A, R4
	movc A, @A + PC
	mov 0F0h, A
	movx A, @DPTR
	mov R5, A
	inc 83h
	movx A, @DPTR
	subb A, R4
	jc jump_0118
	mov @R1, A
	mov A, R5
	mov R5, 0F0h
	mul AB
	mov R4, 0F0h
	mov A, @R1
	mov 0F0h, R5
	mul AB
	add A, R4
	rl A
	rl A
	anl A, #03h
```

## The Channel-Switching Logic

Every time the ADC finishes reading a potentiometer, it fires the `_INT1` interrupt. Inside that interrupt loop, the processor executes this exact block of code found at label `jump_0278`:

```asm
jump_0278:
	mov A, 22h     ; 1. Grab the current active channel mask
	rl A           ; 2. Rotate bits to step to the next channel pattern
	mov 22h, A
	mov A, R0      ; 3. Get the raw channel index number (0 to 7)
	inc A          ; 4. INCREMENT IT: Advance to the next channel address!
	anl A, #07h	;  ; 5. MASK IT: Keep it strictly bounded between 0 and 7
	mov 83h, #58h  ; 6. Set DPH = 58h (Points to external address 5800h)
	movx @DPTR, A  ; 7. WRITE TO HARDWARE: This physically forces the 74138
                   ;    and 8255 lines to set the new address pins AND
				   ;    pulses the _WR line to launch the new conversion!
	orl A, #48h	;  72 'H'
	mov R0, A
	mov A, R2
	pop 0D0h
	reti
```

## The 6-Channel Telemetry Block

When the 8031 handles data storage and serial communication, it uses a block of exactly 6 registers in RAM from address 50h to 55h. Each register holds the digital position value of one of your 6 pots:
- 50h → Potentiometer 1
- 51h → Potentiometer 2
- 52h → Potentiometer 3
- 53h → Potentiometer 4
- 54h → Potentiometer 5
- 55h → Potentiometer 6

```asm
jump_04AF:
	jb 0E0h.4, jump_051F
	anl A, #07h	;   7
	cjne A, #07h, jump_04CE	;   7
	mov 21h, #00h	;   0
	mov 50h, 60h
	mov 51h, 61h
	mov 52h, 62h
	mov 53h, 63h
	mov 54h, 64h
	mov 55h, 65h
	sjmp jump_04FF
```
