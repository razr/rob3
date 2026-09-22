;==============================================================================
; ROB3 FIRMWARE — EXT1 / AXIS SERVO ISR (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the EXTERNAL INTERRUPT 1
;                    (ADC end-of-conversion) axis servo handler at 0x00C0.
;                    Companion to firmware/src/annotated/{vectors,init,main}.asm
;                    (init + vectors + main loop) and
;                    firmware/src/annotated/teachbox.asm (keypad),
;                    and the hardware docs under hardware/board/ (ADC0808/0809,
;                    L293, 8255).
;
; PROVENANCE TAGS
;   [BYTE] = decoded directly from the ROM bytes (verified in ucSim `dc`).
;   [HW]   = confirmed against the hardware schematic docs (hardware/board/).
;   [SIM]  = confirmed by running the ROM in ucSim and observing state.
;   [INFER]= inferred from context; treat as a hypothesis to confirm. In this
;            handler, the exact motor polarity and L293 output-table semantics
;            are [INFER] — the ROM only exposes the encoded table values.
;
;   DEFAULT: every instruction line below is [BYTE] (byte-exact from the ROM)
;   unless it carries a different tag. Only the exceptions are marked inline
;   ([INFER] for the encoded motor-output table reads, [HW][BYTE] for the MOVX
;   accesses to the ADC/8255 that are also confirmed against the hardware).
;
; ENTRY: reached from the External Interrupt 1 vector at 0x0013 (LJMP 0x00C0).
;   INT1 is driven by ADC0808/0809 end-of-conversion on P3.3. What STARTS each
;   conversion is a MOVX write to the ADC (DPH=0x58), which pulses the ADC START
;   pin (=8031 /WR) and latches the channel; that conversion's EOC then fires
;   this interrupt. So start and trigger are two ends of the same handshake:
;   init fires the FIRST conversion by hand, and the tail of every ISR starts
;   the NEXT one (see TRIGGER & RATE below). One interrupt services the axis
;   selected by the rotating mask at 0x22, then advances channel + pointer. [BYTE][HW]
;
;==============================================================================
; EXT1 / AXIS SERVO HANDLER  isr_ext1 (0x00C0)                 [BYTE][HW][INFER]
;------------------------------------------------------------------------------
; External Interrupt 1 is driven by ADC0808/0809 end-of-conversion on P3.3.
; A conversion is not periodic and is not timer-started: it is STARTED by a
; MOVX write to the ADC (the START pin = 8031 /WR), and its completion (EOC)
; is what raises this interrupt. One interrupt services the axis selected by
; the rotating mask at 0x22, then advances the ADC channel and workspace
; pointer for the next conversion.
; The ADC feedback path and INT1 wiring are [HW]; the control-flow and RAM
; accesses below are [BYTE]. Exact motor polarity and L293 semantics remain
; [INFER] where the ROM only exposes encoded output-table values.
;
; WHAT THIS INTERRUPT DOES (plain English)
;   This is the ROB3 closed-loop position servo. It is the ADC's "conversion
;   done" interrupt, and it runs the whole motion control for all six axes by
;   time-slicing: each INT1 handles ONE slot of an 8-step round-robin (see the
;   rotating-mask note below), so across 8 interrupts it sweeps every axis once.
;
;   For a given axis, one servo pass does the classic feedback loop:
;     1. READ the axis's measured position — the ADC conversion that just
;        finished is the pot voltage for this axis (device DPH=0x58/0x59). [BYTE][HW]
;     2. COMPUTE the error against that axis's commanded target/profile, using
;        the inline tables (subtract feedback from target, then scale/clamp the
;        result via MUL/rotate/AND into a bounded command). [BYTE]
;     3. CLAMP to the valid range: underflow -> 0x00 with a negative-direction
;        code, overflow -> 0xFF with a positive-direction code. [BYTE]
;     4. ENCODE speed + direction into the per-axis state, look the command up
;        in the motor output tables, and DRIVE the motor by writing the 8255
;        Port A (axes 0..3) or Port C (axes 4..5) shadow to the L293s. [BYTE]/[INFER]
;     5. ADVANCE the round-robin: rotate the axis/phase mask, select the next
;        ADC channel to start its conversion, and bump the workspace pointer so
;        the next INT1 works on the next axis. [BYTE][HW]
;
;   Net effect: as long as INT1 keeps firing, every axis is continuously nudged
;   toward its target position and held there — this is the loop that actually
;   makes the arm move and stay put. Motion commands from the teachbox / RS232
;   protocol just update the per-axis targets (0x40+N) and flags; THIS handler
;   turns those targets into motor drive using the pot feedback.
;   (Motor-drive polarity / exact L293 table semantics are [INFER].)
;
; DRIVING ALL SIX AXES "AT ONCE" (time-sliced, latched ports)
;   The manual says all axes can move simultaneously — yet this ISR services
;   only ONE axis per interrupt. Both are true, because:
;     - The six motors share two LATCHED 8255 output ports: Port A (shadow
;       0x4E) drives axes 0..3, Port C (shadow 0x4F) drives axes 4..5. Each axis
;       owns a couple of bits (direction/enable to its L293 channel). A latch
;       HOLDS every axis's bits until rewritten, so all six can be energized at
;       the same time. [HW]
;     - When servicing axis N, the output commit (ext1_apply_output) does a
;       READ-MODIFY-WRITE on that axis's port shadow: `anl A,@R1` keeps the
;       OTHER axes' bits, `orl A,@R1` sets only THIS axis's bits, then
;       `movx @DPTR,A` writes the whole port. So updating one axis does not
;       disturb the others. [BYTE]
;     - The round-robin re-services every axis every ~8 conversions (sub-ms),
;       far faster than a DC servo responds (ms+). Between updates each axis
;       keeps driving from the latch. So although only one axis is *updated* at
;       any instant, all six are effectively driven concurrently. [BYTE]/[INFER rate]
;   In short: it is time-division multiplexing — all axes latched-on together,
;   each nudged in turn fast enough that the motion looks simultaneous.
;
; TRIGGER & RATE — ADC-clocked, NOT timer-driven
;   EXT1 is External Interrupt 1 (8031 pin 13 / P3.3), and on this board that
;   pin is wired to the ADC0808/0809 End-Of-Conversion output (ADC pin 16 ->
;   8031 pin 13). So the handler fires on "ADC conversion done" — there is NO
;   timer in this path. [HW] (hardware/board/adc.md)
;
;   It is SELF-CLOCKED: the ISR tail (ext1_advance) writes the next channel to
;   0x5800, which latches ADD-A and pulses START on the ADC; that conversion's
;   EOC then fires the next EXT1. Crucially the ISR does NOT busy-wait for EOC —
;   it fires START and RETIs immediately (see the `movx @DPTR,A ... reti` tail).
;   So each interrupt kicks off the one that follows it, but with a real gap
;   between them. [BYTE][HW]
;
;   THE PAUSE BETWEEN INTERRUPTS = the ADC conversion time. Because the ISR
;   starts a conversion and returns at once, the CPU is FREE during the whole
;   convert window and runs the MAIN LOOP (teachbox scan, RS232 protocol,
;   program interpreter) until EOC interrupts it again. That gap is what keeps
;   the rest of the firmware alive — if EXT1 re-fired with no pause the ISR
;   would starve the main loop and nothing else would run. The pause is set by
;   the ADC's own conversion latency, NOT by any software delay or timer. [BYTE]
;   (ISR returns without waiting) / [HW] (latency = ADC hardware).
;
;   CADENCE: one axis/phase per interrupt; a FULL sweep of all six axes + the
;   two housekeeping phases = 8 conversions. The absolute rate is set by the
;   ADC's external CLOCK (ADC pin 17), not the CPU: an ADC0808/0809 conversion
;   is ~64 ADC-clocks, so at a typical ~0.5-1 MHz ADC clock that is on the order
;   of tens of microseconds per conversion (an axis serviced roughly every ~8
;   of those). The exact ADC clock source/frequency is NOT documented for this
;   board, so any absolute Hz figure — and thus the exact main-loop/ISR duty
;   split — is [INFER]; the EOC->INT1 trigger, the no-wait RETI, and the
;   self-clocking handshake are [BYTE][HW].
;
;   (Timer 0 is a SEPARATE ISR — the system tick at 0x0080 — which merely hands
;   a phase bit to this servo via 0x23.4/0x23.3; it does not trigger EXT1.)
;
; FEEDBACK SCALING / CALIBRATION — raw pot counts, NOT degrees
;   The 0..255 feedback (0x58+N) and target (0x40+N) values are RAW, ratiometric
;   ADC counts of the joint potentiometer: count = 255 * (V_pot / 5V), because
;   the ADC's VREF(+) is tied straight to +5V (hardware/board/adc.md). They are
;   NOT pre-scaled to degrees and NOT normalized to the axis travel. [HW]
;
;   The servo loop here is UNIT-AGNOSTIC: it only ever compares feedback against
;   target in the SAME raw-count scale and drives to close the gap. It never
;   converts to an angle, so no calibration constant appears in this ISR. [BYTE]
;
;   The count<->angle mapping is PER-AXIS, measured, and lives OUTSIDE the
;   firmware. Bench measurements (hardware/motors/test.md, and AXIS_CAL[0..5] in
;   hardware/motors/arduino/rob3_axis.h) show each axis uses only a sub-slice of
;   0..255 and that "0 degrees" is NOT 128 and differs per axis, e.g. [HW-bench]:
;     - shoulder: +70 deg = 0x7F(127), 0 deg = 0x9A(154), -44 deg = 0xBC(188)
;     - elbow:      0 deg = 0x43(67),  -90 deg = 0x8E(142), -110 deg = 0x9F(159)
;   Sign/direction also differs per axis. Any degree display was the host PC
;   software's job (TBPS), not the robot firmware's. [HW]/[INFER]
;
; Per-axis IRAM layout (N = axis 0..5). Each is a 6-byte array; axis N lives at
; base+N. (Cross-checked against the rob3-firmware-map skill.)
;   0x40+N  TARGET position   — the COMMANDED position (0..255). This is what a
;                               `POS a . n` / motion command writes: "where the
;                               axis should go".                         [BYTE]
;   0x48+N  SPEED / step rate — how fast to drive toward the target (ROB3 has
;                               5 selectable speeds); used in the ISR profile
;                               math.                          [BYTE]/[INFER units]
;   0x50+N  CURRENT position (host view) — a SNAPSHOT copy of the ADC feedback
;                               (0x58+N), taken on demand for host/display
;                               reporting; NOT the live per-conversion slot.
;                               (0x0498: `mov 0x50,0x58 ... 0x55,0x5D`.)   [BYTE]
;   0x58+N  FEEDBACK (ADC)    — the MEASURED position: the raw ADC0808/0809
;                               reading of this axis's feedback pot (0..255),
;                               written fresh by this ISR each conversion. [BYTE][HW]
;   0x70+N  DECEL profile     — deceleration/ramp data so the axis eases into
;                               the target instead of slamming it.       [INFER]
;   0x78+N  ISR workspace     — per-axis scratch/state the servo keeps between
;                               passes (encoded speed/direction state).   [BYTE]/[INFER]
; Shared flags/scratch:
;   0x22 rotating PHASE mask (see below — a scheduler, not per-axis data);
;   0x21 active axes; 0x2B need-move; 0x2C moving; 0x2D direction;
;   0x4E/0x4F 8255 Port A/C motor output shadows (axes 0-3 / 4-5).
;
;   TARGET vs FEEDBACK is the core pair: the servo drives FEEDBACK(0x58+N)
;   toward TARGET(0x40+N). SPEED/DECEL shape *how* the gap is closed. CURRENT
;   (0x50+N) is just the reported snapshot; 0x22 only picks whose turn it is.
;
; ---------------------------------------------------------------------------
; ONE AXIS PER INTERRUPT (worked example: you press `POS 2 . 200 ENT`)
; ---------------------------------------------------------------------------
;   IMPORTANT: EXT1 does NOT process all six axes in one call. Each INT1 handles
;   exactly ONE slot of the 8-step round-robin (the axis/phase named by 0x22),
;   then advances to the next slot and returns. It takes a full sweep of ~8
;   interrupts to service every axis once; the loop simply repeats forever as
;   the ADC keeps finishing conversions. [BYTE]
;
;   1. `POS 2 . 200 ENT` on the teachbox (axis "2" is 1-based on the pendant =
;      firmware axis N=1; the firmware numbers axes 0..5) writes the commanded
;      value into that axis's TARGET slot:
;          target[1] (0x41) = 200
;      The single-axis write path is `add A,#0x40 / mov R0,A / mov @R0,<val>`
;      (0x04F0) — byte-confirmed for the command dispatch; the exact teachbox
;      keypress-to-target routing is [BYTE for the store]/[INFER for the POS
;      key path]. (Nothing moves yet — a command only updates target[]/flags.)
;
;   2. Interrupts keep firing as the ADC cycles channels. When the round-robin
;      reaches axis 1's servo slot, THIS ISR runs one pass for axis 1 only:
;          feedback[1] (0x59) = ADC reading of axis-1 pot   (say 150)    [BYTE][HW]
;          error = target[1] - feedback[1]  = 200 - 150 = +50           [BYTE]
;          -> scale/clamp with speed[1]/decel[1] into a bounded command
;          -> encode direction(+)/speed, look up the motor output table
;          -> write 8255 Port A shadow (0x4E) -> L293 -> axis-1 motor drives
;             toward higher position.                          [BYTE]/[INFER drive]
;
;   3. The ISR advances (rotate 0x22, select next ADC channel, bump pointer)
;      and RETIs. The next INT1 services the NEXT slot (axis 2, then 3, ... then
;      the two housekeeping phases), never axis 1 again until the mask wraps.
;
;   4. As axis 1 physically moves, its pot changes, so on its NEXT turn
;      feedback[1] reads higher (e.g. 175, then 195...). error shrinks each
;      sweep until feedback ~= target; the command clamps toward "hold". The
;      axis has arrived and is held at 200. [INFER on the exact stop encoding]
;
;   So: target[] is the SET-POINT you command; feedback[] is the live SENSOR;
;   the ISR nudges one axis per interrupt, sweeping all six continuously.
;
; THE ROTATING MASK AT 0x22 — 8-WIDE, ONE-HOT (6 axes + 2 phases)   [BYTE]/[INFER]
;   0x22 holds a SINGLE set bit that walks left one position on every INT1:
;     init `mov 0x22,#0x01` (bit0), then each ISR does `mov A,0x22 / rl A /
;     mov 0x22,A`, so the bit cycles 0x01->02->04->08->10->20->40->80->(wrap)01.
;   The companion ADC channel counter advances with `inc A / anl A,#0x07`, i.e.
;   a full 0..7 (8-step) cycle in lockstep with the mask. So the round-robin is
;   8 wide, not 6: [BYTE]
;     - bits 0..5  -> the SIX real axes' servo/control work (ext1_control),
;                     matching the `mov R7,#0x06` six-axis init loop.   [BYTE]
;     - bit 6      -> a housekeeping phase: Timer-0 phase hand-off
;                     (mov C,0x23.4 / mov 0x23.3,C / clr 0x23.4).       [INFER]
;     - bit 7      -> the ADC-result read phase (ext1_feedback): store the
;                     just-completed conversion.                        [INFER]
;   Hence `jb 0x22.7,...` / `jnb 0x22.6,...` at entry select a *phase*, not an
;   axis number — the `.7`/`.6` are bit positions in the mask.          [BYTE]
;
;   INIT HANDSHAKE (0x0672): after seeding 0x22=0x01, selecting ADC ch0 and
;   enabling INT1 (IE=0x84), init busy-waits `jb 0x22.0,$ ; jnb 0x22.0,$` —
;   bit0 is cleared on the first INT1 (01->02) and set again only when the
;   rotation wraps (80->01), so init blocks for ONE FULL 8-phase ADC sweep
;   before disabling interrupts and running the six-axis setup loop. The
;   instructions are [BYTE]; "wait one full sweep" is [INFER] from the rotation.
;------------------------------------------------------------------------------
        ; symbols (the inc/*.inc equates) are provided by
        ; the top file rob3.asm, which includes this region in address order.

        .org    0x00C0
        push 0xD0                           ; C0 D0  00C0
        setb 0xD3                           ; D2 D3  00C2
        mov R2, A                           ; FA  00C4
        mov A, R0                           ; E8  00C5
        add A, #0x10                        ; 24 10  00C6
        mov R1, A                           ; F9  00C8
        jb 0x17, L_00D5                     ; 20 17 09  00C9
        jnb 0x16, L_00DC                    ; 30 16 0D  00CC
        mov C, 0x1C                         ; A2 1C  00CF
        mov 0x1B, C                         ; 92 1B  00D1
        clr 0x1C                            ; C2 1C  00D3
L_00D5:
        mov 0x83, #0x59                     ; 75 83 59  00D5
        movx A, @DPTR                       ; E0  00D8
        mov @R1, A                          ; F7  00D9
        ajmp 0x0278                         ; 41 78  00DA
L_00DC:
        mov 0x83, #0x58                     ; 75 83 58  00DC
        rl A                                ; 23  00DF
        add A, R1                           ; 29  00E0
        add A, #0xDE                        ; 24 DE  00E1
        mov R4, A                           ; FC  00E3
        movc A, @A + PC                     ; 83  00E4
        xch A, R4                           ; CC  00E5
        movc A, @A + PC                     ; 83  00E6
        mov 0xF0, A                         ; F5 F0  00E7
        movx A, @DPTR                       ; E0  00E9
        mov R5, A                           ; FD  00EA
        inc 0x83                            ; 05 83  00EB
        movx A, @DPTR                       ; E0  00ED
        subb A, R4                          ; 9C  00EE
        jc L_0118                           ; 40 27  00EF
        mov @R1, A                          ; F7  00F1
        mov A, R5                           ; ED  00F2
        mov R5, 0xF0                        ; AD F0  00F3
        mul AB                              ; A4  00F5
        mov R4, 0xF0                        ; AC F0  00F6
        mov A, @R1                          ; E7  00F8
        mov 0xF0, R5                        ; 8D F0  00F9
        mul AB                              ; A4  00FB
        add A, R4                           ; 2C  00FC
        rl A                                ; 23  00FD
        rl A                                ; 23  00FE
        anl A, #0x03                        ; 54 03  00FF
L_0101:
        mov R4, A                           ; FC  0101
        mov A, 0xF0                         ; E5 F0  0102
        addc A, #0x00                       ; 34 00  0104
        rlc A                               ; 33  0106
        jc L_0125                           ; 40 1C  0107
        rlc A                               ; 33  0109
        orl A, R4                           ; 4C  010A
        jc L_012F                           ; 40 22  010B
        mov @R1, A                          ; F7  010D
        anl 0x09, #0x57                     ; 53 09 57  010E
        subb A, @R1                         ; 97  0111
        jnz L_0136                          ; 70 22  0112
        mov R4, #0x00                       ; 7C 00  0114
        sjmp L_0145                         ; 80 2D  0116
L_0118:
        mov @R1, #0x00                      ; 77 00  0118
        mov R4, #0x08                       ; 7C 08  011A
        subb A, #0xF9                       ; 94 F9  011C
        mov R6, A                           ; FE  011E
        jz L_0129                           ; 60 08  011F
        jc L_0129                           ; 40 06  0121
        sjmp L_0154                         ; 80 2F  0123
L_0125:
        mov @R1, #0xFF                      ; 77 FF  0125
        mov R4, #0x04                       ; 7C 04  0127
L_0129:
        mov A, #0x01                        ; 74 01  0129
        mov R6, #0x0A                       ; 7E 0A  012B
        sjmp L_0154                         ; 80 25  012D
L_012F:
        mov @R1, #0xFF                      ; 77 FF  012F
        mov R4, #0x04                       ; 7C 04  0131
        inc A                               ; 04  0133
        sjmp L_0140                         ; 80 0A  0134
L_0136:
        jc L_013C                           ; 40 04  0136
        mov R4, #0x04                       ; 7C 04  0138
        sjmp L_0140                         ; 80 04  013A
L_013C:
        cpl A                               ; F4  013C
        inc A                               ; 04  013D
        mov R4, #0x08                       ; 7C 08  013E
L_0140:
        cjne A, #0x0A, L_0143               ; B4 0A 00  0140
L_0143:
        jnc L_0129                          ; 50 E4  0143
L_0145:
        mov R6, A                           ; FE  0145
        add A, #0x94                        ; 24 94  0146
        movc A, @A + PC                     ; 83  0148
        jbc 0xE7, L_014E                    ; 10 E7 02  0149
        sjmp L_0154                         ; 80 06  014C
L_014E:
        xch A, 0x22                         ; C5 22  014E
        orl 0x21, A                         ; 42 21  0150
        xch A, 0x22                         ; C5 22  0152
L_0154:
        jb 0x00, L_0159                     ; 20 00 02  0154
        ajmp 0x0278                         ; 41 78  0157
L_0159:
        mov R5, A                           ; FD  0159
        dec @R0                             ; 16  015A
        mov A, @R0                          ; E6  015B
        anl A, #0x0F                        ; 54 0F  015C
        jnz L_01AC                          ; 70 4C  015E
        mov A, R5                           ; ED  0160
        orl A, @R0                          ; 46  0161
        cjne R6, #0x00, L_0167              ; BE 00 02  0162
        sjmp L_0198                         ; 80 31  0165
L_0167:
        cjne R6, #0x01, L_0171              ; BE 01 07  0167
        jnb 0xE5, L_0176                    ; 30 E5 09  016A
        add A, #0x03                        ; 24 03  016D
        sjmp L_0198                         ; 80 27  016F
L_0171:
        mov A, R4                           ; EC  0171
        swap A                              ; C4  0172
        orl A, R5                           ; 4D  0173
        sjmp L_0198                         ; 80 22  0174
L_0176:
        jnb 0xE4, L_017B                    ; 30 E4 02  0176
        add A, #0x02                        ; 24 02  0179
L_017B:
        cjne R4, #0x04, L_0183              ; BC 04 05  017B
        jb 0xE6, L_0186                     ; 20 E6 05  017E
        sjmp L_0194                         ; 80 11  0181
L_0183:
        jnb 0xE7, L_0194                    ; 30 E7 0E  0183
L_0186:
        mov 0x09, R0                        ; 88 09  0186
        xrl 0x09, #0x70                     ; 63 09 70  0188
        cjne @R1, #0x0F, L_019F             ; B7 0F 11  018B
        anl A, #0xC0                        ; 54 C0  018E
        orl A, #0x03                        ; 44 03  0190
        sjmp L_01A0                         ; 80 0C  0192
L_0194:
        xrl A, #0xC0                        ; 64 C0  0194
        add A, #0x0E                        ; 24 0E  0196
L_0198:
        mov 0x09, R0                        ; 88 09  0198
        xrl 0x09, #0x70                     ; 63 09 70  019A
        mov @R1, #0xFF                      ; 77 FF  019D
L_019F:
        inc @R1                             ; 07  019F
L_01A0:
        mov @R0, A                          ; F6  01A0
        mov A, R0                           ; E8  01A1
        jbc 0xE2, L_01B4                    ; 10 E2 0F  01A2
L_01A5:
        mov 0x83, #0x50                     ; 75 83 50  01A5
        mov R1, #0x4E                       ; 79 4E  01A8
        sjmp L_01B9                         ; 80 0D  01AA
L_01AC:
        mov R4, #0x00                       ; 7C 00  01AC
        mov A, R0                           ; E8  01AE
        jnb 0xE2, L_01A5                    ; 30 E2 F3  01AF
        clr 0xE2                            ; C2 E2  01B2
L_01B4:
        mov 0x83, #0x52                     ; 75 83 52  01B4
        mov R1, #0x4F                       ; 79 4F  01B7
L_01B9:
        mov R5, A                           ; FD  01B9
        movc A, @A + PC                     ; 83  01BA
        anl A, @R1                          ; 57  01BB
        mov @R1, A                          ; F7  01BC
        mov A, R4                           ; EC  01BD
        add A, R5                           ; 2D  01BE
        movc A, @A + PC                     ; 83  01BF
        orl A, @R1                          ; 47  01C0
        mov @R1, A                          ; F7  01C1
        movx @DPTR, A                       ; F0  01C2
        mov A, 0x22                         ; E5 22  01C3
        anl A, 0x2B                         ; 55 2B  01C5
        jnz 0x0214                          ; 70 4B  01C7
        ajmp 0x0278                         ; 41 78  01C9
        addc A, R0                          ; 38  01CB
        nop                                 ; 00  01CC
        mov R4, #0x50                       ; 7C 50  01CD
        nop                                 ; 00  01CF
        clr 0x49                            ; C2 49  01D0
        nop                                 ; 00  01D2
        xch A, R5                           ; CD  01D3
        dec @R1                             ; 17  01D4
        nop                                 ; 00  01D5
        anl A, #0x18                        ; 54 18  01D6
        nop                                 ; 00  01D8
        anl 0x70, #0x00                     ; 53 70 00  01D9
        mov R2, A                           ; FA  01DC
        anl C, 0x85                         ; 82 85  01DD
        div AB                              ; 84  01DF
        rr A                                ; 03  01E0
        rr A                                ; 03  01E1
        ljmp 0x0101                         ; 02 01 01  01E2
        ajmp 0x0001                         ; 01 01  01E5
        mov R7, A                           ; FF  01E7
        mov R7, A                           ; FF  01E8
        mov R7, A                           ; FF  01E9
        mov R7, A                           ; FF  01EA
        mov R7, A                           ; FF  01EB
        mov R7, A                           ; FF  01EC
        mov R7, A                           ; FF  01ED
        mov R7, A                           ; FF  01EE
        mov R7, A                           ; FF  01EF
        mov R7, A                           ; FF  01F0
        mov R7, A                           ; FF  01F1
        mov R7, A                           ; FF  01F2
        mov R7, A                           ; FF  01F3
        mov R7, A                           ; FF  01F4
        mov R7, A                           ; FF  01F5
        mov R7, A                           ; FF  01F6
        mov R7, A                           ; FF  01F7
        mov R7, A                           ; FF  01F8
        mov R7, A                           ; FF  01F9
        mov R7, A                           ; FF  01FA
        mov R7, A                           ; FF  01FB
        mov R7, A                           ; FF  01FC
        mov R7, A                           ; FF  01FD
        mov R7, A                           ; FF  01FE
        mov R7, A                           ; FF  01FF
        mov R7, A                           ; FF  0200
        mov R7, A                           ; FF  0201
        mov R7, A                           ; FF  0202
