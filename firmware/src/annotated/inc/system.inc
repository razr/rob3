;==============================================================================
; ROB3 FIRMWARE — SYSTEM / IRAM MEMORY MAP + shared flag bits
;   File: firmware/src/annotated/inc/system.inc
;==============================================================================
;
; THE authoritative internal-RAM map for the ROB3 8031 firmware, plus the
; shared system flag bytes and their bit definitions. Subsystem-owned bytes
; (per-axis arrays, teachbox editor state, serial buffers, program state) are
; declared in their own includes (servo.inc / teachbox.inc / serial.inc /
; program.inc); this file is the single place that documents the WHOLE 0x00..
; 0x7F layout and owns the cross-cutting system flags (0x20, 0x23, 0x28).
;
;   Syntax: SDAS/ASxxxx (sdas8051) `NAME = value`.
;   Source: docs/reverse_engineering_notes.md (IRAM map) + the rob3-firmware-map
;   skill. Addresses are [BYTE]; a few bit ROLES are [INFER] and marked.
;
; BIT-ADDRESS CONVENTION (8051):
;   Bit-addressable RAM is 0x20..0x2F. The bit address of byte B, bit b is
;       bitaddr = (B - 0x20) * 8 + b
;   e.g. 0x22.7 -> (0x22-0x20)*8 + 7 = 0x17. So `jb 0x22.7` and `jb 0x17` are
;   the same instruction. The *_Bn equates below are these numeric bit addrs.
;   Byte-vs-bit reminder: `JB 0x22.0` tests BIT 0 of the one-hot mask byte 0x22,
;   NOT RAM byte 0x22 as a whole.
;==============================================================================

;==============================================================================
; INTERNAL RAM MAP (0x00..0x7F)                                           [BYTE]
;------------------------------------------------------------------------------
;   0x00  Register bank 0 (R0-R7), main
;   0x08  Register bank 1 (R0-R7), ISR / axis base register
;   0x10  Register bank 2, serial
;   0x18  Register bank 3 / general — also serial timeout counter
;   0x19  Axis watchdog timer
;   0x1A-1B  Wait counters (program execution)
;   0x1D  Timer 0 prescaler (/10)                       -> DEC_CONST_10
;   0x1F  Digital-output latch shadow (Port B mirror)   -> DOUT_SHADOW
;   0x20-2F  BIT-ADDRESSABLE FLAG AREA (see below)
;   0x30-31  DPTR shadow for serial TX (program up/download)
;   0x3E  ext-RAM program page hi (base of programs)    -> PROG_PAGE  (program.inc)
;   0x3F  ext-RAM program page hi + 1                   -> PROG_PAGE1 (program.inc)
;   0x40-45  Axis target positions (6)                  -> TARGET_BASE (servo.inc)
;   0x46  Teach-pendant row-strobe / display register   -> KBD_STROBE (teachbox.inc)
;   0x47  LED / display output value                    -> LED_LATCH  (teachbox.inc)
;   0x48-4D  Axis speed / step parameters (6)           -> SPEED_BASE (servo.inc)
;   0x4E-4F  DC-motor output shadows (Port A / Port C)  -> PORTA/ C_SHADOW (servo.inc)
;   0x50-55  Axis current positions (6)                 -> CURPOS_BASE (servo.inc)
;   0x56-57  Keyboard debounce state                    -> KBD_DEBOUNCE0/1 (teachbox.inc)
;   0x58-5D  Axis feedback values from ADC (6)          -> FB_BASE (servo.inc)
;   0x5E-5F  Additional digital-I/O state (hidden DI cmds)
;   0x60-65  Serial RX buffer (6 axis bytes)            -> RX_BUF (serial.inc)
;   0x66-67  Program counter (offset in ext-RAM)        -> PC_LO/PC_HI (program.inc)
;   0x68-6E  Serial command buffer                      -> (serial.inc)
;   0x6D-6E  POS digit-entry accumulator (aliases 0x6D/0x6E) -> ARG_ACC_LO/HI (teachbox.inc)
;   0x70-75  Axis deceleration profile (6)              -> DECEL_BASE (servo.inc)
;   0x76-77  Program memory end pointer                 -> (program.inc)
;   0x78-7F  Axis state-machine workspace (INT1 ISR)    -> ISRWS_BASE (servo.inc)
;==============================================================================

;------------------------------------------------------------------------------
; Misc system scratch bytes (non-bit-addressable)
;------------------------------------------------------------------------------
SER_TIMEOUT     = 0x18          ; serial timeout counter (reloaded by RX ISR)
AXIS_WATCHDOG   = 0x19          ; axis motion watchdog timer
WAIT_CTR_LO     = 0x1A          ; program wait counter lo
WAIT_CTR_HI     = 0x1B          ; program wait counter hi
DEC_CONST_10    = 0x1D          ; Timer0 tick prescaler / decimal-10 scratch
DOUT_SHADOW     = 0x1F          ; digital-out latch shadow (8255 Port B mirror)
TXDPTR_SHADOW   = 0x30          ; DPTR shadow for serial TX (0x30:0x31)

;==============================================================================
; BIT-FLAG BYTES (0x20..0x2F, bit-addressable)                  [BYTE]/[INFER]
;------------------------------------------------------------------------------
; Byte owners: 0x20/0x23/0x28 are cross-cutting SYSTEM flags (defined here).
; 0x21/0x22/0x2B/0x2C/0x2D are servo masks (servo.inc); 0x24/0x25/0x26/0x27 are
; serial/program state (serial.inc / program.inc); 0x29/0x2A are the editor
; (teachbox.inc). The bytes are all listed in the IRAM MAP above; each owner
; include defines that byte's symbol and its bit names.
;------------------------------------------------------------------------------

; -- 0x20  SYSTEM FLAGS --------------------------------------------------------
SYS_FLAGS       = 0x20
SYS_AXIS_ENABLE = 0x00          ; 0x20.0 axis subsystem enable                 [BYTE]
SYS_KBD_EVENT   = 0x01          ; 0x20.1 keyboard-event flag                   [BYTE]
SYS_BAUD_DET    = 0x02          ; 0x20.2 baud detected / "baud ready"          [BYTE]
SYS_TIMER_TGL0  = 0x03          ; 0x20.3 timer phase toggle (Timer0 cpl)       [BYTE]
SYS_TIMER_REQ   = 0x04          ; 0x20.4 periodic main-loop update request     [BYTE]
SYS_KEY_PENDING = 0x05          ; 0x20.5 new-key-press pending (scanner)        [INFER]
SYS_KEY_READY   = 0x06          ; 0x20.6 "ready for a new key" (set on release) [BYTE][SIM]

; -- 0x23  TIMER EVENT FLAGS ---------------------------------------------------
TMR_PHASE       = 0x23
TMR_ACK_REQ     = 0x19          ; 0x23.1 serial R (ack-request) latch          [BYTE]
TMR_PHASE_B3    = 0x1B          ; 0x23.3 published timer phase                 [BYTE]
TMR_PHASE_B4    = 0x1C          ; 0x23.4 incoming timer phase                  [BYTE]
TMR_EVT_SLOW2   = 0x1D          ; 0x23.5 slower timer event                    [BYTE][INFER]
TMR_EVT_MOTION  = 0x1E          ; 0x23.6 slower motion / watchdog event        [BYTE][SIM]
TMR_EVT_SERIAL  = 0x1F          ; 0x23.7 serial-timeout tick                   [BYTE][SIM]

; -- 0x28  SYSTEM STATE FLAGS (program / motion) ------------------------------
STATE_FLAGS     = 0x28
STATE_RAM_OK    = 0x40          ; 0x28.0 SRAM-present / probe-retry latch       [INFER]
STATE_PROG_LOAD = 0x41          ; 0x28.1 program-loaded                         [BYTE]
STATE_RUNNING   = 0x42          ; 0x28.2 program running                        [INFER]
STATE_MOTION    = 0x43          ; 0x28.3 motion active                          [INFER]
STATE_COND      = 0x44          ; 0x28.4 conditional / IF pending               [INFER]
STATE_B7        = 0x47          ; 0x28.7 SRAM-probe retry flag [INFER]
                                ;        (bit addr 0x47 == LED_LATCH byte 0x47)

; End of inc/system.inc
