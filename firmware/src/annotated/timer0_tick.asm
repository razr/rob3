;==============================================================================
; ROB3 FIRMWARE — TIMER0 SYSTEM-TICK ISR (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the Timer 0 overflow / system-tick handler at 0x0080.
;                    Part of the 1:1 annotated source assembled by rob3.asm.
;                    (The EXT1 axis-servo ISR at 0x00C0 lives in ext1_servo.asm.)
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. Unmarked instruction lines are [BYTE].
;
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
        .org    0x0080
timer0_isr:                         ; Timer 0 overflow / system tick
        mov     SFR_TL0,#0x11       ; 75 8A 11  TL0 = 0x11 reload low         [BYTE]
        mov     SFR_TH0,#0xE8       ; 75 8C E8  TH0 = 0xE8 reload high        [BYTE]
        setb    TCON_TR0            ; D2 8C     TR0 = 1 keep Timer 0 running   [BYTE]
        setb    TMR_EVT_SERIAL      ; D2 1F     0x23.7 timer tick / ser-timeout [BYTE]
        setb    TMR_PHASE_B4        ; D2 1C     0x23.4 mark timer phase        [BYTE]
        cpl     SYS_TIMER_TGL0      ; B2 03     0x20.3 toggle timing phase     [BYTE]
        jnb     SYS_TIMER_TGL0,timer0_slow ; 30 03 02  set 0x20.4 on one phase [BYTE]
        setb    SYS_TIMER_REQ       ; D2 04     0x20.4 periodic update request [BYTE]
timer0_slow:
        djnz    DEC_CONST_10,timer0_return ; D5 1D 07  divide tick rate by 10  [BYTE]
        mov     DEC_CONST_10,#0x0A  ; 75 1D 0A  restart slow-event prescaler   [BYTE]
        setb    TMR_EVT_MOTION      ; D2 1E     0x23.6 slower motion event     [BYTE]
        setb    TMR_EVT_SLOW2       ; D2 1D     0x23.5 slower timer event      [BYTE]
timer0_return:
        reti                        ; 32        return from Timer 0 interrupt  [BYTE]



