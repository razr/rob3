;==============================================================================
; ROB3 FIRMWARE — RESET INITIALIZATION SEQUENCE (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the reset init sequence (0x0600 -> main-loop entry 0x074D):
;                    warm-up, 8255 PPI, ADC/axis seed, RAM clear, SRAM probe,
;                    program-area header, UART/timer setup, auto-baud.
;                    Part of the 1:1 annotated source assembled by rob3.asm.
;                    (The main loop at 0x074D lives in main.asm.)
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. Unmarked instruction lines are [BYTE].
;
;==============================================================================
; INITIALIZATION SEQUENCE   (0x0600 -> main loop)
;------------------------------------------------------------------------------
; Reached from the reset vector (LJMP 0x0600). Brings up: warm-up delay, 8255
; PPI, axis select, internal RAM clear, stack, external SRAM sizing/probe,
; program-area header, interrupt enables, then falls into the main loop.
;==============================================================================

        .org    0x0600

;------------------------------------------------------------------------------
; (1) Power-on warm-up delay. Lets the hardware (8255, analog rails from the
;     MAX1044, ADC) settle before the CPU touches the bus.                [BYTE]
;------------------------------------------------------------------------------
init_start:
        mov     A,#0x78             ; 74 78     A = 0x78 (120) outer delay seed
delay_warmup:
        djnz    R0,delay_warmup     ; D8 FE     spin down R0 (256 iterations)
        djnz    SFR_ACC,delay_warmup ; D5 E0 FB decrement A, repeat -> long warm-up

;------------------------------------------------------------------------------
; (2) Poke the aux/axis-select device (DPH=0x48, 74LS138 Y2/Y3 region). Resets
;     that block to a known state before use.                     [BYTE][HW]
;------------------------------------------------------------------------------
        mov     SFR_DPH,#DEV_AUX_LATCH ; 75 83 48  DPH = 0x48 -> aux/axis-select
init_aux_settle:
        movx    @DPTR,A             ; F0        write A to device 0x48
        djnz    R0,init_aux_settle  ; D8 FD     short settle delay
init_self_settle:
        djnz    R0,init_self_settle ; D8 FE     short settle delay

;------------------------------------------------------------------------------
; (3) Configure the 8255 PPI: mode word then clear/preset the three ports.
;     Control = 0x80 -> Mode 0, Ports A, B, C all OUTPUT.               [BYTE]
;------------------------------------------------------------------------------
        mov     SFR_DPH,#DEV_8255_CTRL ; 75 83 53  DPH -> 8255 CONTROL register
        mov     A,#0x80             ; 74 80     mode 0, A/B/C = output
        movx    @DPTR,A             ; F0        program 8255
        clr     A                   ; E4        A = 0
        dec     SFR_DPH             ; 15 83     DPH -> 0x52 = 8255 Port C
        movx    @DPTR,A             ; F0        Port C = 0x00 (motors off)
        dec     SFR_DPH             ; 15 83     DPH -> 0x51 = 8255 Port B
        mov     A,#0xFF             ; 74 FF     A = 0xFF
        movx    @DPTR,A             ; F0        Port B = 0xFF (digital out, active-low idle)
        dec     SFR_DPH             ; 15 83     DPH -> 0x50 = 8255 Port A
        clr     A                   ; E4        A = 0
        movx    @DPTR,A             ; F0        Port A = 0x00 (motors off)

;------------------------------------------------------------------------------
; (4) Prime the ADC/feedback device (DPH=0x59, 74LS138 Y6/Y7 region) with 0x01.
;     0x59 => A8=1 selects ADC channel via ADD-A.               [BYTE][HW]
;------------------------------------------------------------------------------
        mov     SFR_DPH,#DEV_ADC_DATA ; 75 83 59  DPH -> ADC, channel A8=1
        mov     A,#0x01             ; 74 01     A = 1
        movx    @DPTR,A             ; F0        write 0x01 to ADC device

;------------------------------------------------------------------------------
; (5) Clear internal RAM 0x7F..0x01 and select register bank 0.         [BYTE]
;------------------------------------------------------------------------------
        mov     R0,#0x7F            ; 78 7F     R0 = 0x7F (top of internal RAM)
        clr     A                   ; E4        A = 0 (fill value)
        mov     SFR_PSW,A           ; F5 D0     PSW = 0 -> bank 0, flags cleared
clear_ram_loop:
        mov     @R0,A               ; F6        [R0] = 0
        djnz    R0,clear_ram_loop   ; D8 FD     walk down until R0 == 0

;------------------------------------------------------------------------------
; (6) Stack pointer and two output shadow latches.                      [BYTE]
;------------------------------------------------------------------------------
        mov     SFR_SP,#0x31        ; 75 81 31  SP = 0x31 (stack above vars)
        mov     LED_LATCH,#0xFF     ; 75 47 FF  0x47 = 0xFF (display/LED latch)
        mov     DOUT_SHADOW,#0xFF   ; 75 1F FF  0x1F = 0xFF (digital-out shadow)

;------------------------------------------------------------------------------
; (7) External SRAM probe / sizing. Read a cell, write complement, read back
;     and compare to confirm working RAM and find the top page.
;     Probe window base = 0x8000 (DPH=0x80); fallback page 0xA0.       [BYTE]
;------------------------------------------------------------------------------
        mov     DPTR,#0x8000        ; 90 80 00  DPTR = 0x8000 -> ext SRAM window
ram_probe:
        movx    A,@DPTR             ; E0        read current SRAM cell
        cpl     A                   ; F4        complement it
        movx    @DPTR,A             ; F0        write complement back
        mov     R0,A                ; F8        save expected value
        movx    A,@DPTR             ; E0        read it back
        xrl     A,R0                ; 68        A ^= expected -> 0 if RAM OK
        jz      ram_ok              ; 60 0A     branch if verify passed
        jbc     STATE_B7,ram_done   ; 10 47 2B  0x28.7: retry flag set -> give up
        setb    STATE_B7            ; D2 47     set retry flag
        mov     SFR_DPH,#DEV_SRAM_ALT ; 75 83 A0  try alternate page 0xA0
        sjmp    ram_probe           ; 80 EE     re-probe

ram_ok:
        mov     A,R0                ; E8        recover expected value
        cpl     A                   ; F4        restore ORIGINAL cell contents
        movx    @DPTR,A             ; F0        write original back (non-destructive)
        mov     PROG_PAGE,SFR_DPH   ; 85 83 3E  0x3E = working SRAM page high byte
        mov     PROG_PAGE1,PROG_PAGE ; 85 3E 3F 0x3F = copy of page
        inc     PROG_PAGE1          ; 05 3F     0x3F = page + 1
        mov     STATE_FLAGS,#0x03   ; 75 28 03  0x28 = 0x03 (RAM present seed) [INFER]

;------------------------------------------------------------------------------
; (8) Initialize / validate the program-area header in external SRAM.
;     Compares 8 bytes at offset 0xF0 against R0-indexed pattern; if any
;     differ, rewrites them and clears state flag 0x28.1.               [BYTE]
;------------------------------------------------------------------------------
        mov     SFR_DPL,#0xF0      ; 75 82 F0  DPL = 0xF0 (header offset)
        mov     R0,#0x08            ; 78 08     8 header bytes to check
hdr_loop:
        movx    A,@DPTR             ; E0        read header byte
        cjne    A,0x00,hdr_diff     ; B5 00 02  compare with RAM[0x00] template
        sjmp    hdr_next            ; 80 05     match -> keep
hdr_diff:
        mov     A,0x00              ; E5 00     load template byte
        movx    @DPTR,A             ; F0        write it into header
        clr     STATE_PROG_LOAD     ; C2 41     0x28.1 program-loaded flag = 0
hdr_next:
        inc     DPTR                ; A3        next header byte
        djnz    R0,hdr_loop         ; D8 F2     repeat for all 8 bytes
        lcall   0x0800              ; 12 08 00  program-area init (prog_init) [INFER]

;------------------------------------------------------------------------------
; (9) Axis subsystem seed + start one feedback cycle via EXT1.          [BYTE]
;------------------------------------------------------------------------------
ram_done:
        mov     0x08,#0x48          ; 75 08 48  bank1 R0 = 0x48 (axis base ptr)
        mov     AXIS_MASK,#0x01     ; 75 22 01  axis mask, start at axis 0 (bit0)
        mov     SFR_DPH,#DEV_ADC_START ; 75 83 58  DPH -> ADC channel A8=0 [HW]
        clr     A                   ; E4
        movx    @DPTR,A             ; F0        feedback select = 0 (axis 0)
        mov     SFR_IE,#0x84        ; 75 A8 84  IE = 0x84 -> EA=1, EX1 (axis servo)
init_wait_isr_lo:
        jb      AXIS_MASK_B0,init_wait_isr_lo ; 20 10 FD  wait until bit0 clears (one ISR pass) [SIM]
init_wait_isr_hi:
        jnb     AXIS_MASK_B0,init_wait_isr_hi ; 30 10 FD  then wait until set again (sync)     [SIM]

;------------------------------------------------------------------------------
; (10) Copy 6 feedback readings -> current-position array (seed positions
;      from wherever the arm physically is at power-up).                [BYTE]
;------------------------------------------------------------------------------
        clr     IE_EA               ; C2 AF     EA = 0 (disable ints during copy)
        mov     R7,#0x06            ; 7F 06     6 axes
        mov     R0,#FB_BASE         ; 78 58     src = feedback (0x58..0x5D)
        mov     R1,#CURPOS_BASE     ; 79 50     dst = current pos (0x50..0x55)
copy_fb_loop:
        mov     A,@R0               ; E6        A = feedback[R0]
        mov     @R1,A               ; F7        current_pos[R1] = A
        inc     R0                  ; 08
        inc     R1                  ; 09
        djnz    R7,copy_fb_loop     ; DF FA     repeat for 6 axes

;------------------------------------------------------------------------------
; (11) Preset 6 axis speed/step entries (0x48..0x4D) to 0x01.          [BYTE]
;------------------------------------------------------------------------------
        mov     R7,#0x06            ; 7F 06     6 axes
        mov     R0,#SPEED_BASE      ; 78 48     -> speed array 0x48..0x4D
        mov     A,#0x01             ; 74 01     default speed = 1
speed_loop:
        mov     @R0,A               ; F6        speed[R0] = 1
        inc     R0                  ; 08
        djnz    R7,speed_loop       ; DF FC     repeat for 6 axes

;------------------------------------------------------------------------------
; (12) UART / Timer setup for serial comms.                             [BYTE]
;      TMOD=0x21 (T1 mode2 = UART baud gen, T0 mode1), TCON=0,
;      SCON=0x50 (mode 1, 8-bit UART, REN=1).
;------------------------------------------------------------------------------
        mov     SFR_TMOD,#0x21      ; 75 89 21  T1 mode2 (baud), T0 mode1
        mov     SFR_TCON,#0x00      ; 75 88 00  TCON = 0 (timers/flags cleared)
        mov     SFR_SCON,#0x50      ; 75 98 50  UART mode 1, REN enabled
        jb      P3_RXD,baud_detect  ; 20 B0 07  P3.0=1 -> auto-detect baud path
        mov     SFR_IE,#0x07        ; 75 A8 07  IE = 0x07 -> EX0+ET0+EX1 (no ES)
        setb    SYS_BAUD_DET        ; D2 02     0x20.2 = "baud ready"
        ajmp    init_finish         ; E1 3C     skip auto-detect
;   NOTE (fixed-baud path): this enables EX0+ET0+EX1 but NOT the serial
;   interrupt (ES), AND never starts Timer 1 (TR1) or writes TH1. So serial
;   comms does not work on this path. Only auto-detect arms the UART.   [BYTE][SIM]

;------------------------------------------------------------------------------
; (12b) SOFTWARE AUTO-BAUD (0x06B1..0x073B).                       [BYTE][SIM]
;   Measures the width of the incoming training byte on the raw P3.0 (RXD)
;   pin using Timer 0, then derives TH1. See vectors.asm for the full
;   description and the sim findings (baud window, TH1=0xFC, 115200 out of
;   range). Verified end-to-end with the rxd cl_hw pin-driver.
;------------------------------------------------------------------------------
baud_detect:
        jb      P3_INT0,baud_clear  ; 20 B2 02  sample P3.2 (line-idle check) [INFER]
        setb    SYS_BAUD_DET        ; D2 02     0x20.2 = "baud ready"
baud_clear:
        clr     A                   ; E4
        mov     SFR_TCON,A          ; F5 88     TCON = 0
        mov     SFR_TL0,A           ; F5 8A     TL0 = 0 (clear Timer 0)
        mov     SFR_TH0,A           ; F5 8C     TH0 = 0
        mov     R0,#0x01            ; 78 01     edge-capture buffer pointer seed
baud_wait_start:
        jb      P3_RXD,baud_wait_start ; 20 B0 FD  wait for P3.0 LOW (start edge)
        setb    TCON_TR0            ; D2 8C     TR0 = start Timer 0
; --- capture 4 edge widths ---
baud_edge1:
        jb      0x8D,baud_clear     ; 20 8D EF  Timer 0 overflow -> re-measure
        jnb     P3_RXD,baud_edge1   ; 30 B0 FA  wait for P3.0 HIGH
        acall   baud_capture        ; D1 E4     record TL0:TH0, reset Timer 0
baud_edge2:
        jb      0x8D,baud_clear     ; 20 8D E7  overflow -> re-measure
        jb      P3_RXD,baud_edge2   ; 20 B0 FA  wait for P3.0 LOW
        acall   baud_capture        ; D1 E4
baud_edge3:
        jb      0x8D,baud_clear     ; 20 8D DF  overflow -> re-measure
        jnb     P3_RXD,baud_edge3   ; 30 B0 FA  wait for P3.0 HIGH
        acall   baud_capture        ; D1 E4
baud_edge4:
        jb      0x8D,baud_validate  ; 20 8D 14  overflow -> skip to validation
        jb      P3_RXD,baud_edge4   ; 20 B0 FA  wait for P3.0 LOW
        sjmp    baud_clear          ; 80 D2     too many edges -> re-measure

; --- edge-capture subroutine: snapshot TL0:TH0 into buffer, reset Timer 0 ---
baud_capture:
        clr     TCON_TR0            ; C2 8C     TR0 = stop Timer 0
        mov     @R0,SFR_TL0        ; A6 8A     save TL0 into buffer[R0]
        inc     R0                  ; 08
        mov     @R0,SFR_TH0        ; A6 8C     save TH0 into buffer[R0]
        mov     SFR_TL0,A           ; F5 8A     TL0 = 0 (reset)
        mov     SFR_TH0,A           ; F5 8C     TH0 = 0
        setb    TCON_TR0            ; D2 8C     TR0 = restart Timer 0
        inc     R0                  ; 08
        ret                         ; 22

; --- normalize and validate ---
baud_validate:
        mov     R7,#0x01            ; 7F 01     shift count = 1
baud_norm_outer:
        mov     A,R2                ; EA        A = captured run
        jz      baud_check          ; 60 12     zero -> go check
        mov     R0,#0x06            ; 78 06     point to end of buffer
baud_norm_shift:
        clr     C                   ; C3        clear carry for shift
        mov     A,@R0               ; E6        load high/low
        rrc     A                   ; 13        >> 1
        mov     @R0,A               ; F6        store back
        dec     R0                  ; 18
        mov     A,@R0               ; E6
        rrc     A                   ; 13
        mov     @R0,A               ; F6
        djnz    R0,baud_norm_shift  ; D8 F6     next pair
        clr     C                   ; C3
        mov     A,R7                ; EF
        rlc     A                   ; 33        shift count <<= 1
        mov     R7,A                ; FF
        sjmp    baud_norm_outer     ; 80 EB
baud_check:
        mov     A,R1                ; E9        A = run width [R1]
        mov     SFR_B,#0x06         ; 75 F0 06  B = 6
        div     AB                  ; 84        A = run/6
        add     A,#0x08             ; 24 08     A += 8
        anl     A,#0xF0             ; 54 F0     mask low nibble
        cjne    A,#0x20,baud_clear  ; B4 20 A0  != 0x20 -> re-measure
        mov     A,R3                ; EB        check run 2
        add     A,#0x08             ; 24 08
        anl     A,#0xF0             ; 54 F0
        cjne    A,#0x20,baud_clear  ; B4 20 98  != 0x20 -> re-measure
        mov     A,R5                ; ED        check run 3
        clr     C                   ; C3
        rrc     A                   ; 13
        add     A,#0x08             ; 24 08
        anl     A,#0xF0             ; 54 F0
        cjne    A,#0x20,baud_clear  ; B4 20 8E  != 0x20 -> re-measure

; --- baud locked: derive TH1, start UART ---
        mov     A,R7                ; EF        A = derived rate
        dec     A                   ; 14        A -= 1
        cpl     A                   ; F4        A = ~(A-1) -> TH1 reload
        mov     SFR_TH1,A           ; F5 8D     TH1 = derived baud reload
        setb    TCON_TR1            ; D2 8E     TR1 = start Timer 1 (baud gen)
        mov     SFR_SBUF,#0x15      ; 75 99 15  transmit 0x15 (init-OK ACK)
baud_wait_tx:
        jnb     0x99,baud_wait_tx   ; 30 99 FD  wait for TI (transmit done)
        clr     0x99                ; C2 99     clear TI
        setb    0x18                ; D2 18     bit 0x23.0 (timer/serial event) [INFER]
                                    ;           NB: bit addr 0x18 == 0x23.0, NOT the
                                    ;           SER_TIMEOUT byte 0x18 (byte-vs-bit)
        mov     SFR_IE,#0x17        ; 75 A8 17  IE = 0x17 -> ES+EX1+ET0+EX0

;------------------------------------------------------------------------------
; (13) FINAL INIT: timer tick prescaler, Timer-0 reload, enable ints, kick
;      one feedback conversion, then fall into the main loop.           [BYTE]
;------------------------------------------------------------------------------
init_finish:
        mov     DEC_CONST_10,#0x0A  ; 75 1D 0A  Timer0 tick prescaler (/10)
        mov     SFR_TH0,#0xE8      ; 75 8C E8  TH0 = 0xE8 Timer 0 reload
        setb    TCON_TR0            ; D2 8C     TR0 = start Timer 0 (system tick)
        setb    SYS_AXIS_ENABLE     ; D2 00     0x20.0 = axis subsystem enable
        clr     A                   ; E4
        mov     SFR_DPH,#DEV_ADC_START ; 75 83 58  DPH -> ADC ch A8=0 [HW]
        movx    @DPTR,A             ; F0        select axis 0 feedback
        setb    IE_EA               ; D2 AF     EA = 1 -> global interrupts ON
; 074D: falls through into main loop (main.asm)
