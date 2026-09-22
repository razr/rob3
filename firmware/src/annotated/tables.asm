;==============================================================================
; ROB3 FIRMWARE — SHARED LOOKUP TABLES (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the trailing constant/lookup table region at the tail of
;                    the ROM code (0x0FC5..0x0FDD). Part of the 1:1 annotated
;                    source assembled by rob3.asm.
;
; PROVENANCE: [BYTE]=ROM bytes. Unmarked lines are [BYTE].
;
;------------------------------------------------------------------------------
; TAIL: a stray RET, the 1<<n bit-weight table, and a 16-bit XRAM fetch helper.
;------------------------------------------------------------------------------
        .org    0x0FC5
        ret                         ; 22        stray RET (tail of prior routine) [BYTE]

bit_table:
        .db     0x01,0x02,0x04,0x08 ; 0x0FC6  1<<n weight table (0..3)          [BYTE]
        .db     0x10,0x20,0x40,0x80 ; 0x0FCA  1<<n weight table (4..7)          [BYTE]

; 16-bit XRAM fetch: read program pointer (0x6D), form DPTR = PROG_PAGE:index*2,
; load two bytes into 0x66:0x67.                                              [BYTE]
xram_fetch16:
        mov     A,ARG_ACC_LO        ; E5 6D     A = index (0x6D)
        rl      A                   ; 23        A <<= 1 (2-byte table entries)
        mov     SFR_DPL,A           ; F5 82     DPL = A
        mov     SFR_DPH,PROG_PAGE   ; 85 3E 83  DPH = program page (0x3E)
        movx    A,@DPTR             ; E0        A = XRAM[entry].lo
        mov     PC_LO,A             ; F5 66     0x66 = lo
        inc     DPTR                ; A3        next byte
        movx    A,@DPTR             ; E0        A = XRAM[entry].hi
        mov     PC_HI,A             ; F5 67     0x67 = hi
        ret                         ; 22        return                          [BYTE]
;==============================================================================

