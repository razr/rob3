;==============================================================================
; ROB3 FIRMWARE — TEACH-PENDANT / EDITOR data model
;   File: firmware/src/annotated/inc/teachbox.inc  (pairs with teachbox.asm)
;==============================================================================
;
; Keypad scanner, LED/display, debounce, and the POS-digit editor state used by
; the teachbox code (kbd_scan 0x0C00, kbd_handle 0x0C80, pos_digit/pos_commit).
; The keypad columns are read on P1 (see inc/sfr.inc); the row strobe / LEDs go
; out via 8255 Port B (devices.inc DEV_8255_PB). See inc/system.inc for the map
; and the shared SYS_KEY_READY / SYS_KEY_PENDING flags in 0x20.
;
;   Syntax: SDAS/ASxxxx (sdas8051). Addresses [BYTE]; bit ROLES [INFER] noted.
;==============================================================================

;------------------------------------------------------------------------------
; Display / keypad scan bytes
;------------------------------------------------------------------------------
KBD_STROBE      = 0x46          ; current teach-pendant row-strobe pattern
LED_LATCH       = 0x47          ; LED / row display output latch (value driven out)
KBD_DEBOUNCE0   = 0x56          ; keypad debounce state / last accepted key index
KBD_DEBOUNCE1   = 0x57          ; keypad debounce / auto-repeat down-counter

;------------------------------------------------------------------------------
; POS-digit direct-entry accumulator (16-bit, high:low)
;------------------------------------------------------------------------------
ARG_ACC_LO      = 0x6D          ; numeric-arg accumulator low  byte
ARG_ACC_HI      = 0x6E          ; numeric-arg accumulator high byte

;------------------------------------------------------------------------------
; Editor mode / state bytes (in the 0x20..0x2F bit-addressable region)
;------------------------------------------------------------------------------
EDIT_MODE       = 0x29          ; editor mode / sub-state (key handler); 0x40 = POSITION
EDIT_STATE      = 0x2A          ; editor ERR / entry state

; EDIT_MODE (0x29) bits
EDIT_MODE_B3    = 0x4B          ; 0x29.3 two-digit entry mode [INFER] ((0x29-0x20)*8+3)

; EDIT_STATE (0x2A) bits
EDIT_ERR_B5     = 0x55          ; 0x2A.5 editor ERR/entry bit [INFER]
EDIT_ERR_B6     = 0x56          ; 0x2A.6 editor ERR/entry bit [INFER]
EDIT_ERR_B7     = 0x57          ; 0x2A.7 editor ERR/entry bit [INFER]
; (note: 0x2A.6/.7 bit addresses 0x56/0x57 numerically equal the debounce bytes)

; End of inc/teachbox.inc
