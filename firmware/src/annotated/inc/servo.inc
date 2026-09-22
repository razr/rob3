;==============================================================================
; ROB3 FIRMWARE — AXIS SERVO data model
;   File: firmware/src/annotated/inc/servo.inc  (pairs with ext1_servo.asm)
;==============================================================================
;
; Per-axis IRAM arrays and the servo bit-masks used by the EXT1 axis-servo ISR
; (0x00C0) and the motion executor. The ADC that feeds this loop is reached via
; the MOVX windows in devices.inc (DEV_ADC_START / DEV_ADC_DATA); the raw
; feedback lands in FB_BASE below. See inc/system.inc for the full IRAM map.
;
;   Syntax: SDAS/ASxxxx (sdas8051). Addresses [BYTE]; direction polarity [INFER].
;==============================================================================

;------------------------------------------------------------------------------
; Per-axis arrays (N = axis 0..5; axis N is at BASE+N)
;------------------------------------------------------------------------------
TARGET_BASE     = 0x40          ; 0x40+N commanded/target position (what POS writes)
SPEED_BASE      = 0x48          ; 0x48+N speed / step rate
CURPOS_BASE     = 0x50          ; 0x50+N current position (host-view snapshot of feedback)
FB_BASE         = 0x58          ; 0x58+N ADC feedback (raw pot count, live)
DECEL_BASE      = 0x70          ; 0x70+N deceleration / ramp profile
ISRWS_BASE      = 0x78          ; 0x78+N per-axis ISR workspace / state

;------------------------------------------------------------------------------
; Motor output shadows (mirrored to 8255 Port A/C via MOVX)
;------------------------------------------------------------------------------
PORTA_SHADOW    = 0x4E          ; 8255 Port A output shadow (axes 0..3)
PORTC_SHADOW    = 0x4F          ; 8255 Port C output shadow (axes 4..5)

;------------------------------------------------------------------------------
; Servo mask bytes (in the 0x20..0x2F bit-addressable region)
;------------------------------------------------------------------------------
AXIS_ACTIVE     = 0x21          ; axis-active mask (one bit/axis; 0x3F = all)
AXIS_MASK       = 0x22          ; one-hot rotating PHASE mask (INT1 servo scheduler)
NEED_MOVE       = 0x2B          ; axis "needs to move" mask (cleared as each arrives)
MOVING          = 0x2C          ; axis "moving" mask
DIRECTION       = 0x2D          ; axis direction mask (1 = positive) [INFER polarity]

;------------------------------------------------------------------------------
; AXIS_MASK (0x22) one-hot phase selector — bits 0..5 = axes, 6/7 = phases
;------------------------------------------------------------------------------
AXIS_MASK_B0    = 0x10          ; 0x22.0  (init-handshake watch bit)
AXIS_MASK_B6    = 0x16          ; 0x22.6  timer-phase hand-off slot [INFER]
AXIS_MASK_B7    = 0x17          ; 0x22.7  ADC-result-read slot       [INFER]

; End of inc/servo.inc
