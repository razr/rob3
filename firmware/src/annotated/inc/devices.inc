;==============================================================================
; ROB3 FIRMWARE — MOVX external device windows
;   File: firmware/src/annotated/inc/devices.inc
;==============================================================================
;
; The value written to DPH before a `movx @DPTR,A` selects the external device
; via the 74LS138 address decoder (real CPU selects are B=A11, C=A12; A14/A15
; gate peripheral space vs external SRAM). See hardware/board/74LS138.md and
; the EXTERNAL DEVICE MAP in vectors.asm.  [HW]
;
; Syntax: SDAS/ASxxxx (sdas8051). Include with `.include "inc/devices.inc"`.
;==============================================================================

DEV_AUX_LATCH   = 0x48          ; aux / axis-select latch (74LS138 Y2/Y3)
DEV_8255_PA     = 0x50          ; 8255 Port A  (motor drive, axes 0..3)
DEV_8255_PB     = 0x51          ; 8255 Port B  (teachbox LED/row latch)
DEV_8255_PC     = 0x52          ; 8255 Port C  (motor drive, axes 4..5)
DEV_8255_CTRL   = 0x53          ; 8255 control word
DEV_ADC_START   = 0x58          ; ADC channel-select + START (A8 = ADD-A)
DEV_ADC_DATA    = 0x59          ; ADC converted-data read (EOC result)
DEV_SRAM        = 0x80          ; external HM6264 SRAM window base (program store)
DEV_SRAM_ALT    = 0xA0          ; external SRAM probe fallback page

; End of inc/devices.inc
