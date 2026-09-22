;==============================================================================
; ROB3 FIRMWARE — RS-232 SERIAL data model
;   File: firmware/src/annotated/inc/serial.inc  (pairs with rs232.asm)
;==============================================================================
;
; RS-232 binary-protocol workspace used by the UART ISR (0x0300), the command
; dispatch (rx_dispatch 0x03A9) and the TX helper (0x0541). The UART SFRs
; (SCON/SBUF/TH1) live in inc/sfr.inc; the ETX frame terminator is 0x03. See
; inc/system.inc for the IRAM map and the ack-request latch (0x23.1).
;
;   Syntax: SDAS/ASxxxx (sdas8051). Addresses [BYTE]; protocol SEMANTICS [INFER].
;==============================================================================

;------------------------------------------------------------------------------
; Serial state bytes (in the 0x20..0x2F bit-addressable region)
;------------------------------------------------------------------------------
RX_FLAGS        = 0x24          ; serial RX state-machine flags
TX_FLAGS        = 0x25          ; serial TX state-machine flags

; TX_FLAGS (0x25) bits (observed)
TX_MODE_B1      = 0x29          ; 0x25.1 TX-buffer mode  [INFER] ((0x25-0x20)*8+1)
TX_ARM_B3       = 0x2B          ; 0x25.3 reset-ACK arm   [INFER]
TX_LAST_B4      = 0x2C          ; 0x25.4 last-byte flag  [INFER]
TX_ACK_B7       = 0x2F          ; 0x25.7 write-ACK       [INFER]

;------------------------------------------------------------------------------
; Serial buffers
;------------------------------------------------------------------------------
RX_BUF          = 0x60          ; RX buffer base (6 axis bytes 0x60..0x65)
CMD_BUF         = 0x68          ; command/response buffer (0x68..0x6E)

;------------------------------------------------------------------------------
; Protocol constants
;------------------------------------------------------------------------------
ETX             = 0x03          ; frame terminator (cjne A,#0x03 at 0x03AE)
ACK_INIT_OK     = 0x15          ; init-OK reply (auto-baud lock, 0x0733)
ACK_ALREADY     = 0xF1          ; already-init reply (idle-timeout, 0x0793)
ACK_DEFAULT     = 0xF3          ; default command ACK (dispatch default)

; End of inc/serial.inc
