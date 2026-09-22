;==============================================================================
; ROB3 FIRMWARE — 8051/8031 SFR + bit-address equates
;   File: firmware/src/annotated/inc/sfr.inc
;==============================================================================
;
; Standard MCS-51 special-function-register and bit addresses used by the
; annotated ROB3 listings. These are architecture constants (not ROB3-specific)
; but only the subset the firmware touches is defined here.
;
; Syntax: SDAS/ASxxxx (sdas8051) `NAME = value`. Include with
;   `.include "inc/sfr.inc"`.
;
; BIT-ADDRESS CONVENTION (8051):
;   For bit-addressable SFRs the bit address is (SFR base) + bit, e.g.
;   IE.7 (EA) = 0xA8 + 7 = 0xAF; TCON.4 (TR0) = 0x88 + 4 = 0x8C.
;   NOTE the recurring byte-vs-bit collision: the bit address 0x8C (TCON.4/TR0)
;   equals the byte address of TH0 (0x8C). Resolve by instruction (SETB/JB use
;   a bit address; MOV to the SFR uses the byte address).
;==============================================================================

;------------------------------------------------------------------------------
; SFR byte addresses
;------------------------------------------------------------------------------
SFR_P1          = 0x90          ; Port 1 (teachbox keypad columns)
SFR_P3          = 0xB0          ; Port 3 (INT0/INT1/RXD/TXD/T0/T1)
SFR_DPL         = 0x82          ; DPTR low
SFR_DPH         = 0x83          ; DPTR high (selects the MOVX device window)
SFR_TMOD        = 0x89          ; timer mode
SFR_TCON        = 0x88          ; timer control (TR0 = 0x88.4)
SFR_TL0         = 0x8A          ; Timer 0 low byte
SFR_TH0         = 0x8C          ; Timer 0 high byte (reload)
SFR_TL1         = 0x8B          ; Timer 1 low byte
SFR_TH1         = 0x8D          ; Timer 1 high byte (UART baud reload)
SFR_SCON        = 0x98          ; serial control
SFR_SBUF        = 0x99          ; serial data buffer
SFR_IE          = 0xA8          ; interrupt enable (EA = 0xA8.7)
SFR_SP          = 0x81          ; stack pointer
SFR_B           = 0xF0          ; B register (used as MUL/table scratch)
SFR_ACC         = 0xE0          ; accumulator (bit-addressable; .n used as scratch flags)
SFR_PSW         = 0xD0          ; program status word

;------------------------------------------------------------------------------
; SFR bit addresses
;------------------------------------------------------------------------------
PSW_RS0         = 0xD3          ; PSW.3 = register-bank select bit 0
PSW_RS1         = 0xD4          ; PSW.4 = register-bank select bit 1
IE_EA           = 0xAF          ; IE.7  global interrupt enable
TCON_TR0        = 0x8C          ; TCON.4 Timer-0 run (bit addr = 0x88+4; == TH0 byte 0x8C)
TCON_TR1        = 0x8E          ; TCON.6 Timer-1 run
SCON_RI         = 0x98          ; SCON.0 receive interrupt flag
P3_INT0         = 0xB2          ; P3.2 (INT0 / EMERGENCY-OFF, active LOW)
P3_INT1         = 0xB3          ; P3.3 (INT1 / ADC end-of-conversion)
P3_T0           = 0xB4          ; P3.4 (T0 / teachbox-poll gate)
P3_RXD          = 0xB0          ; P3.0 (RXD / baud-select strap)

; End of inc/sfr.inc
