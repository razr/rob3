# ADC

The ADC is the board's analog sampling stage. It reads the sensor and potentiometer inputs and forwards converted values to the 8031 through the bus and interrupt logic.

## Part identification

The chip markings were scratched off by the designer, so the part is identified from the **ringed-out board connections** (continuity-verified) plus the firmware behaviour. The signal set — 8 multiplexed analog inputs, an 8-bit tri-state data bus, and the control lines `START`, `ALE`, `EOC`, `OUTPUT ENABLE`, external `CLOCK`, and channel-address inputs `ADD A/B/C` — is the unique fingerprint of the **ADC0808 / ADC0809** family (8-bit successive-approximation ADC with on-chip 8-channel multiplexer).

Because `VREF(+)` is tied straight to the +5 V rail (ratiometric, no precision reference), the looser-reference **ADC0809** is the most likely populated part; the ADC0808 is pin- and function-identical and would drop in.

## Pinout

The functional labels below are derived from the ringed-out net list, not from chip markings.

```text
                            +----U----+
            Analog input 4 ─|1      28|─ Analog input 3
            Analog input 5 ─|2      27|─ Analog input 2
            Analog input 6 ─┤3      26├─ Analog input 1
            Analog input 7 ─┤4      25├─ Analog input 0
                 VCC (+5V) ─|5      24|─ ADD C  (strapped GND)
                       GND ─|6      23|─ ADD B  (strapped VCC)
           D7 / data bit 7 ─┤7      22├─ ALE
           D6 / data bit 6 ─┤8      21├─ OUTPUT ENABLE
           D5 / data bit 5 ─┤9      20├─ ADD A
           D4 / data bit 4 ─┤10     19├─ START
           D3 / data bit 3 ─┤11     18├─ VCC (+5V)
           D2 / data bit 2 ─┤12     17├─ CLOCK
           D1 / data bit 1 ─┤13     16├─ EOC
           D0 / data bit 0 ─┤14     15├─ VREF(+) / VCC (+5V)
                            +---------+
```

> Note: the exact pin *positions* differ from the National Semiconductor datasheet
> silkscreen ordering because this mapping follows the physically-ringed nets on
> this board, not the canonical package drawing. The functional grouping
> (8 analog in / 8 data out / START / ALE / EOC / OE / CLOCK / ADD A-C) is what
> identifies the part.

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

## Firmware confirmation (ADC0808/0809)

The ADC0808/0809 identification is confirmed by the firmware in
`firmware/src/main.asm`. Every control line ringed out on the board has a
matching software behaviour:

- **EOC → /INT1 (pin 16 → 8031 pin 13).** The 8031 interrupt vector at `0013h`
  (External Interrupt 1) jumps to `jump_00BF`. Byte-offset check in
  `main.asm`: `org 01h` places the INT0 `ljmp` at `0003h → jump_003F`, the
  Timer-0 `ljmp` at `000Bh → jump_007F`, and the next `ljmp jump_00BF` at
  `0013h`. So the ADC's end-of-conversion pulse is what fires the handler —
  exactly how an ADC0809 signals "data ready".

- **Channel step + START via memory-mapped address latch (pins 20/22/19).**
  The `jump_0278` tail of the /INT1 handler advances the channel and launches
  the next conversion:

  ```asm
  jump_0278:
      mov A, 22h      ; current channel bit-mask
      rl A            ; rotate to next channel pattern
      mov 22h, A
      mov A, R0
      inc A           ; next channel index
      anl A, #07h     ; keep it in 0..7  (three ADD lines' worth)
      mov 83h, #58h   ; DPH = 58h  -> external address 5800h
      movx @DPTR, A   ; write channel addr: latches ADD lines (ALE) and
                      ; pulses /WR = START on the ADC
      orl A, #48h
      mov R0, A
      mov A, R2
      pop 0D0h
      reti
  ```

  The `movx @DPTR,A` to `5800h` maps through `74LS138` (pin 22 = ALE / channel
  latch, decoder output) and pulses `/WR` (8031 pin 16 → ADC pin 19 = START).
  This is the classic ADC0809 "latch channel address, then START" sequence.

- **Data read via OUTPUT ENABLE (pin 21 → 8255 pin 5 /RD).** Converted bytes
  are read back through the 8255 data port and stored in the internal RAM
  telemetry block (`50h`-`55h`), matching the 8-bit tri-state data bus
  (D0-D7 → 8255 pin 34..27).

- **`anl A,#07h` proves an 8-channel device.** The firmware masks the channel
  index to `0..7`, i.e. it addresses 8 mux channels — the exact channel count
  of the ADC0808/0809. (On this board only `ADD A` is bused to the CPU via
  A8/8255; `ADD B`/`ADD C` are strapped, so the physically-reachable channels
  are a subset, but the code is written for the full 3-bit `0..7` range.)

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
