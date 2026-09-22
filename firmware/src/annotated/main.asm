;==============================================================================
; ROB3 FIRMWARE — MAIN LOOP (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the idle super-loop entered at 0x074D by fall-through from
;                    init. Services motion/axis flags, then polls the teach-
;                    pendant keypad (gated by P3.2/P3.4). Part of the 1:1
;                    annotated source assembled by rob3.asm.
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. Unmarked instruction lines are [BYTE].
;
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
        ; org 0x074D
; main_loop:
        ; clr     0xAF                ; C2 AF     EA = 0 (guard the flag section)
        ; setb    0xD4                ; D2 D4     PSW.4 = 1 (register bank 2)
        ; jnb     0x2F,ml_0782        ; 30 2F 2C  bit 0x25.7 (motion active?) clear -> skip
        ; ... (motion/axis servicing 0x0757..0x0781; annotated in a later pass)
; ml_0782:
        ; ... (0x0782..0x07A8 clears/sets the housekeeping flags 0x20.x/0x28.x)
        ; clr     0xAF                ; C2 AF     EA = 0 again before the poll gate
        ; jb      0xB4,tb_poll        ; 20 B4 16  GATE 3: poll keypad only if P3.4 HIGH
        ; --- P3.4 LOW: skip the keypad poll this pass ---
        ; clr     A                   ; E4
        ; mov     0x26,A              ; F5 26
        ; mov     0x66,A              ; F5 66
        ; mov     0x67,0x3F           ; 85 3F 67
        ; lcall   0x0803              ; 12 08 03
        ; (0x07B7.. more housekeeping, then loops back to main_loop)
        ; falls around to the tb_poll call site below when P3.4 is HIGH:
        .org    0x074D

;==============================================================================
; THE IDLE SUPER-LOOP
;==============================================================================
main_loop:
        clr     IE_EA               ; C2 AF     EA = 0 (guard the flag section)
        setb    PSW_RS1             ; D2 D4     PSW.4 = 1 (register bank 2)

;--- motion servicing: if 0x25.7 (motion-active) is set ---
        jnb     0x2F,ml_no_motion   ; 30 2F 2C  0x25.7 clear -> skip motion
        mov     A,AXIS_ACTIVE       ; E5 21     A = axis-active mask (0x3F = all)
        cjne    A,#0x3F,ml_motion_tick ; B4 3F 0A  not all-active -> tick path
        mov     A,NEED_MOVE         ; E5 2B     A = "need-move" mask
        jnz     ml_no_motion        ; 70 23     still moving -> skip
        mov     C,TMR_ACK_REQ       ; A2 19     0x23.1 ack-request flag
        mov     0x2A,C              ; 92 2A     store into editor flags [INFER]
        sjmp    ml_motion_done      ; 80 1B
ml_motion_tick:
        jnb     TMR_EVT_MOTION,ml_no_motion ; 30 1E 1A  0x23.6 slow event? skip if not
        clr     TMR_EVT_MOTION      ; C2 1E     consume the event
        djnz    AXIS_WATCHDOG,ml_no_motion ; D5 19 15  watchdog not expired -> skip
        clr     SYS_AXIS_ENABLE     ; C2 00     0x20.0 disable axis subsystem
        clr     A                   ; E4
        mov     SFR_DPH,#DEV_8255_PA ; 75 83 50 DPH -> Port A
        movx    @DPTR,A             ; F0        Port A = 0 (motors off)
        mov     PORTA_SHADOW,A      ; F5 4E     clear shadow
        mov     SFR_DPH,#DEV_8255_PC ; 75 83 52 DPH -> Port C
        movx    @DPTR,A             ; F0        Port C = 0 (motors off)
        mov     PORTC_SHADOW,A      ; F5 4F     clear shadow
        mov     R4,#0xF7            ; 7C F7     R4 = 0xF7 status/reply code [INFER]
        setb    0x2B                ; D2 2B     set bit 0x25.3 (TX flag) [INFER]
ml_motion_done:
        clr     0x2F                ; C2 2F     clear 0x25.7 (motion-active done)

;--- serial housekeeping ---
ml_no_motion:
        jnb     0x18,ml_no_serial   ; 30 18 02  bit 0x23.0 not set -> skip
        acall   0x0541              ; B1 41     call TX helper (rs232.asm)
ml_no_serial:
        jnb     TMR_EVT_SERIAL,ml_poll_gate ; 30 1F 0F  0x23.7 serial-timeout? skip if not
        clr     TMR_EVT_SERIAL      ; C2 1F     consume the tick
        jnb     0x22,ml_poll_gate   ; 30 22 0A  bit 0x24.2 (RX ready?) -> skip [INFER]
        djnz    SER_TIMEOUT,ml_poll_gate ; D5 18 07  timeout not expired -> skip
        anl     RX_FLAGS,#0xF0      ; 53 24 F0  reset RX state machine low nibble
        mov     R4,#0xF1            ; 7C F1     R4 = 0xF1 (reset-ACK reply)
        setb    0x2B                ; D2 2B     set bit 0x25.3 (arm TX)

;--- check gates, then poll teachbox or run program ---
ml_poll_gate:
        clr     PSW_RS1             ; C2 D4     PSW.4 = 0 (back to bank 0)
        lcall   0x0900              ; 12 09 00  motion executor gate (program.asm) [INFER]
        setb    IE_EA               ; D2 AF     EA = 1 (re-enable ints)
        jnb     SYS_TIMER_REQ,main_loop ; 30 04 AC  0x20.4 not set -> loop
        jnb     SYS_BAUD_DET,main_loop  ; 30 02 A9  baud not ready -> loop
        clr     SYS_TIMER_REQ       ; C2 04     consume the periodic request
        jb      STATE_MOTION,main_loop ; 20 43 A4  0x28.3 motion active -> loop
        clr     IE_EA               ; C2 AF     EA = 0

;--- GATE 3: P3.4 = HIGH -> poll the teachbox keypad ---
        jb      P3_T0,tb_poll       ; 20 B4 16  P3.4 HIGH -> scan keypad
        ; P3.4 LOW: skip keypad, run program path instead
        clr     A                   ; E4
        mov     PROG_EXEC_CTRL,A    ; F5 26     clear program exec control
        mov     PC_LO,A             ; F5 66     reset program PC low
        mov     PC_HI,PROG_PAGE1    ; 85 3F 67  PC high = body page
        lcall   0x0803              ; 12 08 03  call prog_prepare (program.asm)
        jnb     STATE_PROG_LOAD,ml_return ; 30 41 10  no program loaded -> skip
        mov     DOUT_SHADOW,#0xFF   ; 75 1F FF  idle the digital-out shadow
        orl     STATE_FLAGS,#0x0C   ; 43 28 0C  set 0x28.2/.3 (running+motion)
        sjmp    ml_return           ; 80 08

tb_poll:
        lcall   0x0C00              ; 12 0C 00  kbd_scan (teachbox.asm)
        jz      ml_return           ; 60 03     no key -> skip
        lcall   0x0C80              ; 12 0C 80  kbd_handle (teachbox.asm)

ml_return:
        setb    IE_EA               ; D2 AF     EA = 1
        ajmp    main_loop           ; E1 4D     back to top

;==============================================================================
; DIGITAL-OUTPUT WRITE HELPER (0x07D0)                                  [BYTE]
;   Called from the teachbox editor to set/clear/toggle/load bits in the
;   digital-out shadow (0x1F / Port B).  R2 = op (1=ORL, 2=ANL, 3=XRL, else=MOV),
;   R0 = mask/value, A = result written to 0x1F and Port B.
;==============================================================================
dout_write:
        anl     A,#0x03             ; 54 03     mask op selector (0..3)
        mov     R2,A                ; FA        R2 = op
        mov     A,DOUT_SHADOW       ; E5 1F     A = current shadow
        djnz    R2,dout_and         ; DA 03     op 1 -> ORL
        orl     A,R0                ; 48        A |= R0
        sjmp    dout_commit         ; 80 0B
dout_and:
        djnz    R2,dout_xor         ; DA 03     op 2 -> ANL
        anl     A,R0                ; 58        A &= R0
        sjmp    dout_commit         ; 80 06
dout_xor:
        djnz    R2,dout_load        ; DA 03     op 3 -> XRL
        xrl     A,R0                ; 68        A ^= R0
        sjmp    dout_commit         ; 80 01
dout_load:
        mov     A,R0                ; E8        A = R0 (direct load)
dout_commit:
        mov     0x7F,SFR_DPH       ; 85 83 7F  save DPH
        mov     SFR_DPH,#DEV_8255_PB ; 75 83 51  DPH -> 8255 Port B
        mov     DOUT_SHADOW,A       ; F5 1F     update shadow
        movx    @DPTR,A             ; F0        write to Port B
        mov     SFR_DPH,0x7F       ; 85 7F 83  restore DPH
        ret                         ; 22
