;==============================================================================
; ROB3 FIRMWARE — RS-232 / UART SERIAL HANDLER (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the RS-232 UART interrupt
;                    service routine at 0x0300 and its transmit helper at
;                    0x0542. Companion to
;                      firmware/src/annotated/main.annotated.asm  (init + vectors
;                        + main loop; the serial VECTOR fall-through is there),
;                      firmware/src/annotated/ext1_axis_servo.annotated.asm,
;                      firmware/src/annotated/teachbox.annotated.asm,
;                    and the hardware docs under hardware/board/ (MM74C04N,
;                    M34004) and hardware/connectors/ (rs232.md).
;
; PROVENANCE TAGS
;   [BYTE] = decoded directly from the ROM bytes (one-off disasm51 labels
;            resolved to the real address; e.g. label jump_02FF == 0x0300).
;   [HW]   = confirmed against the hardware schematic docs (hardware/).
;   [SIM]  = confirmed by running the ROM in ucSim and observing state.
;   [INFER]= inferred from context; treat as a hypothesis to confirm.
;
;   DEFAULT: every instruction line below is [BYTE] (byte-exact from the ROM)
;   unless it carries a different tag. The CONTROL FLOW and register/RAM
;   accesses are [BYTE]. The higher-level PROTOCOL SEMANTICS (what each command
;   byte "means" to the host) are largely [INFER] — the ROM shows how the bytes
;   are dispatched and stored, not the documented host wire format. These are
;   marked [INFER] and cross-referenced to docs/reverse_engineering_notes.md
;   (the "Communication Protocol" section, itself [INFER]).
;
;==============================================================================
; HOW SERIAL IS REACHED  (see main.annotated.asm for the vector detail)
;------------------------------------------------------------------------------
; The 8051 SERIAL interrupt vector is 0x0023. In this ROM 0x0023 is 0xFF
; padding; execution falls through the 0xFF fillers to:
;
;       0x0035:  02 03 00     LJMP 0x0300      ; -> this handler          [BYTE]
;
; The serial interrupt (ES, IE.4) is enabled ONLY on the baud auto-detect
; path, where init executes  MOV IE,#0x17  at 0x0739 (ES+EX1+ET0+EX0). On the
; fixed-baud path init sets IE=0x07 (no ES), so RS-232 is not interrupt-driven
; there. P3.0 (RXD, conditioned by MM74C04N #1) selects which path init takes.
; [BYTE]  (P3.0 conditioning is [HW], see hardware/board/MM74C04N.md.)
;
; SERIAL PORT CONFIG (from init):  SCON=0x50 -> UART mode 1 (8-bit, 1 start,
;   1 stop), REN=1.  TMOD T1=mode2 (8-bit auto-reload) = the baud generator;
;   TH1 reload is derived by the baud-measure block in init.               [BYTE]
;
;==============================================================================
; WHAT THIS INTERRUPT DOES (plain English)                                 [INFER]
;------------------------------------------------------------------------------
; This is a single, re-entrant-per-byte UART ISR that implements BOTH ends of
; the ROB3 host binary protocol:
;
;   * RX side (SCON.0 = RI set): a byte arrived in SBUF. The handler feeds it
;     to a multi-state receive parser (state flags in bit-RAM 0x24 and the
;     0x28 "system state" byte). The FIRST byte of a frame is treated as a
;     COMMAND/header (its bits select an operation + an axis 0..5 or 0x07 =
;     "all"); subsequent bytes are payload accumulated into buffers at 0x60..
;     and 0x68.., or streamed into external SRAM (program upload).
;
;   * TX side (SCON.1 = TI set): the transmitter is ready for the next byte.
;     Before RETI the handler calls the TX helper at 0x0541 (jump_0541), which
;     sources the next response byte from whichever TX state is active
;     (buffer/register/SRAM stream) and writes it to SBUF.
;
;   Every byte also reloads a SERIAL TIMEOUT counter (RAM 0x18 = 0x14) and sets
;   the "byte-seen" flag 0x24.2. The Timer-0 system tick (via 0x23.7) decrements
;   0x18 in the MAIN LOOP; on expiry the RX state machine is reset AND a
;   reset-acknowledge byte 0xF1 is staged for transmit (see RESET-ACK below),
;   so a stalled/partial frame cannot wedge the parser and the host learns the
;   controller is alive. [BYTE][SIM]
;
; PROVENANCE: the RI/TI dispatch, SBUF read/write, timeout reload, and buffer
; addresses are [BYTE]. The following command/response behaviours were driven
; in ucSim (ucsim_51 0.9.9) and are now [SIM] (see the VERIFICATION section at
; the end for the exact stimuli and observed state):
;   - read-feedback copies 0x58..0x5D -> response buffer 0x69..0x6E, R3=7, TX
;     buffer mode 0x25.1 armed;
;   - the TX helper streams the buffer (R1++/R3--) then frames with ETX = 0x03;
;   - single-axis position write stores RX byte to 0x50+axis and arms ACK 0x25.7;
;   - the RESET-ACK path stages R4 = 0xF1 and arms 0x25.3.
; The higher-level HOST WIRE NAMES for each header (0x87 read-all, 0x67 set-all,
; 0x6N/0x7N per-axis, 0x81 block, 0x89..0x8F program download, 0x4N feedback)
; remain [INFER] except where a [SIM]/[HW] note upgrades them below. The bench
; handshake (send 0x20 after reset -> a flood of 0xF1, with 15 F3 embedded;
; gripper frame 05 FF 03) is documented + observed on real hardware in
; hardware/host/README.md and is tagged [HW]; it matches the [SIM] traces here.
;
;==============================================================================
; RAM / FLAG MAP USED BY THE SERIAL HANDLER                                [BYTE addrs]
;------------------------------------------------------------------------------
;   0x18        serial timeout counter (reloaded to 0x14 on every byte)
;   0x19        secondary timeout/retry counter (set 0x64 on some paths)
;   0x1F        Port B (digital-out) shadow, written via 0x07D0 helper
;   0x24.n      RX state-machine flags (0x24.0..0x24.4)                    [INFER roles]
;   0x25.n      TX state-machine flags (0x25.1..0x25.7)                    [INFER roles]
;   0x23.0      "TX-armed / response pending" tick flag                    [INFER]
;   0x23.1      per-axis conditional flag written from a command           [INFER]
;   0x26        frame/byte counter scratch                                 [INFER]
;   0x28.n      system state (0x28.1 program-loaded, .2 running,
;               .3 motion-active, .4 conditional) — shared with executor    [INFER]
;   0x30:0x31   DPTR shadow (lo:hi) for the SRAM program stream            [BYTE]
;   0x3E:0x3F   SRAM program-area page base (hi bytes)                     [BYTE]
;   0x60..0x65  RX data buffer (6 bytes: one per axis)                     [BYTE]
;   0x66:0x67   program counter / 16-bit arg (lo:hi)                       [BYTE]
;   0x68..0x6E  command buffer / response staging                          [BYTE]
;   R0/R2       byte pointer / remaining-count in the active buffer        [BYTE]
;   R4/R5       response bytes staged for TX (status + data)               [BYTE]
;   R6          saved copy of the received byte (SBUF)                     [BYTE]
;
;   NOTE ON 0x30:0x31 ORDER: the SRAM stream loads DPL from 0x30 and DPH from
;   0x31 (see 0x056E / 0x0362), so 0x30 = low, 0x31 = high. The RX-arg pair
;   0x66:0x67 is used low:high by the block routines at 0x07FF/0x0802.
;
;==============================================================================
; ENTRY: serial ISR  isr_serial (0x0300)                                   [BYTE]
;   Reached by LJMP 0x0300 at 0x0035 (fall-through from the 0x0023 vector).
;==============================================================================
        .include "rob3.inc"

; --- ISR PROLOGUE -------------------------------------------------------------
; label jump_02FF (0x02FF) is 0xFF padding decoded as `MOV R7,A`; the real
; entry is the PUSH PSW at 0x0300.
isr_serial:                         ; 0x0300
        push    SFR_PSW             ; 0300: C0 D0   PUSH PSW  (save flags/bank)
        setb    PSW_RS0+1           ; 0302: D2 D4   SETB PSW.4 -> select reg bank 2
                                    ;   (serial ISR runs in bank 2; see docs SFR map)
;   0x0304 is 0xFF padding (`MOV R7,A`), harmless before the first real test.

; --- RX / TX DISPATCH ---------------------------------------------------------
        jnb     0x98.0,serial_exit_early ; 0305: 30 98 4A  JNB SCON.0(RI),0x0352
                                    ;   no received byte -> skip RX (-> 0x0352 ->
                                    ;   0x0525 TX check). Offset 0x4A from 0x0308.  [BYTE]
        clr     0x98.0              ; 0308: C2 98   CLR RI  (ack the received byte)
        mov     A,0x99              ; 030A: E5 99   MOV A,SBUF  (read received byte)
        mov     0x18,#0x14          ; 030C: 75 18 14  reload serial timeout = 0x14
        setb    0x24.2              ; 030F: D2 22   RX flag 0x24.2 (byte-seen)      [INFER]
        jb      0x24.0,rx_payload   ; 0311: 20 20 40  0x24.0 set -> already in a frame,
                                    ;   this byte is PAYLOAD -> 0x0354
        setb    0x24.0              ; 0314: D2 20   else: first byte of a frame ->
                                    ;   mark "frame in progress"                    [INFER]

; --- HEADER (first byte of a frame) decode -----------------------------------
; The received byte is in A (and saved in R6). Its high bits select the op;
; the low 3 bits (anl A,#07h) are the axis 0..5 or 0x07 = "all axes". The exact
; host-visible command names are [INFER] (see docs Communication Protocol).
rx_header:
        mov     R6,A                ; 0316: FE     save the header byte
        mov     R0,#0x60            ; 0317: 78 60   R0 -> RX data buffer 0x60
        mov     R2,#0x01            ; 0319: 7A 01   default payload count = 1
        jb      0xE0.7,hdr_bit7     ; 031B: 20 E7 xx  A.7 set -> command class hi
        jb      0xE0.6,hdr_bit6     ; 031E: 20 E6 xx  A.6 set
        jb      0xE0.4,serial_exit_early ; 0321: 20 E4 xx  A.4 set -> ignore        [INFER]
        anl     A,#0x07             ; 0324: 54 07   isolate axis field (0..7)
        cjne    A,#0x07,serial_exit_early ; 0326: B4 07 xx  axis != 7 -> exit        [INFER]
        mov     R2,#0x06            ; 0329: 7A 06   axis==7 ("all") -> expect 6 bytes
        ajmp    serial_exit         ; 032B: -> 0x0525 (arm to receive 6 payload bytes)

hdr_bit6:                           ; 0x032D  (A.7=0, A.6=1)
        jnb     0xE0.5,hdr_reset    ; 032D: A.5 clear -> 0x039F (set 0x24.1, restart)
        jnb     0xE0.4,hdr_reset    ; 0330: A.4 clear -> 0x039F                       [INFER]
        inc     R2                  ; 0333: expect one extra byte
        anl     A,#0x07             ; 0334: axis field
        cjne    A,#0x07,serial_exit ; 0336: axis != 7 -> exit
        setb    0x24.3              ; 0339: 0x24.3 = "all-axes payload" mode          [INFER]
        mov     R2,#0x06            ; 033B: expect 6 payload bytes
        ajmp    serial_exit         ; 033D: -> 0x0525

hdr_bit7:                           ; 0x033F  (A.7=1: system/program class)          [INFER]
        cjne    A,#0x81,hdr_notblock; 033F: B4 81 xx  0x81 = block/data-start marker
        setb    0x24.3              ; 0344: mark block mode                           [INFER]
        ajmp    serial_exit         ; -> 0x0525

hdr_notblock:                       ; 0x0346
        add     A,#0x77             ; 0346: 24 77   A += 0x77 (range test via carry)
        jc      hdr_carry           ; 0348: 40 xx   -> 0x0350 (A was >= 0x89)         [INFER]
        add     A,#0x02             ; 034A: 24 02   second range test
        jnc     hdr_reset           ; 034C: 50 xx   out of range -> 0x039F
        ajmp    serial_exit         ; 034E: in the 0x89..0x8F band -> 0x0525
                                    ;   (program-download initiation range)          [INFER]
hdr_carry:                          ; 0x0350
        clr     0x24.0              ; 0350: C2 20   clear "frame in progress"         [INFER]
serial_exit_early:                  ; 0x0352 (fwd_0352_jump_0525)
        ajmp    serial_exit         ; 0352: -> 0x0525

;==============================================================================
; RX PAYLOAD path (0x24.0 was already set -> this byte is payload)         [BYTE]
;==============================================================================
rx_payload:                         ; 0x0354
        jbc     0x24.1,rx_dispatch  ; 0354: 10 21 xx  0x24.1 set -> whole frame ready,
                                    ;   go interpret it -> 0x03A9 (clears 0x24.1)
        cjne    R6,#0x81,rx_store   ; 0357: BE 81 xx  header != 0x81 -> plain store -> 0x0398
        jbc     0x24.3,rx_setptr    ; 035A: 10 23 xx  block mode -> set up pointer -> 0x037B
        jbc     0x24.4,rx_setcount  ; 035D: 10 24 xx  -> set count -> 0x0380

; --- SRAM program-stream store (0x81 block, pointer + count already set) ------
        mov     0x83,0x31           ; 0360: 85 31 83  DPH <- 0x31 (SRAM page hi)
        mov     0x82,0x30           ; 0363: 85 30 82  DPL <- 0x30
        movx    @DPTR,A             ; 0366: F0        store payload byte to SRAM      [HW]
        inc     0x30                ; 0367: 05 30     bump stream pointer low
        mov     A,0x30
        jnz     rx_stream_nohi      ; -> 0x036F
        inc     0x31                ; carry into page hi
rx_stream_nohi:                     ; 0x036F
        djnz    R0,rx_exit          ; 036F: D8 xx  more bytes in this run -> 0x03A1
        djnz    R2,rx_exit          ; 0371: DA xx  more runs -> 0x03A1
        movx    A,@DPTR             ; 0373: E0     read back last written byte        [HW]
        cjne    A,#0x83,hdr_reset   ; 0374: B4 83 xx  verify == 0x83 sentinel         [INFER]
        setb    0x28.1              ; 0379: mark "program loaded"                      [INFER]
        sjmp    hdr_reset           ; 037A: -> 0x039F (arm for next frame)

rx_setptr:                          ; 0x037B  (0x81 + 0x24.3): this byte is the ptr
        mov     R0,A                ; 037B: F8     R0 = byte-count for the run
        setb    0x24.4              ; 037C: expect the count byte next
        ajmp    serial_exit         ; 037E: -> 0x0525

rx_setcount:                        ; 0x0380  (0x81 + 0x24.4): this byte is the count
        mov     R2,A                ; 0380: FA
        mov     0x30,#0x00          ; 0381: stream pointer low = 0
        mov     0x31,0x3F           ; 0384: stream pointer hi  = SRAM page (0x3F)     [BYTE]
        mov     0x83,0x3E           ; 0387: DPH = 0x3E
        mov     0x82,#0xFF          ; 038A: DPL = 0xFF
        movx    @DPTR,A             ; 038D: write count to SRAM header                [HW]
        dec     0x82                ; 038E: DPL-- (0xFE)
        mov     A,R0
        dec     A                   ; 0391: R0-1
        movx    @DPTR,A             ; 0392: write (count-1) to SRAM header            [HW]
        clr     0x28.1              ; 0393: clear "program loaded" (reloading)         [INFER]
        inc     R2                  ; 0396: adjust remaining count
        ajmp    serial_exit         ; 0397: -> 0x0525

rx_store:                           ; 0x0398  (plain payload byte -> RX buffer)
        mov     @R0,A               ; 0398: F6     buffer[R0] = byte
        inc     R0                  ; 0399: advance
        djnz    R2,rx_exit          ; 039A: more expected -> 0x03A1
        jbc     0x24.3,rx_all_setup ; 039C: last byte + all-axes mode -> 0x03A3
hdr_reset:                          ; 0x039F
        setb    0x24.1              ; 039F: D2 21  0x24.1 = "frame complete" -> next
                                    ;   received byte triggers rx_dispatch
rx_exit:                            ; 0x03A1 (fwd_03A1_jump_0525)
        ajmp    serial_exit         ; 03A1: -> 0x0525

rx_all_setup:                       ; 0x03A3  (all-axes frame: re-arm for 6 bytes)
        mov     R2,#0x06            ; 03A3: count = 6
        mov     R0,#0x70            ; 03A5: R0 -> 0x70 (second buffer / decel area)   [INFER]
        ajmp    serial_exit         ; 03A7: -> 0x0525

;==============================================================================
; RX FRAME DISPATCH — a complete frame was received; act on it            [BYTE]
;   Entered from rx_payload via  jbc 0x24.1  (frame-complete). R6 = header,
;   the RX buffer(s) hold the payload. Builds a response for the TX helper.
;==============================================================================
rx_dispatch:                        ; 0x03A9
        anl     0x24,#0xC0          ; 03A9: 53 24 C0  clear RX state bits (keep .6/.7)
        mov     R4,#0xF3            ; 03AC: 7C F3  default status/response byte        [INFER]
        cjne    A,#0x03,cmd_generic ; 03AE: A(header remainder)!=3 -> 0x03C1          [INFER]
        mov     A,R6                ; 03B3: reload header
        mov     R5,A                ; 03B4: stage it as a response data byte
        jnb     0xE0.7,cmd_class0   ; 03B5: header.7 clear -> 0x0440 (axis/position)
        inc     R4                  ; 03B8: R4 = 0xF4
        subb    A,#0x80             ; 03B9: A -= 0x80 (index into system commands)     [INFER]
        mov     R6,A                ; 03BB: save sub-code
        jnz     sys_cmd             ; 03BC: nonzero sub-code -> 0x03E1
        jb      0x28.1,sys_readprog ; 03BE: sub-code 0 + program loaded -> 0x03C9
cmd_clr_prog:                       ; 0x03BF
        clr     0x28.1              ; 03BF: clear "program loaded"                     [INFER]
cmd_generic:                        ; 0x03C1
        setb    0x25.3              ; 03C1: arm TX state 0x25.3                        [INFER]
        clr     0x25.2              ; 03C3: clear TX state 0x25.2
        ajmp    serial_exit         ; 03C5: -> 0x0525 (response will stream via TX)

cmd_class0_j:                       ; 0x03C7 (fwd_03C7_jump_0440)
        ajmp    cmd_class0          ; 03C7: -> 0x0440

; --- system: read stored program back to host --------------------------------
sys_readprog:                       ; 0x03C9                                          [INFER]
        setb    0x25.6              ; 03C9: TX mode = "stream from SRAM"               [INFER]
        mov     0x83,0x3E           ; 03CB: DPH = 0x3E (SRAM program page)
        mov     0x82,#0xFE          ; 03CE: DPL = 0xFE (header slot)
        movx    A,@DPTR             ; 03D1: read stored byte-count header             [HW]
        add     A,#0x04             ; 03D2: +4 framing bytes
        mov     R1,A                ; 03D4: R1 = total bytes to send
        inc     DPTR                ; 03D5: -> 0xFF slot
        movx    A,@DPTR             ; 03D6: read second header byte                   [HW]
        mov     R3,A                ; 03D7:
        inc     R3                  ; 03D8: R3 = run count + 1
        mov     0x30,#0xFD          ; 03D9: TX stream pointer low
        mov     0x31,0x3E           ; 03DC: TX stream pointer hi (SRAM page)
        ajmp    serial_exit         ; 03DF: -> 0x0525

; --- system sub-commands (sub-code in R6) ------------------------------------
sys_cmd:                            ; 0x03E1                                          [INFER]
        djnz    R6,sys_cmd_2        ; 03E1: sub-code 1 -> fall; else -> 0x03F1
        jnb     0x28.0,cmd_clr_prog ; 03E3: 0x28.0 clear -> 0x03BF
        lcall   0x07FF              ; 03E6: run/prepare program block (0x07FF helper) [BYTE]
        inc     R4                  ; 03E9: status byte adjust
        jnb     0x28.1,cmd_generic  ; 03EA: not loaded -> generic reply
cmd_run_reply:                      ; 0x03ED
        setb    0x25.2              ; 03ED: TX state 0x25.2                            [INFER]
        ajmp    serial_exit         ; 03EF: -> 0x0525

sys_cmd_2:                          ; 0x03F1  (sub-code 2)
        mov     R4,#0xF6            ; 03F1: status byte 0xF6                           [INFER]
        jnb     0x28.1,cmd_generic  ; 03F3: not loaded -> generic
        djnz    R6,sys_cmd_3        ; 03F6: -> 0x040B (sub-code 3)
        clr     A
        mov     0x26,A              ; 03F9: reset frame counter
        mov     0x66,A              ; 03FB: PC low = 0
        mov     0x67,0x3F           ; 03FD: PC high = SRAM page -> start of program
sys_exec_step:                      ; 0x0400
        lcall   0x0802              ; 0400: execute/advance one program block (0x0802)[BYTE]
        jnb     0x28.1,cmd_generic  ; 0403: program cleared -> generic
        mov     0x1F,#0xFF          ; 0406: Port B shadow = 0xFF (all outputs)         [HW]
        sjmp    sys_set_running     ; 0409: -> 0x041A

sys_cmd_3:                          ; 0x040B  (sub-code 3)
        djnz    R6,sys_cmd_4        ; 040B: -> 0x0415
sys_stop:                           ; 0x040D
        anl     0x28,#0x03          ; 040D: clear run/motion/cond bits (keep .0/.1)    [INFER]
        mov     0x26,#0x00          ; 0410: reset frame counter
        sjmp    cmd_run_reply       ; 0413: -> 0x03ED

sys_cmd_4:                          ; 0x0415  (sub-code 4)
        djnz    R6,sys_cmd_5        ; 0415: -> 0x041F
        jnb     0x28.2,cmd_generic  ; 0417: not running -> generic
sys_set_running:                    ; 0x041A
        orl     0x28,#0x0C          ; 041A: set running(.2)+motion(.3)                 [INFER]
        sjmp    cmd_run_reply       ; 041D: -> 0x03ED

sys_cmd_5:                          ; 0x041F  (sub-code 5)
        djnz    R6,sys_cmd_6        ; 041F: -> 0x0428
        jnb     0x28.2,cmd_generic  ; 0421: not running -> generic
        setb    0x28.4              ; 0424: set conditional(.4)                        [INFER]
        sjmp    cmd_run_reply       ; 0426: -> 0x03ED

sys_cmd_6:                          ; 0x0428  (sub-code 6)
        djnz    R6,sys_cmd_7        ; 0428: -> 0x042E
        clr     0x28.3              ; 042A: clear motion(.3)                           [INFER]
        sjmp    cmd_run_reply       ; 042C: -> 0x03ED

sys_cmd_7:                          ; 0x042E  (sub-code 7+)
        mov     A,0x60              ; 042E: A = RX buffer[0] (arg)
        djnz    R6,sys_cmd_8        ; 0430: -> 0x0437
        lcall   0x0A33              ; 0432: program helper (0x0A33)                    [BYTE]
        sjmp    sys_exec_step       ; 0435: -> 0x0400

sys_cmd_8:                          ; 0x0437
        mov     R4,#0xF2            ; 0437: status 0xF2                                [INFER]
        djnz    R6,cmd_generic      ; 0439: -> 0x03C1
        lcall   0x0A33              ; 043B: program helper (0x0A33)                    [BYTE]
        sjmp    sys_stop            ; 043E: -> 0x040D

;==============================================================================
; CLASS-0 commands (header.7 = 0): AXIS / POSITION / FEEDBACK              [BYTE]
;   Sub-decode on header bits .6/.5/.4 and the axis field (low 3 bits).
;   Command-name mapping is [INFER] (docs Communication Protocol).
;==============================================================================
cmd_class0:                         ; 0x0440
        jnb     0xE0.6,c0_bit6_lo   ; 0440: header.6 clear -> 0x04AF
        jb      0xE0.5,c0_65        ; 0443: .6 set + .5 set -> 0x048C
; --- .6=1 .5=0 : READ feedback / positions into the response buffer 0x68.. ----
        mov     R1,#0x68            ; 0446: R1 -> response buffer 0x68
        mov     @R1,A               ; 0448: echo header into 0x68
        mov     R3,#0x01            ; 0449: default 1 data byte
        jb      0xE0.4,c0_read_dig  ; 044B: .4 set -> 0x0471 (read digital inputs)
        anl     A,#0x07             ; 044E: axis field
        cjne    A,#0x07,c0_read_one ; 0450: != 7 -> single axis feedback -> 0x0469
        mov     0x69,0x58           ; 0453: copy all 6 feedback (0x58..0x5D) ->  [SIM]
        mov     0x6A,0x59           ; 0456:   response buffer (0x69..0x6E). Verified:
        mov     0x6B,0x5A           ; 0459:   feedback 11 22 33 44 55 66 seeded ->
        mov     0x6C,0x5B           ; 045C:   0x68..0x6E = 47 11 22 33 44 55 66,
        mov     0x6D,0x5C           ; 045F:   R3=7, R1=0x68, 0x25.1 set.            [SIM]
        mov     0x6E,0x5D           ; 0462:
        mov     R3,#0x07            ; 0465: 7 bytes (header + 6 axes)              [SIM]
        ajmp    c0_arm_tx           ; 0467: -> 0x0486
c0_read_one:                        ; 0x0469  (single-axis feedback)
        add     A,#0x58             ; 0469: A = 0x58 + axis (feedback slot)
        mov     R0,A                ; 046B:
        mov     0x69,@R0            ; 046C: response[1] = feedback[axis]
        inc     R3                  ; 046F: 2 bytes
        ajmp    c0_arm_tx           ; 0470: -> 0x0486
c0_read_dig:                        ; 0x0471  (.4 set: read digital input bits)       [INFER]
        jnb     0xE0.0,c0_dig1      ; 0471: axis.0 -> include one input
        inc     R1
        inc     R3
        mov     @R1,0x5E            ; 0475: append 0x5E (aux feedback/input)
c0_dig1:                            ; 0x0478
        jnb     0xE0.1,c0_dig2      ; 0478:
        inc     R1
        inc     R3
        mov     @R1,0x5F            ; 047C: append 0x5F
c0_dig2:                            ; 0x047F
        jnb     0xE0.2,c0_arm_tx    ; 047F:
        inc     R1
        inc     R3
        mov     @R1,0x90            ; 0483: append P1 (0x90) input state             [HW]
c0_arm_tx:                          ; 0x0486
        setb    0x25.1              ; 0486: TX mode = "send response buffer"          [SIM]
        mov     R1,#0x68            ; 0488: R1 -> response buffer start (for TX)       [SIM]
        ajmp    serial_exit         ; 048A: -> 0x0525

; --- .6=1 .5=1 : write single I/O bit / snapshot feedback into positions ------
c0_65:                              ; 0x048C
        jb      0xE0.4,c0_654       ; 048C: .4 set -> 0x04D5
        jb      0xE0.1,c0_65_1      ; 048F: .1 set -> 0x0498
        mov     C,0xE0.0            ; 0492: C = header.0
        mov     0x20.0,C            ; 0495: 0x20.0 (axis-enable flag) = C            [INFER]
        ajmp    serial_exit         ; 0497: -> 0x0525
c0_65_1:                            ; 0x0498
        jb      0xE0.0,c0_setprog   ; 0498: .0 set -> 0x050B
        mov     0x50,0x58           ; 049B: snapshot feedback (0x58..) into current
        mov     0x51,0x59           ; 049E:   positions (0x50..) — "sync to sensor"   [BYTE]
        mov     0x52,0x5A           ; 04A1:
        mov     0x53,0x5B           ; 04A4:
        mov     0x54,0x5C           ; 04A7:
        mov     0x55,0x5D           ; 04AA:
        ajmp    serial_exit         ; 04AD: -> 0x0525

; --- .6=0 : write CURRENT POSITION from the RX buffer -------------------------
c0_bit6_lo:                         ; 0x04AF
        jb      0xE0.4,c0_settarget ; 04AF: .4 set -> 0x051F
        anl     A,#0x07             ; 04B2: axis field
        cjne    A,#0x07,c0_pos_one  ; 04B4: != 7 -> single -> 0x04CE
        mov     0x21,#0x00          ; 04B9: clear 0x21 (motion mask)                  [INFER]
        mov     0x50,0x60           ; 04BC: positions 0x50.. <- RX buffer 0x60..
        mov     0x51,0x61           ; 04BF:
        mov     0x52,0x62           ; 04C2:
        mov     0x53,0x63           ; 04C5:
        mov     0x54,0x64           ; 04C8:
        mov     0x55,0x65           ; 04CB:
        sjmp    c0_done             ; 04CD: -> 0x04FF
c0_pos_one:                         ; 0x04CE
        add     A,#0x50             ; 04CE: 0x50 + axis
        mov     R0,A
        mov     @R0,0x60            ; 04D1: position[axis] = RX buffer[0]. Verified:  [SIM]
                                    ;   header 0x02 (axis 2) + 0x60=0x80 -> 0x52=0x80,
                                    ;   and 0x25.7 (ACK) set at c0_ack.                [SIM]
        sjmp    c0_done             ; 04D4: -> 0x04FF

; --- .6=1 .5=1 .4=1 : write TARGET position (arms motion) ---------------------
c0_654:                             ; 0x04D5
        anl     A,#0x07             ; 04D5: axis field
        cjne    A,#0x07,c0_tgt_one  ; 04D7: != 7 -> single -> 0x04F0
        mov     0x40,0x60           ; 04DC: targets 0x40.. <- RX buffer 0x60..
        mov     0x41,0x61           ; 04DF:
        mov     0x42,0x62           ; 04E2:
        mov     0x43,0x63           ; 04E5:
        mov     0x44,0x64           ; 04E8:
        mov     0x45,0x65           ; 04EB:
        mov     A,#0x3F             ; 04EE: motion mask = all 6 axes (0x3F)           [INFER]
        sjmp    c0_tgt_mask         ; 04F0? -> 0x04FB
c0_tgt_one:                         ; 0x04F0
        add     A,#0x40             ; 04F0: 0x40 + axis
        mov     R0,A
        mov     @R0,0x60            ; 04F3: target[axis] = RX buffer[0]
        orl     0x10,#0x70          ; 04F6: (bank-2 R0-region flag set)               [INFER]
        mov     @R0,0x61            ; 04F9: second byte? (target hi / speed)          [INFER]
        movc    A,@A+PC             ; ...   1<<axis via a bit table                   [INFER]
c0_tgt_mask:                        ; 0x04FB
        orl     0x2B,A              ; 04FB: OR the axis bit into motion masks
        orl     0x2C,A              ; 04FD:   (0x2B / 0x2C = "needs move" flags)       [INFER]
c0_done:                            ; 0x04FF
        mov     A,R6                ; 04FF: reload header
        mov     C,0xE0.3            ; 0500: C = header.3
        mov     0x23.1,C            ; 0502: 0x23.1 = conditional flag                 [INFER]
c0_ack:                             ; 0x0504
        setb    0x25.7              ; 0504: TX mode = "send single status byte"       [SIM]
        mov     0x19,#0x64          ; 0506: secondary timeout/retry = 0x64
        ajmp    serial_exit         ; 0509: -> 0x0525

; --- .6=1 .5=1 .0=1 : read program header block into response -----------------
c0_setprog:                         ; 0x050B                                          [INFER]
        mov     0x68,A              ; 050B: response[0] = header
        mov     DPTR,#0x001F        ; 050C: (label dptr_001F)                         [BYTE]
        movx    A,@DPTR             ; 050F: read program info byte                     [HW]
        mov     0x69,A              ; 0510:
        inc     DPTR
        movx    A,@DPTR             ; 0513:
        mov     0x6A,A              ; 0514:
        inc     DPTR
        movx    A,@DPTR             ; 0516:
        mov     0x6B,A              ; 0517:
        mov     R3,#0x04            ; 0518: 4-byte response
        ajmp    c0_arm_tx           ; 051A: -> 0x0486

; --- .6=0 .4=1 : set target from a computed value -----------------------------
c0_settarget:                       ; 0x051F
        mov     R0,0x60             ; 051F: R0 = RX buffer[0]
        acall   portb_write         ; 0521: 0x07D0 helper -> drive Port B digital out [HW]
        mov     0x47,A              ; 0523: store returned value in 0x47 (display?)   [INFER]

;==============================================================================
; COMMON EXIT + TX service  serial_exit (0x0525)                          [BYTE]
;   Every RX/dispatch path lands here. If the transmitter is ready (TI set)
;   it ACKs TI and calls the TX helper to load the next byte, then RETIs.
;==============================================================================
serial_exit:                        ; 0x0525  (label jump_0525)
        jnb     0x98.1,serial_ret   ; 0525: 30 99 04  JNB SCON.1(TI) -> 0x052B
        clr     0x98.1              ; 0528: C2 99  CLR TI (ack transmit-ready)
        acall   serial_tx_next      ; 052A: B1 41  ACALL 0x0541 (TX helper)
serial_ret:                         ; 0x052B
        mov     A,R7                ; 052B: EF     (restore scratch)
        pop     SFR_PSW             ; 052C: D0 D0  POP PSW (restore flags/bank)
        reti                        ; 052E: 32     RETI  (re-enable this int level)
;   0x052F.. is 0xFF padding.

;==============================================================================
; SERIAL TX HELPER  serial_tx_next (0x0541)                               [BYTE]
;   Entry at 0x0541 (CLR 0x23.0), reached by ACALL 0x0541 from serial_exit
;   (0x052A) and by other callers. Sources the next outgoing byte from
;   whichever TX state is active and writes it to SBUF (0x99).
;==============================================================================
serial_tx_next:                     ; 0x0541
        clr     0x23.0              ; 0541: C2 18  clear "TX pending" tick flag        [INFER]
        jnb     0x25.1,tx_not_buf   ; 0543: 30 29 11  0x25.1 clear -> 0x0557
; --- TX from the response buffer (R1 pointer, R3 count) -----------------------
; [SIM]: with 0x25.1 set, R1=0x68, R3=3, one call sent buffer[0] and left
;   R1=0x69, R3=2 (pointer++/count--). When R3 reached 1, the call set 0x25.4
;   (0x25 -> 0x12). The FOLLOWING call took tx_buf_last -> cleared 0x25.1 and
;   reached tx_send_etx (0x0553) = MOV SBUF,#0x03 -> the ETX terminator.
        jbc     0x25.4,tx_buf_last  ; 0546: 10 2C 08  0x25.4 set -> last-byte -> 0x0551 [SIM]
        mov     0x99,@R1            ; 0549: 87 99  SBUF = *R1  (send next buffer byte)  [SIM]
        inc     R1                  ; 054B: 09    advance                               [SIM]
        djnz    R3,tx_buf_ret       ; 054C: DB 02  more bytes -> 0x0550                 [SIM]
        setb    0x25.4              ; 054E: D2 2C  last byte queued -> set end flag      [SIM]
tx_buf_ret:                         ; 0x0550
        ret                         ; 0550:
tx_buf_last:                        ; 0x0551
        clr     0x25.1              ; 0551: end buffer mode                              [SIM]
tx_send_etx:                        ; 0x0553
        mov     0x99,#0x03          ; 0553: SBUF = 0x03 (ETX / frame terminator)        [SIM]
        ret                         ; 0556:

tx_not_buf:                         ; 0x0557
        jb      0x25.6,tx_from_sram ; 0557: 0x25.6 set -> stream from SRAM -> 0x056E
        jbc     0x25.2,tx_send_r5   ; 055A: 0x25.2 -> send R5 -> 0x0569
        jbc     0x25.5,tx_send_etx  ; 055D: 0x25.5 -> send ETX -> 0x0553
        jbc     0x25.3,tx_send_r4   ; 0560: 0x25.3 -> send R4 (status) -> 0x0566
        setb    0x23.0              ; 0563: nothing queued -> re-arm "TX pending"      [INFER]
        ret                         ; 0565:
tx_send_r4:                         ; 0x0566
        mov     0x99,R4             ; 0566: SBUF = R4 (status byte, e.g. 0xF1 reset-ACK) [SIM role]
        ret                         ; 0568:
tx_send_r5:                         ; 0x0569
        mov     0x99,R5             ; 0569: SBUF = R5 (data byte)
        setb    0x25.5              ; 056A: next send an ETX
        ret                         ; 056D:

; --- TX streaming a stored program back out of SRAM ---------------------------
tx_from_sram:                       ; 0x056E
        mov     0x82,0x30           ; 056E: DPL <- 0x30 (stream ptr low)
        mov     0x83,0x31           ; 0571: DPH <- 0x31 (stream ptr hi)
        movx    A,@DPTR             ; 0574: read next program byte                    [HW]
        mov     0x99,A              ; 0575: SBUF = byte
        inc     0x30                ; 0577: bump pointer low
        mov     A,0x30
        jnz     tx_sram_nohi        ; -> 0x057F
        inc     0x31                ; carry into hi
tx_sram_nohi:                       ; 0x057F
        djnz    R1,tx_sram_ret      ; 057F: more bytes in run -> 0x0587
        djnz    R3,tx_sram_ret      ; 0581: more runs -> 0x0587
        clr     0x25.6              ; 0583: done streaming
        setb    0x25.5              ; 0585: send a terminating ETX next
tx_sram_ret:                        ; 0x0587
        ret                         ; 0587:

;==============================================================================
; RESET-ACK / SERIAL IDLE-TIMEOUT  (lives in the MAIN LOOP, not this ISR)
;   0x0785 in main.asm.  Cross-referenced here because it is the RX side's
;   completion: it is what actually SENDS the reply after a byte is received.
;------------------------------------------------------------------------------
; The serial ISR does NOT reply immediately. Each received byte only:
;   - sets 0x24.2 ("a byte was seen")           (0x030F in this file), and
;   - reloads the idle-timeout counter 0x18 = 0x14 (0x030C).
; The Timer-0 system tick sets 0x23.7 each tick. The main loop, at 0x0785,
; runs the idle-timeout accept:
;
;       0785:  jnb 0x23.7, 0x0797     ; only on a fresh timer tick
;       0788:  clr 0x23.7
;       078A:  jnb 0x24.2, 0x0797     ; only if a byte was received
;       078D:  djnz 0x18, 0x0797      ; count down the idle timeout; wait until 0
;       0790:  anl 0x24, #0xF0        ; RX line-idle -> RESET the RX parser state
;       0793:  mov R4, #0xF1          ; stage the reset-ACK byte 0xF1          [BYTE]
;       0795:  setb 0x25.3            ; arm TX to send R4 (-> tx_send_r4)      [BYTE]
;
; So: host sends a byte (e.g. 0x20) after reset -> after the RX line goes idle
; for the timeout window, the firmware stages 0xF1 and the TX helper streams it
; (0x25.3 -> tx_send_r4 -> MOV SBUF,R4). The host therefore sees a burst of
; 0xF1 (interspersed with other TX-state bytes such as R5/status), exactly the
; bench capture in hardware/host/README.md (`printf '\x20'` -> f1 f1 ... 15 f3 ...).
;
; [SIM] Verified: seeding 0x23.7=1, 0x24.2=1, 0x18=1 and executing from 0x0785
;   yields R4 = 0xF1, 0x24 low nibble cleared (0x24 -> 0x00), and 0x25.3 set
;   (0x25 -> 0x08). [HW] the resulting 0xF1 flood is the documented reset reply.
;
;==============================================================================
; HELPERS REFERENCED (annotated elsewhere / by role)
;------------------------------------------------------------------------------
;   0x07D0  portb_write  — 8255 Port B (DPH=0x51) digital-out helper: R2 selects
;           OR/AND/XOR/WRITE against the 0x1F shadow, then MOVX @DPTR,A. [BYTE][HW]
;           (Full listing near 0x07D0 in main.asm.)
;   0x07FF / 0x0802 / 0x0A33 — external-SRAM program block routines (load / step /
;           validate the stored motion program). Called by the system-command
;           dispatch above; their internals are the program-interpreter subsystem
;           and are annotated separately (not in this file). [BYTE], semantics [INFER].
;
;==============================================================================
; OPEN / [INFER] LEFT STANDING
;------------------------------------------------------------------------------
;   * The SYSTEM-class (header.7=1) sub-command decode (0x03E1.. sys_cmd_N) and
;     the program upload/download SRAM streaming are [BYTE] for flow but their
;     host wire names remain [INFER] — not yet driven in ucSim.
;   * The precise ROLE of several 0x24/0x25/0x28/0x23 flag bits is now partly
;     [SIM] (0x24.2 byte-seen; 0x25.1 buffer-TX; 0x25.3 send-R4; 0x25.4 buffer-
;     end; 0x25.7 ACK). The remaining bits (0x25.2/.5/.6, 0x28.x, 0x23.1) are
;     [BYTE] at their read/write sites but [INFER] in role.
;   * The 0x40+ target-write "second byte" path (0x04F6..0x04FA, orl 0x10 / the
;     movc bit-table) is not fully resolved — whether the second byte is a speed
;     or target-hi is [INFER].
;   * The gripper frame `05 FF 03` (hardware/host/README.md) routes header 0x05 to the
;     axis-5 class-0 write (R6=0x05, R0=0x60, R2=1 payload observed [SIM]); the
;     trailing 0x03 is the ETX the TX side also emits. End-to-end multi-byte
;     value commit was not run as one stream (needs the RI/s_in feed, below).
;
; VERIFICATION STATUS
;   Control flow, addresses, SBUF/SCON access, timeout reload, and buffer/SRAM
;   pointer handling are [BYTE] (decoded from the ROM; addresses byte-verified
;   with xxd: entry 0x0300, serial_exit 0x0525, RETI 0x052E, ACALL 0x0541 to
;   the TX helper).
;
;   [SIM] runs (ucsim_51 0.9.9, `-t 51 -X 11.0592M simulator/build/rob3.hex`),
;   entering at the relevant address with seeded IRAM/A and a breakpoint at the
;   common exit:
;     - READ feedback (enter 0x0440, A=0x47, 0x58..=11 22 33 44 55 66) ->
;       0x68..0x6E = 47 11 22 33 44 55 66, R3=7, R1=0x68, 0x25.1 set.
;     - TX buffer stream (enter 0x0541, 0x25.1 set, R1=0x68, R3=3) -> one call
;       R1->0x69, R3->2; at R3=1 sets 0x25.4; next call clears 0x25.1 and
;       reaches tx_send_etx (0x0553 = MOV SBUF,#0x03).
;     - WRITE single-axis position (enter 0x0440, A=0x02, 0x60=0x80) ->
;       0x52=0x80, 0x25.7 set.
;     - RESET-ACK (enter 0x0785, 0x23.7=1 0x24.2=1 0x18=1) -> R4=0xF1,
;       0x24 low nibble cleared, 0x25.3 set.
;
;   [SIM] END-TO-END over the REAL wire (simulator/tests/sim_serial_e2e.sh,
;   loader ucsim_51 + adc + rxd cl_hw modules + `-S in=,out=` serial link):
;     - the rxd module shifts the auto-baud training byte 0x20 on P3.0; the ROM
;       locks (TH1=0xFC, TR1, IE=0x17) and transmits its 0x15 ACK on the serial
;       OUTPUT (TX over the link, captured in the out file);
;     - a command byte 0x47 sent on the serial INPUT is clocked by the CORE UART
;       into SBUF verbatim (SBUF=0x47) with RI set (SCON=0x51);
;     - the RX ISR at 0x0300 runs from that real reception and the RX parser
;       advances (0x24=0x07: frame-in-progress .0 + byte-seen .2).
;   This connects the wire -> SBUF/RI -> ISR -> parser chain that the seeded
;   entries above stop short of. (Note: `MOV A,SBUF` reads the model's s_in, so
;   the seeded-entry tests deliberately bypass it; the e2e test uses the real
;   UART path once the baud is set.) See also
;   simulator/issues/003-mcs51-uart-does-not-drive-rxd-txd-pins.
;
;   ucSim serial note: `MOV A,SBUF` returns the model's internal `s_in`, NOT the
;   SBUF SFR cell (cl_serial::read in src/sims/s51.src/serial.cc), and a write
;   to SBUF sets `s_out` (not the cell get()). So injecting a byte via
;   `set mem sfr 0x99` does NOT feed the RX path, and transmitted bytes are not
;   visible via `dump sfr 0x99`. These [SIM] runs therefore enter the decode
;   AFTER the SBUF read (seeding A / the RX buffer) and observe the resulting
;   IRAM/registers; a fully end-to-end feed would use ucSim's `-S` serial input.
;
;   NOT assembled: this is a documentation listing; the golden byte-match build
;   uses simulator/*.a51, not the annotated files.
;==============================================================================
