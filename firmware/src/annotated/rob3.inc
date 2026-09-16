;==============================================================================
; ROB3 FIRMWARE — symbolic equates for the annotated disassembly
;   File: firmware/src/annotated/rob3.inc
;==============================================================================
;
; Named constants for the ROB3 8031 firmware data model, so the annotated
; listings can read `jb AXIS_MASK_B7, ...` and `mov FB_BASE+..` instead of raw
; magic numbers like `0x22.7` and `0x58`.
;
; Scope / status:
;   - This is DOCUMENTATION support for the *.annotated.asm files. The golden
;     byte-match build uses the .db transcriptions in simulator/*.a51 and does
;     NOT assemble the annotated listings, so nothing here affects that build.
;   - Syntax is SDAS/ASxxxx (sdas8051): `NAME = value`. Include with
;     `.include "rob3.inc"`.
;   - Names/addresses follow the rob3-firmware-map skill (the authoritative map).
;
; Provenance: addresses are [BYTE] (observed in the ROM); the human-readable
; ROLE of a few flag bits is [INFER] and marked as such below.
;
; BIT-ADDRESS CONVENTION (8051):
;   Bit-addressable RAM is 0x20..0x2F. The *bit address* of byte B, bit b is
;       bitaddr = (B - 0x20) * 8 + b
;   e.g. byte 0x22 bit 7  -> (0x22-0x20)*8 + 7 = 0x17. So `jb 0x22.7` and
;   `jb 0x17` (bit form) are the same instruction. The AXIS/flag *_Bn equates
;   below are given as these numeric bit addresses.
;==============================================================================


;------------------------------------------------------------------------------
; SFRs used by the servo / init (subset; standard 8051 addresses)
;------------------------------------------------------------------------------
SFR_P1          = 0x90          ; Port 1 (teachbox keypad columns)
SFR_P3          = 0xB0          ; Port 3 (INT0/INT1/RXD/TXD/T0/T1)
SFR_DPL         = 0x82          ; DPTR low
SFR_DPH         = 0x83          ; DPTR high (selects the MOVX device window)
SFR_TH0         = 0x8C          ; Timer 0 high byte (reload)
SFR_TL0         = 0x8A          ; Timer 0 low byte
SFR_TCON        = 0x88          ; timer control (TR0 = 0x88.4)
SFR_SCON        = 0x98          ; serial control
SFR_IE          = 0xA8          ; interrupt enable (EA = 0xA8.7)
SFR_B           = 0xF0          ; B register (used as MUL/table scratch)
SFR_ACC         = 0xE0          ; accumulator (bit-addressable; .n used as scratch flags)
SFR_PSW         = 0xD0          ; program status word
PSW_RS0         = 0xD3          ; PSW.3 = register-bank select bit 0
IE_EA           = 0xAF          ; IE.7 global interrupt enable (bit addr = 0xA8+7)
TCON_TR0        = 0x8C          ; TCON.4 Timer-0 run (bit addr = 0x88+4; note: numerically == TH0 byte 0x8C)

;------------------------------------------------------------------------------
; MOVX device windows — value written to DPH before `movx @DPTR,A` [HW]
;------------------------------------------------------------------------------
DEV_AUX_LATCH   = 0x48          ; aux / axis-select latch (74LS138 Y2/Y3)
DEV_8255_PA     = 0x50          ; 8255 Port A  (motor drive, axes 0..3)
DEV_8255_PB     = 0x51          ; 8255 Port B  (teachbox LED/row latch)
DEV_8255_PC     = 0x52          ; 8255 Port C  (motor drive, axes 4..5)
DEV_8255_CTRL   = 0x53          ; 8255 control word
DEV_ADC_START   = 0x58          ; ADC channel-select + START (A8 = ADD-A)
DEV_ADC_DATA    = 0x59          ; ADC converted-data read (EOC result)

;------------------------------------------------------------------------------
; Per-axis IRAM arrays (N = axis 0..5; axis N is at BASE+N)
;------------------------------------------------------------------------------
TARGET_BASE     = 0x40          ; 0x40+N commanded/target position (what POS writes)
SPEED_BASE      = 0x48          ; 0x48+N speed / step rate
CURPOS_BASE     = 0x50          ; 0x50+N current position (host-view snapshot of feedback)
FB_BASE         = 0x58          ; 0x58+N ADC feedback (raw pot count, live)
DECEL_BASE      = 0x70          ; 0x70+N deceleration / ramp profile
ISRWS_BASE      = 0x78          ; 0x78+N per-axis ISR workspace / state

;------------------------------------------------------------------------------
; Shared servo scratch / masks (bytes)
;------------------------------------------------------------------------------
SYS_FLAGS       = 0x20          ; system flags (see bits below)
AXIS_ACTIVE     = 0x21          ; axis-active mask (one bit/axis; 0x3F = all)
AXIS_MASK       = 0x22          ; one-hot rotating PHASE mask (INT1 servo scheduler)
TMR_PHASE       = 0x23          ; timer/phase hand-off bits (see bits below)
STATE_FLAGS     = 0x28          ; program/run/motion state [INFER on some bits]
EDIT_MODE       = 0x29          ; editor mode / sub-state
EDIT_STATE      = 0x2A          ; editor ERR / entry state
NEED_MOVE       = 0x2B          ; axis "needs to move" mask (cleared as each arrives)
MOVING          = 0x2C          ; axis "moving" mask
DIRECTION       = 0x2D          ; axis direction mask (1 = positive) [INFER polarity]
PORTA_SHADOW    = 0x4E          ; 8255 Port A output shadow (axes 0..3)
PORTC_SHADOW    = 0x4F          ; 8255 Port C output shadow (axes 4..5)

;------------------------------------------------------------------------------
; Bit addresses (byte 0x20..0x2F -> (byte-0x20)*8 + bit)
;------------------------------------------------------------------------------
; SYS_FLAGS (0x20)
SYS_AXIS_ENABLE = 0x00          ; .0 axis subsystem enable      (0x20.0)
SYS_KBD_EVENT   = 0x01          ; .1 keypad event               (0x20.1) [INFER]
SYS_BAUD_DET    = 0x02          ; .2 baud detected              (0x20.2) [INFER]

; AXIS_MASK (0x22) one-hot phase selector — bits 0..5 = axes, 6/7 = phases
AXIS_MASK_B0    = 0x10          ; 0x22.0  (init-handshake watch bit)
AXIS_MASK_B6    = 0x16          ; 0x22.6  timer-phase hand-off slot [INFER]
AXIS_MASK_B7    = 0x17          ; 0x22.7  ADC-result-read slot       [INFER]

; TMR_PHASE (0x23)
TMR_PHASE_B3    = 0x1B          ; 0x23.3  published phase
TMR_PHASE_B4    = 0x1C          ; 0x23.4  incoming timer phase

;------------------------------------------------------------------------------
; Teach-pendant / editor / display (used by teachbox.annotated.asm)
;------------------------------------------------------------------------------
DOUT_SHADOW     = 0x1F          ; digital-out latch shadow (8255 Port B)
KBD_STROBE      = 0x46          ; teach-pendant row strobe pattern
LED_LATCH       = 0x47          ; LED / row display output latch
KBD_DEBOUNCE0   = 0x56          ; keypad debounce state
KBD_DEBOUNCE1   = 0x57          ; keypad debounce state
DEC_CONST_10    = 0x1D          ; decimal constant (10) scratch used by digit entry

; SYS_FLAGS extra bits
SYS_KBD_EVENT_B = 0x01          ; 0x20.1 kbd-event flag (same as SYS_KBD_EVENT)
SYS_FLAG_B5     = 0x05          ; 0x20.5 [INFER]
SYS_FLAG_B6     = 0x06          ; 0x20.6 [INFER]

; EDIT_STATE (0x2A) bits
EDIT_ERR_B5     = 0x55          ; 0x2A.5 editor ERR/entry bit [INFER]
EDIT_ERR_B6     = 0x56          ; 0x2A.6 editor ERR/entry bit [INFER]
EDIT_ERR_B7     = 0x57          ; 0x2A.7 editor ERR/entry bit [INFER]
; (note: 0x2A.6/.7 bit addresses 0x56/0x57 numerically equal the debounce bytes)

; STATE_FLAGS (0x28)
STATE_B7        = 0x47          ; 0x28.7 [INFER] (bit addr == LED_LATCH byte 0x47)

; EDIT_MODE (0x29) bits
EDIT_MODE_B3    = 0x4B          ; 0x29.3 two-digit entry mode [INFER] (bit addr = (0x29-0x20)*8+3)

;------------------------------------------------------------------------------
; Program / serial workspace (used by main.annotated.asm)
;------------------------------------------------------------------------------
PROG_PAGE       = 0x3E          ; ext-RAM program page hi
PROG_PAGE1      = 0x3F          ; ext-RAM program page +1
PC_LO           = 0x66          ; program counter (ext-RAM offset) lo
PC_HI           = 0x67          ; program counter (ext-RAM offset) hi
ARG_ACC_LO      = 0x6D          ; numeric-arg (POS digit-entry) accumulator low byte
ARG_ACC_HI      = 0x6E          ; numeric-arg accumulator high byte
RX_BUF          = 0x60          ; serial RX buffer base (6 axis bytes 0x60..0x65)
DEV_SRAM        = 0xA0          ; external SRAM window (A15) [HW]

; End of rob3.inc
