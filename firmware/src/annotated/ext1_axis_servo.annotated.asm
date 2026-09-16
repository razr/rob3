;==============================================================================
; ROB3 FIRMWARE — EXT1 / AXIS SERVO ISR (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the EXTERNAL INTERRUPT 1
;                    (ADC end-of-conversion) axis servo handler at 0x00C0.
;                    Companion to firmware/src/annotated/main.annotated.asm
;                    (init + vectors + main loop) and
;                    firmware/src/annotated/teachbox.annotated.asm (keypad),
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
        org     0x00C0
isr_ext1:
        push    0xD0                ; save PSW
        setb    0xD3                ; select register bank 1 (axis ISR bank)
        mov     R2,A                ; preserve accumulator across the ISR
        mov     A,R0                ; load current axis base pointer
        add     A,#0x10             ; derive feedback/workspace address
        mov     R1,A                ; R1 = 0x58+axis: feedback/workspace slot

        jb      0x22.7,ext1_feedback ; mask bit7 = ADC-result-read phase (not an axis)
        jnb     0x22.6,ext1_control  ; mask bit6? no -> axis servo (bits0..5); yes -> timer phase
        mov     C,0x23.4             ; (bit6 phase) transfer timer phase from Timer 0 ISR
        mov     0x23.3,C             ; publish phase to the axis state machine
        clr     0x23.4              ; consume the timer phase hand-off

; Feedback branch: read the completed ADC conversion for the selected axis and
; store it in that axis's feedback slot before advancing the round-robin state.
ext1_feedback:
        mov     0x83,#0x59           ; select ADC feedback device
        movx    A,@DPTR              ; read completed conversion
        mov     @R1,A                ; store feedback for this axis
        ajmp    ext1_advance         ; finish this pass and select next axis

; Control branch: derive the axis error/profile values and calculate a bounded
; motor command from the selected axis's feedback and target data.
ext1_control:
        mov     0x83,#0x58           ; select ADC channel/control device
        rl      A                    ; derive table index from axis state
        add     A,R1                 ; add axis workspace offset
        add     A,#0xDE              ; point into inline profile table
        mov     R4,A                ; preserve first table index
        movc    A,@A+PC              ; lookup output/control parameter
        xch     A,R4                ; exchange table value and second index
        movc    A,@A+PC              ; lookup complementary parameter
        mov     0xF0,A              ; save table value in B
        movx    A,@DPTR              ; read current feedback/control value
        mov     R5,A                ; preserve first sampled value
        inc     0x83                ; select adjacent ADC/control address
        movx    A,@DPTR             ; read second sampled value
        subb    A,R4                 ; compare feedback against target/table value
        jc      ext1_error_low       ; branch to low-side error handling
        mov     @R1,A               ; store the sampled difference
        mov     A,R5                ; restore first sampled value
        mov     R5,0xF0             ; move profile value into R5
        mul     AB                  ; multiply sampled value by profile value
        mov     R4,0xF0             ; preserve high product byte
        mov     A,@R1               ; reload stored difference
        mov     0xF0,R5             ; move second factor into B
        mul     AB                  ; multiply difference by second factor
        add     A,R4                ; combine product components
        rl      A                   ; scale computed output
        rl      A                   ; scale computed output again
        anl     A,#0x03              ; clamp/quantize output magnitude
        rr      A                   ; restore scaled value alignment
        mov     R4,A                ; retain scaled magnitude
        mov     A,0xF0              ; load high product byte
        addc    A,#0x00             ; propagate carry into high byte
        rlc     A                   ; test for upper-range saturation
        jc      ext1_limit_high     ; clamp positive overflow
        rlc     A                   ; continue range test
        orl     A,R4                ; merge magnitude and direction bits
        jc      ext1_limit_high     ; clamp encoded overflow
        mov     @R1,A               ; store calculated axis value
        anl     0x09,#0x57          ; retain relevant axis-state bits
        subb    A,@R1               ; compare calculated and stored values
        jnz     ext1_update_state   ; update state when value changed
        mov     R4,#0x00            ; zero adjustment for equal values
        sjmp    ext1_output_state   ; continue with output encoding

; Low-side clamp: the comparison underflowed, so force the working value to
; zero and continue with the negative-direction error/profile calculation.
ext1_error_low:
        mov     @R1,#0x00            ; clamp low-side value
        mov     R4,#0x08             ; record negative-direction code
        subb    A,#0xF9              ; calculate low-side error magnitude
        mov     R6,A                 ; save error magnitude
        jz      ext1_small_error     ; zero/small error uses minimum profile
        jc      ext1_small_error     ; underflow uses minimum profile
        sjmp    ext1_profile         ; continue with profile lookup

; High-side clamp: the calculated value overflowed the supported range, so
; saturate the working value at 0xFF and select the positive-direction code.
ext1_limit_high:
        mov     @R1,#0xFF            ; clamp high-side value
        mov     R4,#0x04             ; record positive-direction code
; Small-error path: use the minimum nonzero profile entry and its marker before
; entering the common profile selection logic.
ext1_small_error:
        mov     A,#0x01              ; minimum nonzero profile index
        mov     R6,#0x0A             ; retain small-error marker
        sjmp    ext1_profile        ; continue with profile lookup

; Changed-error path: derive the direction code from the subtraction carry and
; normalize negative values to a magnitude before selecting the profile.
ext1_update_state:
        jc      ext1_negative_error  ; branch for negative error
        mov     R4,#0x04             ; positive-direction code
        sjmp    ext1_profile_sign    ; normalize profile sign
; Negative-error normalization: convert the error magnitude to two's complement
; and record the negative motor-direction code.
ext1_negative_error:
        cpl     A                    ; two's-complement error magnitude
        inc     A                    ; complete two's complement
        mov     R4,#0x08             ; negative-direction code
; Profile-sign join: compare the normalized error with the small-error threshold
; and route large values through the common profile path.
ext1_profile_sign:
        cjne    A,#0x0A,ext1_profile ; compare against small-error threshold
; Profile threshold path: select the minimum profile when the comparison carry
; indicates that the error is outside the directly indexed profile range.
ext1_profile:
        jnc     ext1_small_error     ; saturate profile when threshold is exceeded
; Profile lookup: fetch the speed/direction entry and use its marker bit to
; update the active-axis mask before preparing the motor state.
ext1_output_state:
        mov     R6,A                 ; save profile index
        add     A,#0x94              ; index inline speed/direction table
        movc    A,@A+PC              ; read speed/direction profile entry
        jbc     0xE0.7,ext1_set_axis ; consume table direction/active marker
        sjmp    ext1_output          ; proceed without changing active mask
; Active-axis update: merge the profile's axis mask into the active-axis flags
; while preserving the rotating current-axis mask.
ext1_set_axis:
        xch     A,0x22               ; exchange profile mask with current axis mask
        orl     0x21,A               ; mark selected axis active
        xch     A,0x22               ; restore current axis mask

; Output gate: skip motor-state work unless the axis subsystem is enabled.
ext1_output:
        jb      0x20.0,ext1_motion   ; axis subsystem enabled?
        ajmp    ext1_advance         ; skip control when motion is disabled

; Motion-state update: combine the profile command with the selected axis's
; existing state and choose the speed/direction encoding branch.
ext1_motion:
        mov     R5,A                 ; preserve encoded profile value
        dec     @R0                  ; update per-axis motion counter
        mov     A,@R0                ; load per-axis state
        anl     A,#0x0F              ; isolate low state nibble
        jnz     ext1_write_output    ; nonzero state goes directly to output
        mov     A,R5                 ; restore encoded profile value
        orl     A,@R0                ; merge it with existing state
        cjne    R6,#0x00,ext1_speed_case ; branch for nonzero profile
        sjmp    ext1_write_state     ; zero profile uses the current state
; Speed-case dispatch: distinguish the special low-speed profile from the normal
; direction encoding path.
ext1_speed_case:
        cjne    R6,#0x01,ext1_direction_case ; select special profile case
        jnb     0xE0.5,ext1_speed_case_2    ; test encoded profile bit
        add     A,#0x03              ; apply special speed increment
        sjmp    ext1_write_state     ; store resulting state
; Direction encoding: place the direction code in the high nibble and combine
; it with the calculated speed/profile value.
ext1_direction_case:
        mov     A,R4                 ; load direction code
        swap    A                    ; move direction into output nibble
        orl     A,R5                 ; combine direction and speed
        sjmp    ext1_write_state     ; store resulting state
; Alternate speed case: apply the secondary speed increment when its profile bit
; is set, then continue to direction handling.
ext1_speed_case_2:
        jnb     0xE0.4,ext1_speed_case_3 ; test alternate speed bit
        add     A,#0x02              ; apply alternate speed increment
; Direction test: select the special direction update or retain the existing
; state when the profile does not request a direction change.
ext1_speed_case_3:
        cjne    R4,#0x04,ext1_direction_check ; test direction encoding
        jb      0xE0.6,ext1_direction_set   ; select direction update
        sjmp    ext1_state_done      ; retain state when direction is inactive
; Profile-marker check: only enter the direction update when the profile marker
; bit is set.
ext1_direction_check:
        jnb     0xE0.7,ext1_state_done ; retain state when profile marker is clear
; Direction update: address the per-axis workspace and apply the special output
; encoding used for the 0x0F state.
ext1_direction_set:
        mov     0x09,R0              ; form axis-state comparison address
        xrl     0x09,#0x70           ; map axis base to 0x78+axis workspace
        cjne    @R1,#0x0F,ext1_write_state ; skip special encoding unless state is 0x0F
        anl     A,#0xC0              ; preserve direction bits
        orl     A,#0x03              ; add minimum drive code
        sjmp    ext1_write_state     ; store resulting state
; State-completion path: transform the retained state into the stop/hold output
; form before writing it back to the axis workspace.
ext1_state_done:
        xrl     A,#0xC0              ; invert direction-related output bits
        add     A,#0x0E              ; apply stop/hold output offset
; State write setup: select the per-axis workspace and initialize the output
; sentinel used by the following increment.
ext1_write_state:
        mov     0x09,R0              ; select axis state workspace
        xrl     0x09,#0x70           ; map R0 to 0x78+axis
        mov     @R1,#0xFF            ; initialize output-state sentinel
; Output increment: advance the encoded per-axis output value for table lookup.
ext1_write_output:
        inc     @R1                  ; advance output-state value
; State commit and port selection: store the axis state, then choose Port A or
; Port C and its shadow register for the motor output update.
ext1_write_state_value:
        mov     @R0,A                ; update per-axis state/current value
        mov     A,R0                 ; reload axis workspace base
        jbc     0xE0.2,ext1_port_c  ; select Port C path for upper axes
        mov     0x83,#0x50           ; axes 0..3 use 8255 Port A
        mov     R1,#0x4E             ; select Port A shadow
        sjmp    ext1_apply_output    ; apply encoded output
; Upper-axis port path: prepare the Port C output selection and offset.
ext1_port_c:
        mov     R4,#0x00             ; clear alternate output offset
        mov     A,R0                 ; reload axis workspace base
        jnb     0xE0.2,ext1_port_a  ; retain Port A path if selector is clear
        clr     0xE0.2               ; clear selector before Port C output
; Port C selection join: select the Port C device and its output shadow.
ext1_port_a:
        mov     0x83,#0x52           ; axes 4..5 use 8255 Port C
        mov     R1,#0x4F             ; select Port C shadow
; Motor output commit: combine the table encodings with the selected Port A/C
; shadow, write the result to the 8255, and test the remaining move mask.
ext1_apply_output:
        mov     R5,A                 ; preserve axis/output table index
        movc    A,@A+PC              ; read first motor output encoding [INFER]
        anl     A,@R1                ; mask existing Port A/C shadow
        mov     @R1,A                ; store masked motor shadow
        mov     A,R4                 ; load direction/output offset
        add     A,R5                 ; form second output table index
        movc    A,@A+PC              ; read second motor output encoding [INFER]
        orl     A,@R1                ; merge encoded output with shadow
        mov     @R1,A                ; update Port A/C output shadow
        movx    @DPTR,A              ; write motor command to 8255 [HW][BYTE]
        mov     A,0x22               ; load current axis mask
        anl     A,0x2B               ; clear completed axes from need-move mask
        jnz     ext1_advance         ; advance when another axis remains active

; Round-robin exit: rotate the axis mask, select the next ADC channel, restore
; the interrupted CPU context, and return from EXT1.
ext1_advance:
        mov     A,0x22               ; load current rotating axis mask
        rl      A                    ; rotate mask to next axis
        mov     0x22,A               ; save next-axis mask
        mov     A,R0                 ; load current axis workspace base
        inc     A                    ; advance to next axis
        anl     A,#0x07              ; wrap axis selector
        mov     0x83,#0x58           ; select ADC channel device
        movx    @DPTR,A              ; select next channel AND pulse START (=/WR) -> begins next conversion [HW][BYTE]
        orl     A,#0x48              ; convert selector to 0x48+axis base
        mov     R0,A                 ; save next axis speed/state base
        mov     A,R2                 ; restore interrupted accumulator
        pop     0xD0                  ; restore interrupted PSW
        reti                          ; return from External Interrupt 1

;==============================================================================
; END OF EXT1 / AXIS SERVO HANDLER
;==============================================================================
