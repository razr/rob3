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

;==============================================================================
; ISR ENTRY — save context, derive axis pointer, select phase
;==============================================================================
isr_ext1:
        push    SFR_PSW             ; C0 D0     save PSW
        setb    PSW_RS0             ; D2 D3     PSW.3 = 1 -> register bank 1
        mov     R2,A                ; FA        save A
        mov     A,R0                ; E8        A = bank1 R0 (axis base ptr)
        add     A,#0x10             ; 24 10     R1 = base + 0x10 (workspace ptr)
        mov     R1,A                ; F9

;--- phase dispatch: bit7 = ADC-result-read, bit6 = timer hand-off ---
        jb      AXIS_MASK_B7,ext1_feedback ; 20 17 09  bit7 -> store ADC result
        jnb     AXIS_MASK_B6,ext1_control  ; 30 16 0D  not bit6 -> real axis control

;--- bit6 housekeeping: timer phase hand-off ---
        mov     C,TMR_PHASE_B4      ; A2 1C     carry = 0x23.4 (incoming phase)
        mov     TMR_PHASE_B3,C      ; 92 1B     0x23.3 = carry (publish phase)
        clr     TMR_PHASE_B4        ; C2 1C     clear incoming

;==============================================================================
; FEEDBACK PHASE (bit7) — store the just-completed ADC conversion
;==============================================================================
ext1_feedback:
        mov     SFR_DPH,#DEV_ADC_DATA ; 75 83 59  DPH -> ADC data read (0x59)
        movx    A,@DPTR             ; E0        A = ADC result
        mov     @R1,A               ; F7        store into feedback[axis]
        ajmp    0x0278             ; 41 78     -> advance mask/channel

;==============================================================================
; CONTROL PHASE (bits 0..5) — closed-loop servo for one axis
;==============================================================================
ext1_control:
        mov     SFR_DPH,#DEV_ADC_START ; 75 83 58  DPH -> ADC start (0x58) [HW]
        rl      A                   ; 23        A = base ptr * 2 (MOVC index)
        add     A,R1                ; 29
        add     A,#0xDE             ; 24 DE     offset into inline table
        mov     R4,A                ; FC        R4 = table offset
        movc    A,@A+PC             ; 83        fetch profile constant 1
        xch     A,R4                ; CC        swap: R4=const, A=offset
        movc    A,@A+PC             ; 83        fetch profile constant 2
        mov     SFR_B,A             ; F5 F0     B = const2

;--- read ADC feedback, compute signed error vs profile ---
        movx    A,@DPTR             ; E0        A = ADC feedback (ch A8=0) [HW]
        mov     R5,A                ; FD        R5 = raw feedback
        inc     SFR_DPH             ; 05 83     DPH -> 0x59 (ch A8=1)
        movx    A,@DPTR             ; E0        A = ADC data (ch A8=1)
        subb    A,R4                ; 9C        A -= R4 (profile-adjusted target)
        jc      ext1_error_neg      ; 40 27     negative error -> branch

;--- positive error path ---
        mov     @R1,A               ; F7        workspace = |error|
        mov     A,R5                ; ED        A = raw feedback
        mov     R5,SFR_B            ; AD F0     R5 = profile const from B
        mul     AB                  ; A4        A:B = feedback * const
        mov     R4,SFR_B            ; AC F0     R4 = high product
        mov     A,@R1               ; E7        A = |error|
        mov     SFR_B,R5            ; 8D F0     B = const
        mul     AB                  ; A4        A:B = error * const
        add     A,R4                ; 2C        A += high(feedback*const)
        rl      A                   ; 23        shift
        rl      A                   ; 23        shift
        anl     A,#0x03             ; 54 03     mask to 2 bits

;--- scale/clamp the command ---
ext1_scale:
        mov     R4,A                ; FC        R4 = scaled command
        mov     A,SFR_B             ; E5 F0     A = B (remaining product)
        addc    A,#0x00             ; 34 00
        rlc     A                   ; 33
        jc      ext1_clamp_hi       ; 40 1C     overflow -> clamp high
        rlc     A                   ; 33
        orl     A,R4                ; 4C
        jc      ext1_clamp_hi2      ; 40 22     overflow -> clamp high
        mov     @R1,A               ; F7        workspace = command
        anl     0x09,#0x57          ; 53 09 57  mask bank1 R1 bits [INFER]
        subb    A,@R1               ; 97
        jnz     ext1_moving         ; 70 22     not zero -> axis still moving
        mov     R4,#0x00            ; 7C 00     R4 = 0 (stopped)
        sjmp    ext1_lookup         ; 80 2D     -> motor output lookup

;--- negative error path ---
ext1_error_neg:
        mov     @R1,#0x00           ; 77 00     workspace = 0 (floor)
        mov     R4,#0x08            ; 7C 08     R4 = 0x08 (reverse direction flag)
        subb    A,#0xF9             ; 94 F9     compare magnitude
        mov     R6,A                ; FE
        jz      ext1_min_drive      ; 60 08     zero -> minimum drive
        jc      ext1_min_drive      ; 40 06     small -> minimum drive
        sjmp    ext1_drive          ; 80 2F     large -> full drive

ext1_clamp_hi:
        mov     @R1,#0xFF           ; 77 FF     workspace = 0xFF (ceiling)
        mov     R4,#0x04            ; 7C 04     R4 = 0x04 (forward high)
ext1_min_drive:
        mov     A,#0x01             ; 74 01     A = 1 (minimum step)
        mov     R6,#0x0A            ; 7E 0A     R6 = 0x0A (step rate) [INFER]
        sjmp    ext1_drive          ; 80 25     -> drive

ext1_clamp_hi2:
        mov     @R1,#0xFF           ; 77 FF     workspace = 0xFF (ceiling)
        mov     R4,#0x04            ; 7C 04     R4 = 0x04
        inc     A                   ; 04
        sjmp    ext1_set_rate       ; 80 0A

ext1_moving:
        jc      ext1_moving_neg     ; 40 04
        mov     R4,#0x04            ; 7C 04     forward direction
        sjmp    ext1_set_rate       ; 80 04
ext1_moving_neg:
        cpl     A                   ; F4        negate
        inc     A                   ; 04
        mov     R4,#0x08            ; 7C 08     reverse direction

ext1_set_rate:
        cjne    A,#0x0A,ext1_set_rate2 ; B4 0A 00  compare with rate threshold
ext1_set_rate2:
        jnc     ext1_min_drive      ; 50 E4     >= threshold -> minimum drive

;==============================================================================
; MOTOR OUTPUT LOOKUP — map (direction, speed) to L293 drive bits
;==============================================================================
ext1_lookup:
        mov     R6,A                ; FE        R6 = speed/command
        add     A,#0x94             ; 24 94     offset into MOVC table
        movc    A,@A+PC             ; 83        lookup motor output byte
        jbc     0xE7,ext1_arm_motion ; 10 E7 02  A.7 set -> arm motion mask
        sjmp    ext1_drive          ; 80 06

ext1_arm_motion:
        xch     A,AXIS_MASK         ; C5 22     swap A <-> mask
        orl     AXIS_ACTIVE,A       ; 42 21     set this axis in active mask
        xch     A,AXIS_MASK         ; C5 22     restore

;==============================================================================
; MOTOR DRIVE — write the encoded output to 8255 Port A/C shadow
;==============================================================================
ext1_drive:
        jb      SYS_AXIS_ENABLE,ext1_drive_go ; 20 00 02  axis subsystem on?
        ajmp    0x0278             ; 41 78     no -> skip drive, just advance
ext1_drive_go:
        mov     R5,A                ; FD        R5 = encoded output
        dec     @R0                 ; 16        decrement decel counter [INFER]
        mov     A,@R0               ; E6
        anl     A,#0x0F             ; 54 0F     mask low nibble
        jnz     ext1_no_step        ; 70 4C     not zero -> hold (no step this pass)

;--- step: apply direction/speed encoding to motor output ---
        mov     A,R5                ; ED
        orl     A,@R0               ; 46
        cjne    R6,#0x00,ext1_speed_nz ; BE 00 02  speed != 0?
        sjmp    ext1_write_shadow   ; 80 31     speed = 0 -> write as-is

ext1_speed_nz:
        cjne    R6,#0x01,ext1_speed_gt1 ; BE 01 07  speed != 1?
        jnb     0xE5,ext1_decel_check ; 30 E5 09  A.5 not set -> decel path
        add     A,#0x03             ; 24 03     adjust output
        sjmp    ext1_write_shadow   ; 80 27

ext1_speed_gt1:
        mov     A,R4                ; EC        A = direction/flag
        swap    A                   ; C4        swap nibbles
        orl     A,R5                ; 4D        merge with speed
        sjmp    ext1_write_shadow   ; 80 22

ext1_decel_check:
        jnb     0xE4,ext1_decel2    ; 30 E4 02  A.4 -> decel step 2
        add     A,#0x02             ; 24 02

ext1_decel2:
        cjne    R4,#0x04,ext1_decel3 ; BC 04 05  direction forward?
        jb      0xE6,ext1_decel_apply ; 20 E6 05  A.6 set -> apply
        sjmp    ext1_decel_alt      ; 80 11

ext1_decel3:
        jnb     0xE7,ext1_decel_alt ; 30 E7 0E  A.7 not set -> alt path

ext1_decel_apply:
        mov     0x09,R0             ; 88 09     save R0 to bank1 R1 [INFER]
        xrl     0x09,#0x70          ; 63 09 70  XOR with 0x70 -> decel ptr
        cjne    @R1,#0x0F,ext1_decel_step ; B7 0F 11  decel count != 0x0F?
        anl     A,#0xC0             ; 54 C0     mask top 2 bits
        orl     A,#0x03             ; 44 03     set low bits
        sjmp    ext1_store_output   ; 80 0C

ext1_decel_alt:
        xrl     A,#0xC0             ; 64 C0
        add     A,#0x0E             ; 24 0E

ext1_write_shadow:
        mov     0x09,R0             ; 88 09     save R0
        xrl     0x09,#0x70          ; 63 09 70  -> decel ptr
        mov     @R1,#0xFF           ; 77 FF     reset decel counter

ext1_decel_step:
        inc     @R1                 ; 07        increment decel counter

ext1_store_output:
        mov     @R0,A               ; F6        store output to workspace

;--- select Port A (axes 0..3) or Port C (axes 4..5) ---
        mov     A,R0                ; E8        A = axis base ptr
        jbc     0xE2,ext1_portc     ; 10 E2 0F  A.2 set -> Port C path (axes 4..5)
ext1_porta:
        mov     SFR_DPH,#DEV_8255_PA ; 75 83 50  DPH -> Port A
        mov     R1,#PORTA_SHADOW    ; 79 4E     R1 -> Port A shadow
        sjmp    ext1_write_port     ; 80 0D

ext1_no_step:
        mov     R4,#0x00            ; 7C 00     R4 = 0 (no new command)
        mov     A,R0                ; E8
        jnb     0xE2,ext1_porta     ; 30 E2 F3  not bit2 -> Port A
        clr     0xE2                ; C2 E2     clear the select bit

ext1_portc:
        mov     SFR_DPH,#DEV_8255_PC ; 75 83 52  DPH -> Port C
        mov     R1,#PORTC_SHADOW    ; 79 4F     R1 -> Port C shadow

;--- read-modify-write the port shadow with MOVC mask tables ---
ext1_write_port:
        mov     R5,A                ; FD        R5 = axis base ptr (MOVC index)
        movc    A,@A+PC             ; 83        fetch AND-mask from table
        anl     A,@R1               ; 57        clear this axis's bits in shadow
        mov     @R1,A               ; F7        update shadow
        mov     A,R4                ; EC        A = direction+speed encoding
        add     A,R5                ; 2D        offset into OR-mask table
        movc    A,@A+PC             ; 83        fetch OR-mask
        orl     A,@R1               ; 47        set this axis's new bits
        mov     @R1,A               ; F7        update shadow
        movx    @DPTR,A             ; F0        write to 8255 port [HW]

;--- check if this axis's motion is complete ---
        mov     A,AXIS_MASK         ; E5 22     A = current mask
        anl     A,NEED_MOVE         ; 55 2B     mask & need-move
        jnz     0x0214              ; 70 4B     still needed -> set motion-active flag
        ajmp    0x0278             ; 41 78     done -> advance

;==============================================================================
; INLINE MOVC LOOKUP TABLES (0x01CB..0x01E6)                            [BYTE]
;   Decoded as instructions by the disassembler but this is DATA — the MOVC
;   table entries for the motor-output AND/OR masks + profile constants.
;   Emitted as raw bytes to guarantee 1:1.
;==============================================================================
        .db     0x38,0x00,0x7C,0x50,0x00,0xC2,0x49,0x00 ; 01CB
        .db     0xCD,0x17,0x00,0x54,0x18,0x00,0x53,0x70 ; 01D3
        .db     0x00,0xFA,0x82,0x85,0x84,0x03,0x03      ; 01DB

;--- 0xFF padding (0x01E2..0x0202) — objcopy gap-fill handles this ---
;   The region extends to 0x0202 to cover the full ext1 address span;
;   bytes 0x01E2..0x0202 are 0xFF in the ROM (no code).
        .db     0x02,0x01,0x01,0x01,0x01                ; 01E2  (non-FF tail)
