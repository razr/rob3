;==============================================================================
; ROB3 INDUSTRIAL ROBOT — FIRMWARE ANNOTATED DISASSEMBLY
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
;                     firmware/hex/M2764A@DIP28.HEX
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human annotated listing. Currently covers the
;                    INITIALIZATION SEQUENCE (reset -> main loop entry).
;
; PROVENANCE OF ANNOTATIONS
;   [BYTE]  = Verified by decoding the raw ROM bytes (xxd of the .BIN).
;             These are the exact opcodes the CPU fetches and executes.
;   [SIM]   = Verified dynamically in the ucSim/s51 simulator.
;   [INFER] = Inferred from context / hardware; NOT yet proven. Treat as
;             a hypothesis to confirm.
;   [HW]    = Confirmed by cross-referencing the hardware schematic docs under
;             hardware/board/ (ringed-out board connections + decode logic).
;
; NOTE ON THE ORIGINAL disasm51 LISTING (firmware/src/main.asm)
;   The auto-generated main.asm mislabels the reset target as "jump_05FF"
;   and renders the 0xFF EPROM padding as endless "MOV R7,A". The byte-level
;   truth is that the reset vector is  LJMP 0x0600  and real init code begins
;   at 0x0600. Addresses in THIS file are the true byte offsets. [BYTE]
;
;------------------------------------------------------------------------------
; CONTROL BOARD IC COMPLEMENT (as reported for this hardware)
;------------------------------------------------------------------------------
;   8031            - Host CPU (MCS-51), external ROM/RAM bus, XTAL 11.0592 MHz
;   EPROM 8K        - M2764A, holds this firmware (code memory)
;   SRAM 8K         - External data RAM; stores robot programs (probed at boot)
;   8255            - Programmable Peripheral Interface (Ports A/B/C + control)
;   74LS138         - 3-to-8 decoder. [HW] Generates the device selects seen
;                     as DPH values on MOVX. Real CPU selects are B=A11, C=A12;
;                     input A is tied to output Y4 (self-latch, not an address
;                     line). See EXTERNAL DEVICE MAP for the DPH->Yn table.
;   74HC373         - Octal transparent latch. [INFER] AD0-AD7 address latch for
;                     the 8031 multiplexed low-address/data bus.
;   74LS244         - Octal buffer/line driver. [INFER] Input read path
;                     (e.g. keyboard / feedback bus onto the data bus).
;   L293 x3         - Dual H-bridge motor drivers. 3 x 2 channels = up to 6
;                     motor channels -> matches the 6 robot axes driven from
;                     8255 Port A / Port C. [INFER on exact channel mapping]
;   ADC             - ADC0808/0809 8-bit, 8-channel SAR ADC. [HW] Axis position
;                     feedback read via MOVX at DPH=0x58/0x59 (74LS138 Y6/Y7),
;                     A8 = channel line ADD-A. Feedback is ANALOG, not a
;                     quadrature encoder. EOC -> INT1 (8031 pin 13).
;   M34004          - [INFER] Function not yet confirmed (driver/array?).
;   MAX1044         - Switched-capacitor voltage inverter; generates a negative
;                     rail (e.g. for the ADC / analog front end). Not directly
;                     firmware-visible.
;   MM74C04N x2     - Hex inverters. [INFER] General logic / signal inversion.
;   74HC14          - Hex Schmitt-trigger inverter. [INFER] Input signal
;                     conditioning (e.g. the P3.0 serial/baud-detect input).
;
;------------------------------------------------------------------------------
; EXTERNAL DEVICE MAP (DPH selects the device on MOVX @DPTR)
;   DPH   Device                                   Confirmation
;   0x48  Aux / axis-select latch (74LS138 Y2/Y3)  [HW] decode: A12=0,A11=1
;   0x50  8255 Port A  (motor phase outputs)       [BYTE] init writes 0x00
;   0x51  8255 Port B  (general digital out)       [BYTE] init writes 0xFF
;   0x52  8255 Port C  (motor phase outputs)       [BYTE] init writes 0x00
;   0x53  8255 Control register                    [BYTE] init writes 0x80
;   0x58  ADC / axis feedback, channel A8=0        [BYTE] init writes 0x00
;   0x59  ADC / axis feedback, channel A8=1        [BYTE] init writes 0x01
;   0x80  External SRAM window base                [BYTE] probe starts here
;   0xA0  External SRAM (alt page)                 [BYTE] probe fallback
;
;   DECODER DERIVATION (confirmed against hardware/board/74LS138.md):        [HW]
;     The 74LS138 real CPU selects are B = A11 and C = A12; input A (pin 1) is
;     tied to output Y4 (pin 11) as a self-latch, so A is NOT a CPU address
;     line. A14/A15 gate peripheral space (A14=1,A15=0) vs external SRAM
;     (A15=1). Thus the peripheral DPH values decode purely on A11/A12:
;         A12=0,A11=1 -> Y2/Y3 region -> DPH 0x48 (aux/axis latch)
;         A12=1,A11=0 -> Y4/Y5 region -> DPH 0x50..0x53 (8255; A0/A1 pick port)
;         A12=1,A11=1 -> Y6/Y7 region -> DPH 0x58/0x59 (ADC; Y7 -> ADC pin 22)
;     0x50..0x53 are distinguished by the 8255's OWN A0/A1, not the decoder.
;     0x58 vs 0x59 differ only in A8 = the ADC channel line ADD A (only ADD A
;     is CPU-driven; ADD B/ADD C are strapped). See hardware/board/adc.md.
;------------------------------------------------------------------------------
; INTERRUPT VECTORS (actual targets, verified from ROM bytes)
;   0x0000 RESET   -> LJMP 0x0600  (init)
;   0x0003 EXT0    -> LJMP 0x0040  (EMERGENCY-OFF handler; INT0 = P3.2, active LOW)
;   0x000B TIMER0  -> LJMP 0x0080  (system tick ISR)
;   0x0013 EXT1    -> LJMP 0x00C0  (axis servo ISR)
;   0x001B TIMER1  -> (0xFF, no handler installed)
;   0x0023 SERIAL  -> 0xFF fillers, fall through to LJMP 0x0300 at 0x0035
;                     -> RS232 UART ISR at 0x0300 (ES enabled via IE=0x17)
;==============================================================================


;==============================================================================
; INTERRUPT / RESET VECTOR TABLE  (0x0000 - 0x0025)   [BYTE]
;------------------------------------------------------------------------------
; Decoded directly from ROM bytes. disasm51 rendered these incorrectly.
;==============================================================================
        org     0x0000
reset_vector:
        ljmp    init_start          ; 0x0600  RESET -> initialization        [BYTE]

        org     0x0003
ext_int0_vector:
        ljmp    0x0040              ; External Interrupt 0 -> EMERGENCY-OFF handler [BYTE]
                                    ; (INT0 = P3.2, active LOW; see emergency_off below)

        org     0x000B
timer0_vector:
        ljmp    0x0080              ; Timer 0 overflow (system tick ISR)      [BYTE]

        org     0x0013
ext_int1_vector:
        ljmp    0x00C0              ; External Interrupt 1 (axis servo ISR)   [BYTE]

        org     0x001B
timer1_vector:
        ; 0x001B..0x0022 = unused Timer 1 vector gap.                        [BYTE]
        ; Timer 1 is only the UART baud-rate generator; its interrupt (ET1) is
        ; NEVER enabled (all IE writes = 0x84 / 0x07 / 0x17, none set bit 3).
        ; The stray bytes at 0x0020-0x0022 (00 12 22, which a disassembler shows
        ; as NOP / LCALL 0x22FF) are DEAD DATA: nothing branches to 0x0020 and
        ; the CPU never vectors to 0x001B. LCALL 0x22FF also targets outside the
        ; 8 KB ROM, confirming it is not real code. [BYTE]

        org     0x0023
serial_vector:
;   RS232 SERIAL INTERRUPT. The 8051 UART interrupt vectors here (0x0023).
;   The 3-byte vector slot itself is 0xFF padding; execution FALLS THROUGH the
;   0xFF fillers (each 0xFF = MOV R7,A, a harmless 1-byte op) from 0x0023 up to
;   0x0035, where the real jump lives:
;
;       0x0035:  02 03 00     LJMP 0x0300      -> serial ISR                 [BYTE]
;
;   The serial interrupt IS enabled: the init path executes  MOV IE,#0x17  at
;   0x0739, which sets ES (serial), EX1, ET0, EX0 (plus EA later). So RS232
;   is interrupt-driven through the handler at 0x0300.                       [BYTE]
;
;   Handler prologue @ 0x0300 (confirms it is the UART ISR):
;       0300: C0 D0        PUSH PSW
;       0302: D2 D4        SETB PSW.4        ; switch to ISR register bank
;       0305: 30 98 4A     JNB  SCON.0(RI),..; test receive flag
;       0308: C2 98        CLR  SCON.0(RI)   ; ack received byte
;       030A: E5 99        MOV  A,SBUF       ; read received byte
;       030C: 75 18 14     MOV  0x18,#0x14   ; reload serial timeout counter
;
;   CORRECTION HISTORY: an earlier draft first claimed "LJMP 0x0300 at 0x0023"
;   (wrong address), then wrongly claimed "no serial handler exists". Both were
;   incorrect. The truth (verified from ROM bytes): vector slot is 0xFF, the
;   LJMP 0x0300 sits at 0x0035 reached by fall-through, and the ISR at 0x0300
;   is the RS232 UART handler. [BYTE]


;==============================================================================
; EMERGENCY-OFF HANDLER  emergency_off (0x0040)      [BYTE][SIM][HW]
;------------------------------------------------------------------------------
; The External-Interrupt-0 (INT0) service routine, reached via the 0x0003
; vector (LJMP 0x0040). INT0 is the 8031 P3.2 pin (board 8031.md); on the ROB3
; board P3.2 is wired — through MM74C04N #1 — to the DB25 pin-4 "EMERGENCY OFF"
; line, which is **active LOW** (hardware/board/MM74C04N.md,
; hardware/teachbox/README.md, hardware/connectors/db25.md).            [HW]
;
; INT0 is enabled and LEVEL-triggered: init sets IE=0x17 (EX0 among others) at
; 0x0739, and TCON.IT0 is left 0. So while P3.2 is held LOW the interrupt keeps
; re-asserting and this handler runs continuously.                      [BYTE]
;
; Behaviour: it (1) immediately hammers both motor 8255 ports to 0 to cut all
; drive, then (2) SPINS until P3.2 goes HIGH again (emergency released), then
; (3) restores the motor ports from the saved shadow bytes 0x4E/0x4F and RETIs.
; This matches the manual: "Activation of the function switches off the ROB3i's
; motors. After eliminating the problem, you must execute a RESET".     [HW]
;
; SIMULATION NOTE (why the teachbox never gets polled in ucSim):        [SIM]
;   ucSim's P3.2 pin reads LOW when nothing drives it, so the firmware sees a
;   permanent EMERGENCY-OFF: INT0 fires, this handler runs, and the `JNB P3.2`
;   spin at 0x0054 never falls through. Execution therefore never returns to
;   the main-loop teachbox poll (tb_poll, 0x07C4) — verified by tracing the PC
;   from the main loop straight into 0x0003 -> 0x0040 and looping in
;   0x0047..0x0054. To simulate normal operation the P3.2 pin must be driven
;   HIGH (emergency-off de-asserted). See rob3-lessons-learned.
;==============================================================================
        org     0x0040
emergency_off:
        push    0xD0                ; C0 D0     PUSH PSW
        setb    0xD3                ; D2 D3     PSW.3 = 1 -> register bank 1
        mov     R2,A                ; FA        save A
        clr     A                   ; E4
        mov     R1,A                ; F9        R1 = 0 (DJNZ wraps -> 256 passes)
eo_kill:
        mov     0x83,#0x50          ; 75 83 50  DPH = 0x50 -> 8255 Port A (5000H)
        clr     A                   ; E4
        movx    @DPTR,A             ; F0        Port A = 0 (motors axes 0..3 OFF)
        mov     0x83,#0x52          ; 75 83 52  DPH = 0x52 -> 8255 Port C (5200H)
        movx    @DPTR,A             ; F0        Port C = 0 (motors axes 4..5 OFF)
        djnz    R1,eo_kill          ; D9 F5     hammer both ports to 0, 256x
eo_wait:
        mov     R1,#0x00            ; 79 00     reload the release-debounce count
        jnb     0xB2,eo_wait        ; 30 B2 FB  WHILE P3.2(INT0)==LOW: spin here
        djnz    R1,eo_wait+2        ; D9 FB     require P3.2 HIGH for 256 counts
        mov     0x83,#0x50          ; 75 83 50  restore Port A...
        mov     A,0x4E              ; E5 4E       from motor shadow byte 0x4E
        movx    @DPTR,A             ; F0
        mov     0x83,#0x52          ; 75 83 52  restore Port C...
        mov     A,0x4F              ; E5 4F       from motor shadow byte 0x4F
        movx    @DPTR,A             ; F0
        mov     A,R2                ; EA        restore A
        pop     0xD0                ; D0 D0     POP PSW
        jbc     0x43.3,eo_setrow    ; 10 43 03  bit 0x28.3: pending? -> reset row latch
        setb    0x01                ; D2 01     else set bit 0x20.1 (keyboard-event flag)
        reti                        ; 32
eo_setrow:
        mov     0x47,#0xFF          ; 75 47 FF  idle the LED/row-strobe latch
        reti                        ; 32
;   Byte-exact (0x0040..0x0071):
;     c0 d0 d2 d3 fa e4 f9 75 83 50 e4 f0 75 83 52 f0
;     d9 f5 79 00 30 b2 fb d9 fb 75 83 50 e5 4e f0 75
;     83 52 e5 4f f0 ea d0 d0 10 43 03 d2 01 32 75 47
;     ff 32
;   CORRECTION HISTORY: the vector-table summary previously labelled
;   0x0003 -> 0x0040 as a "motor pulse ISR". That was wrong: 0x0040 is the
;   INT0 EMERGENCY-OFF handler (P3.2 active-LOW), verified [BYTE]+[SIM]+[HW].


;==============================================================================
; EXT1 / AXIS SERVO HANDLER  isr_ext1 (0x00C0)                 [BYTE][HW][INFER]
;------------------------------------------------------------------------------
; External Interrupt 1 is driven by ADC0808/0809 end-of-conversion on P3.3.
; One interrupt services the axis selected by the rotating mask at 0x22, then
; advances the ADC channel and workspace pointer for the next conversion.
; The ADC feedback path and INT1 wiring are [HW]; the control-flow and RAM
; accesses below are [BYTE]. Exact motor polarity and L293 semantics remain
; [INFER] where the ROM only exposes encoded output-table values.
;
; Per-axis layout (N = 0..5):
;   0x40+N target, 0x48+N speed/state input, 0x50+N current position,
;   0x58+N ADC feedback, 0x70+N deceleration/state workspace, 0x78+N ISR state.
;   0x22 rotating axis mask; 0x21 active axes; 0x2B need-move;
;   0x2C moving; 0x2D direction; 0x4E/0x4F Port A/C output shadows.
;------------------------------------------------------------------------------
        org     0x00C0
isr_ext1:
        push    0xD0                ; save PSW                                      [BYTE]
        setb    0xD3                ; select register bank 1 (axis ISR bank)        [BYTE]
        mov     R2,A                ; preserve accumulator across the ISR           [BYTE]
        mov     A,R0                ; load current axis base pointer             [BYTE]
        add     A,#0x10             ; derive feedback/workspace address          [BYTE]
        mov     R1,A                ; R1 = 0x58+axis: feedback/workspace slot   [BYTE]

        jb      0x22.7,ext1_feedback ; active-axis path: sample ADC feedback [BYTE]
        jnb     0x22.6,ext1_control  ; otherwise use the output/control path [BYTE]
        mov     C,0x23.4             ; transfer timer phase from Timer 0 ISR [BYTE]
        mov     0x23.3,C             ; publish phase to the axis state machine [BYTE]
        clr     0x23.4              ; consume the timer phase hand-off           [BYTE]

; Feedback branch: read the completed ADC conversion for the selected axis and
; store it in that axis's feedback slot before advancing the round-robin state.
ext1_feedback:
        mov     0x83,#0x59           ; select ADC feedback device                  [BYTE]
        movx    A,@DPTR              ; read completed conversion                  [BYTE]
        mov     @R1,A                ; store feedback for this axis                [BYTE]
        ajmp    ext1_advance         ; finish this pass and select next axis      [BYTE]

; Control branch: derive the axis error/profile values and calculate a bounded
; motor command from the selected axis's feedback and target data.
ext1_control:
        mov     0x83,#0x58           ; select ADC channel/control device          [BYTE]
        rl      A                    ; derive table index from axis state        [BYTE]
        add     A,R1                 ; add axis workspace offset                 [BYTE]
        add     A,#0xDE              ; point into inline profile table            [BYTE]
        mov     R4,A                ; preserve first table index                 [BYTE]
        movc    A,@A+PC              ; lookup output/control parameter           [BYTE]
        xch     A,R4                ; exchange table value and second index     [BYTE]
        movc    A,@A+PC              ; lookup complementary parameter            [BYTE]
        mov     0xF0,A              ; save table value in B                       [BYTE]
        movx    A,@DPTR              ; read current feedback/control value       [BYTE]
        mov     R5,A                ; preserve first sampled value                [BYTE]
        inc     0x83                ; select adjacent ADC/control address       [BYTE]
        movx    A,@DPTR             ; read second sampled value                  [BYTE]
        subb    A,R4                 ; compare feedback against target/table value [BYTE]
        jc      ext1_error_low       ; branch to low-side error handling            [BYTE]
        mov     @R1,A               ; store the sampled difference                [BYTE]
        mov     A,R5                ; restore first sampled value                 [BYTE]
        mov     R5,0xF0             ; move profile value into R5                  [BYTE]
        mul     AB                  ; multiply sampled value by profile value    [BYTE]
        mov     R4,0xF0             ; preserve high product byte                  [BYTE]
        mov     A,@R1               ; reload stored difference                    [BYTE]
        mov     0xF0,R5             ; move second factor into B                   [BYTE]
        mul     AB                  ; multiply difference by second factor       [BYTE]
        add     A,R4                ; combine product components                  [BYTE]
        rl      A                   ; scale computed output                       [BYTE]
        rl      A                   ; scale computed output again                 [BYTE]
        anl     A,#0x03              ; clamp/quantize output magnitude              [BYTE]
        rr      A                   ; restore scaled value alignment               [BYTE]
        mov     R4,A                ; retain scaled magnitude                      [BYTE]
        mov     A,0xF0              ; load high product byte                      [BYTE]
        addc    A,#0x00             ; propagate carry into high byte               [BYTE]
        rlc     A                   ; test for upper-range saturation              [BYTE]
        jc      ext1_limit_high     ; clamp positive overflow                     [BYTE]
        rlc     A                   ; continue range test                          [BYTE]
        orl     A,R4                ; merge magnitude and direction bits            [BYTE]
        jc      ext1_limit_high     ; clamp encoded overflow                       [BYTE]
        mov     @R1,A               ; store calculated axis value                   [BYTE]
        anl     0x09,#0x57          ; retain relevant axis-state bits               [BYTE]
        subb    A,@R1               ; compare calculated and stored values          [BYTE]
        jnz     ext1_update_state   ; update state when value changed               [BYTE]
        mov     R4,#0x00            ; zero adjustment for equal values              [BYTE]
        sjmp    ext1_output_state   ; continue with output encoding                 [BYTE]

; Low-side clamp: the comparison underflowed, so force the working value to
; zero and continue with the negative-direction error/profile calculation.
ext1_error_low:
        mov     @R1,#0x00            ; clamp low-side value                         [BYTE]
        mov     R4,#0x08             ; record negative-direction code               [BYTE]
        subb    A,#0xF9              ; calculate low-side error magnitude            [BYTE]
        mov     R6,A                 ; save error magnitude                         [BYTE]
        jz      ext1_small_error     ; zero/small error uses minimum profile         [BYTE]
        jc      ext1_small_error     ; underflow uses minimum profile                [BYTE]
        sjmp    ext1_profile         ; continue with profile lookup                 [BYTE]

; High-side clamp: the calculated value overflowed the supported range, so
; saturate the working value at 0xFF and select the positive-direction code.
ext1_limit_high:
        mov     @R1,#0xFF            ; clamp high-side value                        [BYTE]
        mov     R4,#0x04             ; record positive-direction code               [BYTE]
; Small-error path: use the minimum nonzero profile entry and its marker before
; entering the common profile selection logic.
ext1_small_error:
        mov     A,#0x01              ; minimum nonzero profile index                [BYTE]
        mov     R6,#0x0A             ; retain small-error marker                    [BYTE]
        sjmp    ext1_profile        ; continue with profile lookup                 [BYTE]

; Changed-error path: derive the direction code from the subtraction carry and
; normalize negative values to a magnitude before selecting the profile.
ext1_update_state:
        jc      ext1_negative_error  ; branch for negative error                    [BYTE]
        mov     R4,#0x04             ; positive-direction code                      [BYTE]
        sjmp    ext1_profile_sign    ; normalize profile sign                      [BYTE]
; Negative-error normalization: convert the error magnitude to two's complement
; and record the negative motor-direction code.
ext1_negative_error:
        cpl     A                    ; two's-complement error magnitude            [BYTE]
        inc     A                    ; complete two's complement                   [BYTE]
        mov     R4,#0x08             ; negative-direction code                      [BYTE]
; Profile-sign join: compare the normalized error with the small-error threshold
; and route large values through the common profile path.
ext1_profile_sign:
        cjne    A,#0x0A,ext1_profile ; compare against small-error threshold         [BYTE]
; Profile threshold path: select the minimum profile when the comparison carry
; indicates that the error is outside the directly indexed profile range.
ext1_profile:
        jnc     ext1_small_error     ; saturate profile when threshold is exceeded   [BYTE]
; Profile lookup: fetch the speed/direction entry and use its marker bit to
; update the active-axis mask before preparing the motor state.
ext1_output_state:
        mov     R6,A                 ; save profile index                           [BYTE]
        add     A,#0x94              ; index inline speed/direction table           [BYTE]
        movc    A,@A+PC              ; read speed/direction profile entry           [BYTE]
        jbc     0xE0.7,ext1_set_axis ; consume table direction/active marker         [BYTE]
        sjmp    ext1_output          ; proceed without changing active mask         [BYTE]
; Active-axis update: merge the profile's axis mask into the active-axis flags
; while preserving the rotating current-axis mask.
ext1_set_axis:
        xch     A,0x22               ; exchange profile mask with current axis mask  [BYTE]
        orl     0x21,A               ; mark selected axis active                     [BYTE]
        xch     A,0x22               ; restore current axis mask                    [BYTE]

; Output gate: skip motor-state work unless the axis subsystem is enabled.
ext1_output:
        jb      0x20.0,ext1_motion   ; axis subsystem enabled?                      [BYTE]
        ajmp    ext1_advance         ; skip control when motion is disabled          [BYTE]

; Motion-state update: combine the profile command with the selected axis's
; existing state and choose the speed/direction encoding branch.
ext1_motion:
        mov     R5,A                 ; preserve encoded profile value               [BYTE]
        dec     @R0                  ; update per-axis motion counter               [BYTE]
        mov     A,@R0                ; load per-axis state                         [BYTE]
        anl     A,#0x0F              ; isolate low state nibble                    [BYTE]
        jnz     ext1_write_output    ; nonzero state goes directly to output        [BYTE]
        mov     A,R5                 ; restore encoded profile value               [BYTE]
        orl     A,@R0                ; merge it with existing state               [BYTE]
        cjne    R6,#0x00,ext1_speed_case ; branch for nonzero profile               [BYTE]
        sjmp    ext1_write_state     ; zero profile uses the current state          [BYTE]
; Speed-case dispatch: distinguish the special low-speed profile from the normal
; direction encoding path.
ext1_speed_case:
        cjne    R6,#0x01,ext1_direction_case ; select special profile case           [BYTE]
        jnb     0xE0.5,ext1_speed_case_2    ; test encoded profile bit               [BYTE]
        add     A,#0x03              ; apply special speed increment                 [BYTE]
        sjmp    ext1_write_state     ; store resulting state                         [BYTE]
; Direction encoding: place the direction code in the high nibble and combine
; it with the calculated speed/profile value.
ext1_direction_case:
        mov     A,R4                 ; load direction code                          [BYTE]
        swap    A                    ; move direction into output nibble             [BYTE]
        orl     A,R5                 ; combine direction and speed                  [BYTE]
        sjmp    ext1_write_state     ; store resulting state                         [BYTE]
; Alternate speed case: apply the secondary speed increment when its profile bit
; is set, then continue to direction handling.
ext1_speed_case_2:
        jnb     0xE0.4,ext1_speed_case_3 ; test alternate speed bit                 [BYTE]
        add     A,#0x02              ; apply alternate speed increment                [BYTE]
; Direction test: select the special direction update or retain the existing
; state when the profile does not request a direction change.
ext1_speed_case_3:
        cjne    R4,#0x04,ext1_direction_check ; test direction encoding               [BYTE]
        jb      0xE0.6,ext1_direction_set   ; select direction update                 [BYTE]
        sjmp    ext1_state_done      ; retain state when direction is inactive        [BYTE]
; Profile-marker check: only enter the direction update when the profile marker
; bit is set.
ext1_direction_check:
        jnb     0xE0.7,ext1_state_done ; retain state when profile marker is clear      [BYTE]
; Direction update: address the per-axis workspace and apply the special output
; encoding used for the 0x0F state.
ext1_direction_set:
        mov     0x09,R0              ; form axis-state comparison address             [BYTE]
        xrl     0x09,#0x70           ; map axis base to 0x78+axis workspace            [BYTE]
        cjne    @R1,#0x0F,ext1_write_state ; skip special encoding unless state is 0x0F [BYTE]
        anl     A,#0xC0              ; preserve direction bits                       [BYTE]
        orl     A,#0x03              ; add minimum drive code                        [BYTE]
        sjmp    ext1_write_state     ; store resulting state                         [BYTE]
; State-completion path: transform the retained state into the stop/hold output
; form before writing it back to the axis workspace.
ext1_state_done:
        xrl     A,#0xC0              ; invert direction-related output bits           [BYTE]
        add     A,#0x0E              ; apply stop/hold output offset                  [BYTE]
; State write setup: select the per-axis workspace and initialize the output
; sentinel used by the following increment.
ext1_write_state:
        mov     0x09,R0              ; select axis state workspace                   [BYTE]
        xrl     0x09,#0x70           ; map R0 to 0x78+axis                           [BYTE]
        mov     @R1,#0xFF            ; initialize output-state sentinel              [BYTE]
; Output increment: advance the encoded per-axis output value for table lookup.
ext1_write_output:
        inc     @R1                  ; advance output-state value                   [BYTE]
; State commit and port selection: store the axis state, then choose Port A or
; Port C and its shadow register for the motor output update.
ext1_write_state_value:
        mov     @R0,A                ; update per-axis state/current value
        mov     A,R0                 ; reload axis workspace base                    [BYTE]
        jbc     0xE0.2,ext1_port_c  ; select Port C path for upper axes              [BYTE]
        mov     0x83,#0x50           ; axes 0..3 use 8255 Port A                    [BYTE]
        mov     R1,#0x4E             ; select Port A shadow                         [BYTE]
        sjmp    ext1_apply_output    ; apply encoded output                         [BYTE]
; Upper-axis port path: prepare the Port C output selection and offset.
ext1_port_c:
        mov     R4,#0x00             ; clear alternate output offset                 [BYTE]
        mov     A,R0                 ; reload axis workspace base                    [BYTE]
        jnb     0xE0.2,ext1_port_a  ; retain Port A path if selector is clear         [BYTE]
        clr     0xE0.2               ; clear selector before Port C output             [BYTE]
; Port C selection join: select the Port C device and its output shadow.
ext1_port_a:
        mov     0x83,#0x52           ; axes 4..5 use 8255 Port C                    [BYTE]
        mov     R1,#0x4F             ; select Port C shadow                         [BYTE]
; Motor output commit: combine the table encodings with the selected Port A/C
; shadow, write the result to the 8255, and test the remaining move mask.
ext1_apply_output:
        mov     R5,A                 ; preserve axis/output table index               [BYTE]
        movc    A,@A+PC              ; read first motor output encoding [INFER]       [BYTE]
        anl     A,@R1                ; mask existing Port A/C shadow                  [BYTE]
        mov     @R1,A                ; store masked motor shadow                      [BYTE]
        mov     A,R4                 ; load direction/output offset                  [BYTE]
        add     A,R5                 ; form second output table index                [BYTE]
        movc    A,@A+PC              ; read second motor output encoding [INFER]      [BYTE]
        orl     A,@R1                ; merge encoded output with shadow               [BYTE]
        mov     @R1,A                ; update Port A/C output shadow                 [BYTE]
        movx    @DPTR,A              ; write motor command to 8255 [HW][BYTE]
        mov     A,0x22               ; load current axis mask                      [BYTE]
        anl     A,0x2B               ; clear completed axes from need-move mask      [BYTE]
        jnz     ext1_advance         ; advance when another axis remains active      [BYTE]

; Round-robin exit: rotate the axis mask, select the next ADC channel, restore
; the interrupted CPU context, and return from EXT1.
ext1_advance:
        mov     A,0x22               ; load current rotating axis mask              [BYTE]
        rl      A                    ; rotate mask to next axis                     [BYTE]
        mov     0x22,A               ; save next-axis mask                          [BYTE]
        mov     A,R0                 ; load current axis workspace base             [BYTE]
        inc     A                    ; advance to next axis                         [BYTE]
        anl     A,#0x07              ; wrap axis selector                           [BYTE]
        mov     0x83,#0x58           ; select ADC channel device                    [BYTE]
        movx    @DPTR,A              ; select next ADC channel [HW][BYTE]
        orl     A,#0x48              ; convert selector to 0x48+axis base           [BYTE]
        mov     R0,A                 ; save next axis speed/state base              [BYTE]
        mov     A,R2                 ; restore interrupted accumulator              [BYTE]
        pop     0xD0                  ; restore interrupted PSW                     [BYTE]
        reti                          ; return from External Interrupt 1            [BYTE]


;==============================================================================
; TIMER 0 TICK HANDLER  timer0_isr (0x0080)                       [BYTE][SIM]
;------------------------------------------------------------------------------
; Reached from the Timer 0 vector at 0x000B. Timer 0 is configured in mode 1
; during initialization, with TH0=0xE8 as the reload value; this handler also
; refreshes TL0=0x11 on every overflow. The resulting interrupt cadence depends
; on the 8031 timer-clock divider; the software prescaler below is byte-exact.
;
; The handler publishes timing events through bit-addressable RAM. The names
; below describe observed consumers, not undocumented hardware registers:
;   0x20.3  phase/timing toggle, also copied by the axis ISR [BYTE][SIM]
;   0x20.4  periodic axis/main-loop update request              [BYTE][SIM]
;   0x23.5  periodic timer event                                [BYTE][INFER]
;   0x23.6  slower motion/watchdog event                        [BYTE][SIM]
;   0x23.7  serial-timeout tick                                 [BYTE][SIM]
;------------------------------------------------------------------------------
        org     0x0080
timer0_isr:                         ; ISR1: Timer 0 overflow / system tick
        mov     0x8A,#0x11          ; TL0 = 0x11: reload low byte             [BYTE]
        mov     0x8C,#0xE8          ; TH0 = 0xE8: reload high byte            [BYTE]
        setb    0x88.4              ; TR0 = 1: keep Timer 0 running          [BYTE]
        setb    0x23.7              ; publish timer tick / serial timeout    [BYTE]
        setb    0x23.4              ; mark timer phase state                 [BYTE]
        cpl     0x20.3              ; toggle timing phase                    [BYTE]
        jnb     0x20.3,timer0_slow  ; only set 0x20.4 on one phase           [BYTE]
        setb    0x20.4              ; request periodic main-loop update      [BYTE]
timer0_slow:
        djnz    0x1D,timer0_return  ; divide tick rate by 10                  [BYTE]
        mov     0x1D,#0x0A          ; restart the slow-event prescaler       [BYTE]
        setb    0x23.6              ; publish the slower motion event        [BYTE]
        setb    0x23.5              ; publish the slower timer event          [BYTE]
timer0_return:
        reti                         ; return from Timer 0 interrupt          [BYTE]


;==============================================================================
; INITIALIZATION SEQUENCE   (0x0600 -> main loop)
;------------------------------------------------------------------------------
; Reached from the reset vector. Brings up: warm-up delay, 8255 PPI, axis
; select, internal RAM clear, stack, external SRAM sizing/probe, program-area
; header, interrupt enables, then falls into the main loop.
; All opcodes below are [BYTE]-verified from the ROM image. Items describing
; run-time *behavior* (which probe branch is taken, measured baud, delay
; durations) are marked [SIM] where confirmed or [INFER] where still pending.
;==============================================================================
        org     0x0600
init_start:
;------------------------------------------------------------------------------
; (1) Power-on warm-up delay. Lets the hardware (8255, analog rails from the
;     MAX1044, ADC) settle before the CPU touches the bus.                   [BYTE]
;------------------------------------------------------------------------------
        mov     A,#0x78             ; A = 0x78 (120) outer delay seed
delay_warmup:
        djnz    R0,delay_warmup     ; spin down R0 (256 iterations)
        djnz    ACC,delay_warmup    ; decrement A, repeat -> long warm-up delay

;------------------------------------------------------------------------------
; (2) Poke the aux/axis-select device (DPH=0x48, 74LS138 Y2/Y3 region). Resets
;     that block to a known state before use.                               [BYTE]
;     Decode: A12=0,A11=1 -> Y2/Y3 (see EXTERNAL DEVICE MAP).               [HW]
;------------------------------------------------------------------------------
        mov     0x83,#0x48          ; DPH = 0x48 -> aux/axis-select block (Y2/Y3)
        movx    @DPTR,A             ; write A to device 0x48
        djnz    R0,$-1              ; short settle delay (rel FD -> back to 0x060A)
        djnz    R0,$                ; short settle delay (rel FE -> self)

;------------------------------------------------------------------------------
; (3) Configure the 8255 PPI: mode word then clear/preset the three ports.
;     Control = 0x80 -> Mode 0, Ports A, B, C all OUTPUT.                    [BYTE]
;------------------------------------------------------------------------------
        mov     0x83,#0x53          ; DPH = 0x53 -> 8255 CONTROL register
        mov     A,#0x80             ; 0x80 = 8255 control: mode 0, A/B/C = output
        movx    @DPTR,A             ; program 8255 -> all ports become outputs
        clr     A                   ; A = 0
        dec     0x83                ; DPH -> 0x52  = 8255 Port C
        movx    @DPTR,A             ; Port C = 0x00  (motor phase outputs off)
        dec     0x83                ; DPH -> 0x51  = 8255 Port B
        mov     A,#0xFF             ; A = 0xFF
        movx    @DPTR,A             ; Port B = 0xFF  (general digital out, [INFER] active-low idle)
        dec     0x83                ; DPH -> 0x50  = 8255 Port A
        clr     A                   ; A = 0
        movx    @DPTR,A             ; Port A = 0x00  (motor phase outputs off)

;------------------------------------------------------------------------------
; (4) Prime the ADC/feedback device (DPH=0x59, 74LS138 Y6/Y7 region) with 0x01.
;     0x59 => A8=1 selects ADC channel via ADD-A; write kicks the front end.
;     Decode: A12=1,A11=1 -> Y6/Y7 -> ADC (Y7 -> ADC pin 22).              [BYTE][HW]
;------------------------------------------------------------------------------
        mov     0x83,#0x59          ; DPH = 0x59 -> ADC/feedback device, channel A8=1
        mov     A,#0x01             ; A = 1
        movx    @DPTR,A             ; write 0x01 to ADC/feedback device

;------------------------------------------------------------------------------
; (5) Clear internal RAM 0x7F..0x01 and select register bank 0.             [BYTE]
;------------------------------------------------------------------------------
        mov     R0,#0x7F            ; R0 = 0x7F (top of internal RAM)
        clr     A                   ; A = 0 (fill value)
        mov     0xD0,A              ; PSW = 0  -> register bank 0, flags cleared
clear_ram_loop:
        mov     @R0,A               ; [R0] = 0
        djnz    R0,clear_ram_loop   ; walk down until R0 == 0 (0x00 left as-is)

;------------------------------------------------------------------------------
; (6) Stack pointer and two output shadow latches.                          [BYTE]
;------------------------------------------------------------------------------
        mov     0x81,#0x31          ; SP = 0x31 (stack grows above cleared vars)
        mov     0x47,#0xFF          ; RAM 0x47 = 0xFF  (display/LED latch shadow)
        mov     0x1F,#0xFF          ; RAM 0x1F = 0xFF  (digital-out shadow, Port B mirror)

;------------------------------------------------------------------------------
; (7) External SRAM probe / sizing. Read a cell, write its complement, read
;     back and compare to confirm working RAM and find the top page.
;     Probe window base = 0x8000 (DPH=0x80); fallback page 0xA0.           [BYTE]
;     [INFER] exact loop semantics/branch taken -> confirm with [SIM].
;------------------------------------------------------------------------------
        mov     DPTR,#0x8000        ; DPTR = 0x8000 -> external SRAM window
ram_probe:
        movx    A,@DPTR             ; read current SRAM cell
        cpl     A                   ; complement it
        movx    @DPTR,A             ; write complement back
        mov     R0,A                ; save expected value
        movx    A,@DPTR             ; read it back
        xrl     A,R0                ; A ^= expected -> 0 if RAM is good
        jz      ram_ok              ; branch if verify passed
        jbc     0x28.7,ram_done     ; if retry-flag already set, give up / done
        setb    0x28.7              ; set retry flag
        mov     0x83,#0xA0          ; retry using alternate SRAM page 0xA0
        sjmp    ram_probe           ; re-probe

ram_ok:
        mov     A,R0                ; recover expected value
        cpl     A                   ; restore ORIGINAL cell contents
        movx    @DPTR,A             ; write original back (non-destructive probe)
        mov     0x3E,0x83           ; RAM 0x3E = working SRAM page high byte
        mov     0x3F,0x3E           ; RAM 0x3F = copy of page
        inc     0x3F                ; RAM 0x3F = page + 1
        mov     0x28,#0x03          ; system-state flags 0x28 = 0x03
                                    ; [INFER] bit0,bit1 set (RAM present / program-loaded seed)

;------------------------------------------------------------------------------
; (8) Initialize / validate the program-area header in external SRAM.
;     Compares 8 bytes at offset 0xF0 against R0-indexed pattern; if any
;     differ, rewrites them and clears state flag 0x28.1.                   [BYTE]
;------------------------------------------------------------------------------
        mov     0x82,#0xF0          ; DPL = 0xF0 (header offset within page)
        mov     R0,#0x08            ; 8 header bytes to check
hdr_loop:
        movx    A,@DPTR             ; read header byte
        cjne    A,0x00,hdr_diff     ; compare with RAM[0x00] template byte
        sjmp    hdr_next            ; match -> keep
hdr_diff:
        mov     A,0x00              ; load template byte
        movx    @DPTR,A             ; write it into header
        clr     0x28.1              ; program-loaded flag = 0 (header was invalid)
hdr_next:
        inc     DPTR                ; next header byte
        djnz    R0,hdr_loop         ; repeat for all 8 bytes
        lcall   0x0800              ; [INFER] program-area init helper (program_init)

;------------------------------------------------------------------------------
; (9) Axis subsystem seed + start one feedback cycle via Ext-Int-1 path.    [BYTE]
;------------------------------------------------------------------------------
ram_done:
        mov     0x08,#0x48          ; RAM 0x08 (bank1 R0) = 0x48 axis base ptr
        mov     0x22,#0x01          ; 0x22 = axis rotation mask, start at axis 0 (bit0)
        mov     0x83,#0x58          ; DPH = 0x58 -> ADC/feedback (Y6/Y7), channel A8=0 [HW]
        clr     A
        movx    @DPTR,A             ; feedback select = 0 (axis 0 / ADD-A low)
        mov     0xA8,#0x84          ; IE = 0x84 -> EA=1, enable EX1 (axis servo int) [INFER exact mask]
        jb      0x22.0,$            ; wait until axis-0 mask bit clears (one ISR pass) [SIM to confirm]
        jnb     0x22.0,$            ; then wait until it is set again (sync)          [SIM to confirm]
        clr     0xA8.7              ; disable interrupts (EA=0) during next setup
        mov     R7,#0x06            ; 6 axes
        mov     R0,#0x58            ; src = feedback values (0x58..0x5D)
        mov     R1,#0x50            ; dst = current positions (0x50..0x55)

;------------------------------------------------------------------------------
; (10) Copy 6 feedback readings -> current-position array (seed positions from
;      wherever the arm physically is at power-up).                         [BYTE]
;------------------------------------------------------------------------------
copy_fb_loop:
        mov     A,@R0               ; A = feedback[R0]
        mov     @R1,A               ; current_pos[R1] = A
        inc     R0
        inc     R1
        djnz    R7,copy_fb_loop     ; repeat for 6 axes

;------------------------------------------------------------------------------
; (11) Preset the 6 axis speed/step entries (0x48..0x4D) to 0x01.          [BYTE]
;------------------------------------------------------------------------------
        mov     R7,#0x06            ; 6 axes
        mov     R0,#0x48            ; -> axis speed array 0x48..0x4D
        mov     A,#0x01             ; default speed = 1
speed_loop:
        mov     @R0,A               ; speed[R0] = 1
        inc     R0
        djnz    R7,speed_loop       ; repeat for 6 axes

;------------------------------------------------------------------------------
; (12) UART / Timer setup for serial comms.                                 [BYTE]
;      TMOD=0x21 (T1 mode2 = UART baud gen, T0 mode1), TCON=0,
;      SCON=0x50 (mode 1, 8-bit UART, REN=1). The baud-measure block below
;      clears Timer 0 (TL0/TH0); the Timer 1 reload (TH1) is derived later.  [BYTE]
;------------------------------------------------------------------------------
        mov     0x89,#0x21          ; TMOD = 0x21 -> T1 mode2 (baud gen), T0 mode1
        mov     0x88,#0x00          ; TCON = 0 (timers/int flags cleared)
        mov     0x98,#0x50          ; SCON = 0x50 -> UART mode 1, REN enabled
        jb      0xB0.0,baud_detect  ; if P3.0 == 1 -> auto-detect baud path
        mov     0xA8,#0x07          ; IE = 0x07 -> EX0+ET0+EX1 (fixed/fast path; ES not set here)
        setb    0x20.2              ; flag 0x20.2 = "baud ready"
        ajmp    init_finish         ; skip auto-detect, go finish init
;   NOTE: the fixed-baud path above enables EX0+ET0+EX1 but NOT the serial
;   interrupt (ES). The auto-detect path instead ends with MOV IE,#0x17 at
;   0x0739, which DOES set ES (serial) -> RS232 is interrupt-driven there.  [BYTE]

baud_detect:
        jb      0xB0.2,$+5          ; sample P3.2 [INFER: line-idle check]
        setb    0x20.2              ; flag 0x20.2 = "baud ready"
;------------------------------------------------------------------------------
; (12b) Baud-rate auto-detection: measure the width of an incoming serial
;       edge on P3.0 using TIMER 0 (TL0/TH0 cleared, SETB TR0 below), then
;       derive the Timer-1 reload (TH1) so the UART baud matches the host.
;       Full inner-loop math continues past 0x06B6; annotated at instruction
;       level below. Behavior (measured value) is [SIM]-pending.           [BYTE]
;------------------------------------------------------------------------------
baud_measure:
        clr     A
        mov     0x88,A              ; TCON = 0
        mov     0x8A,A              ; MOV TL0,A -> TL0 = 0 (0x8A = TL0, NOT TL1 @0x8B)
        mov     0x8C,A              ; MOV TH0,A -> TH0 = 0 (clear Timer 0 accumulator).
                                    ; NB: 0x8C = TH0, NOT TH1 (TH1 = 0x8D). Baud
                                    ; measurement times with Timer 0 (SETB TR0 below).
                                    ; Raw bytes: F5 8C = MOV 0x8C,A. [BYTE]
        mov     R0,#0x01
        jb      0xB0.0,$            ; wait for P3.0 to go low (start of edge)
        setb    0x8C                ; SETB TR0 -> start Timer 0 during baud measure
                                    ; NB: operand 0x8C here is the BIT address
                                    ; TCON.4 (=TR0), NOT the TH0 byte SFR @0x8C.
                                    ; Raw bytes: D2 8C = SETB bit 0x8C. [BYTE]
; ... (baud measurement inner loop continues; see 0x06C4..0x073B in ROM,
;      not fully annotated in this pass — flow returns/branches to init_finish)

;------------------------------------------------------------------------------
; (13) FINAL INIT: timer tick prescaler, Timer-1 reload, enable ints, kick
;      one feedback conversion, then fall into the main loop.               [BYTE]
;------------------------------------------------------------------------------
init_finish:
        mov     0x1D,#0x0A          ; RAM 0x1D = 10 -> Timer0 tick prescaler (/10)
        mov     0x8C,#0xE8          ; MOV TH0,#0xE8 -> Timer 0 reload (0x8C = TH0 byte SFR)
        setb    0x8C                ; SETB TR0 (=TCON.4) -> start Timer 0 (system tick).
                                    ; NB: same operand value 0x8C as the line above but
                                    ; here it is the BIT address TCON.4, not the TH0 byte.
                                    ; Raw bytes: 8C E8 = MOV TH0,#0xE8 ; D2 8C = SETB TR0. [BYTE]
        setb    0x20.0              ; flag 0x20.0 = axis subsystem enable
        clr     A
        mov     0x83,#0x58          ; DPH = 0x58 -> ADC/feedback (Y6/Y7), channel A8=0 [HW]
        movx    @DPTR,A             ; select axis 0 feedback (ADD-A low)
        setb    0xA8.7              ; EA = 1, global interrupts ON
; 074D:                 (falls through into main loop)
        ; ---> MAIN LOOP entry at 0x074D

;==============================================================================
; MAIN LOOP  (0x074D -> 0x07C7)                          [BYTE][SIM][HW]
;------------------------------------------------------------------------------
; The idle super-loop. It services motion/axis flags, then — gated by three
; Port-3 input lines — polls the teach-pendant keypad. All three P3 gate lines
; are conditioned by MM74C04N #1 (hardware/board/MM74C04N.md), which is why the
; board needs BOTH the Teachbox AND the RS-232 shorting connector installed to
; run (hardware/teachbox/README.md "Hardware requirements").
;
; THREE GATES that must be satisfied for the keypad ever to be scanned — each
; verified by tracing the PC in ucSim and forcing the pin state:            [SIM]
;
;   GATE 1  EMERGENCY-OFF (P3.2 / INT0).  If P3.2 is LOW the level-triggered
;           INT0 keeps vectoring to the emergency_off handler (0x0040), which
;           never returns to the loop. P3.2 must be HIGH.           [BYTE][SIM]
;
;   GATE 3  TEACHBOX-POLL ENABLE (P3.4 / T0).  At 0x07AB:
;               20 B4 16   JB  P3.4, tb_poll (0x07C4)
;           the keypad scanner is CALLED only when P3.4 (8031 pin 14, T0,
;           bit addr 0xB4) reads HIGH; otherwise the loop skips the poll. So
;           P3.4 must be HIGH.                                       [BYTE][SIM]
;           (GATE 2 — the INT1/ADC servo ISR appearing to hog the CPU — is not
;            a real gate: once GATE 3 passes, the loop reaches tb_poll on the
;            first pass even with INT1 active. It only *looked* like a block
;            while the CPU was trapped by GATE 1.)                      [SIM]
;
;   GATE 4  KEYPAD DEBOUNCE (in kbd_scan, 0x0C00).  Even with the scanner
;           called, a key is only ACCEPTED (→ kbd_handle) after it survives the
;           two-stage debounce. The accept path at 0x0C41 is guarded by
;               30 06 1B   JNB 0x20.6, ret_zero
;           so flag 0x20.6 ("ready for a new key") must be SET — and it is only
;           set by the key_release path (SETB 0x20.6) when the scanner first
;           sees NO key. So the required cadence is RELEASE → PRESS-and-HOLD:
;           a release sets 0x20.6, then a held key is accepted a few scan passes
;           later (≈3 passes / ~24k instructions in ucSim). Holding a key from
;           reset without a prior release leaves 0x20.6 clear and the key is
;           never dispatched.                                          [SIM]
;           (Verified: idle-release first → 0x20 bit6 set → press row3/grp2 →
;            kbd_handle reached at ~24000 stepped instructions.)
;
; SIM IMPLICATION: to exercise the real keypad path in ucSim you must present
; P3.2=1 and P3.4=1 (the "RS-232 shorting connector present" pin state) and
; HOLD the key across several scan passes. The `loopback` cl_hw module
; (simulator/ucsim-modules/loopback/) drives P3.2/P3.4 for exactly this reason.
;------------------------------------------------------------------------------
        org     0x074D
main_loop:
        clr     0xAF                ; C2 AF     EA = 0 (guard the flag section)
        setb    0xD4                ; D2 D4     PSW.4 = 1 (register bank 2)
        jnb     0x2F,ml_0782        ; 30 2F 2C  bit 0x25.7 (motion active?) clear -> skip
        ; ... (motion/axis servicing 0x0757..0x0781; annotated in a later pass)
ml_0782:
        ; ... (0x0782..0x07A8 clears/sets the housekeeping flags 0x20.x/0x28.x)
        clr     0xAF                ; C2 AF     EA = 0 again before the poll gate
        jb      0xB4,tb_poll        ; 20 B4 16  GATE 3: poll keypad only if P3.4 HIGH
        ; --- P3.4 LOW: skip the keypad poll this pass ---
        clr     A                   ; E4
        mov     0x26,A              ; F5 26
        mov     0x66,A              ; F5 66
        mov     0x67,0x3F           ; 85 3F 67
        lcall   0x0803              ; 12 08 03
        ; (0x07B7.. more housekeeping, then loops back to main_loop)
        ; falls around to the tb_poll call site below when P3.4 is HIGH:
        org     0x07C4
tb_poll:
        lcall   kbd_scan            ; 12 0C 00  scan the 5x5 matrix (enters 0x0C00)
        ; (jz/…: nonzero A -> kbd_handle at 0x0C80; see teachbox.annotated.asm)
;==============================================================================
; END OF ANNOTATED INITIALIZATION + MAIN-LOOP GATES
;   Remaining code (full motion servicing, ISRs, protocol, interpreter, the
;   teach-pendant editor) to be annotated in subsequent passes. 0xFF EPROM
;   padding is intentionally NOT annotated.
;==============================================================================
