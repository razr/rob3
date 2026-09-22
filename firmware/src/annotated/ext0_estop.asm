;==============================================================================
; ROB3 FIRMWARE — EXT0 / EMERGENCY-OFF ISR (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the External-Interrupt-0 handler at 0x0040 (INT0 = P3.2,
;                    active-LOW emergency-off). Part of the 1:1 annotated
;                    source assembled by rob3.asm.
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. Unmarked instruction lines are [BYTE].
;
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
        .org    0x0040
emergency_off:
        push    SFR_PSW             ; C0 D0     PUSH PSW
        setb    PSW_RS0             ; D2 D3     PSW.3 = 1 -> register bank 1
        mov     R2,A                ; FA        save A
        clr     A                   ; E4
        mov     R1,A                ; F9        R1 = 0 (DJNZ wraps -> 256 passes)
eo_kill:
        mov     SFR_DPH,#DEV_8255_PA ; 75 83 50 DPH = 0x50 -> 8255 Port A (5000H)
        clr     A                   ; E4
        movx    @DPTR,A             ; F0        Port A = 0 (motors axes 0..3 OFF)
        mov     SFR_DPH,#DEV_8255_PC ; 75 83 52 DPH = 0x52 -> 8255 Port C (5200H)
        movx    @DPTR,A             ; F0        Port C = 0 (motors axes 4..5 OFF)
        djnz    R1,eo_kill          ; D9 F5     hammer both ports to 0, 256x
eo_wait:
        mov     R1,#0x00            ; 79 00     reload the release-debounce count
eo_wait_spin:
        jnb     P3_INT0,eo_wait     ; 30 B2 FB  WHILE P3.2(INT0)==LOW: spin here
        djnz    R1,eo_wait_spin     ; D9 FB     require P3.2 HIGH for 256 counts
        mov     SFR_DPH,#DEV_8255_PA ; 75 83 50 restore Port A...
        mov     A,PORTA_SHADOW      ; E5 4E       from motor shadow byte 0x4E
        movx    @DPTR,A             ; F0
        mov     SFR_DPH,#DEV_8255_PC ; 75 83 52 restore Port C...
        mov     A,PORTC_SHADOW      ; E5 4F       from motor shadow byte 0x4F
        movx    @DPTR,A             ; F0
        mov     A,R2                ; EA        restore A
        pop     SFR_PSW             ; D0 D0     POP PSW
        jbc     STATE_MOTION,eo_setrow ; 10 43 03  bit 0x28.3: pending? -> reset row
        setb    SYS_KBD_EVENT       ; D2 01     else set 0x20.1 (keyboard-event flag)
        reti                        ; 32
eo_setrow:
        mov     LED_LATCH,#0xFF     ; 75 47 FF  idle the LED/row-strobe latch
        reti                        ; 32
;   Byte-exact (0x0040..0x0071):
;     c0 d0 d2 d3 fa e4 f9 75 83 50 e4 f0 75 83 52 f0
;     d9 f5 79 00 30 b2 fb d9 fb 75 83 50 e5 4e f0 75
;     83 52 e5 4f f0 ea d0 d0 10 43 03 d2 01 32 75 47
;     ff 32
;   CORRECTION HISTORY: the vector-table summary previously labelled
;   0x0003 -> 0x0040 as a "motor pulse ISR". That was wrong: 0x0040 is the
;   INT0 EMERGENCY-OFF handler (P3.2 active-LOW), verified [BYTE]+[SIM]+[HW].


