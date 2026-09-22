;==============================================================================
; ROB3 FIRMWARE — RESET + INTERRUPT VECTOR TABLE (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the reset + interrupt vector table (0x0000..0x0037) and
;                    the board/device-map reference header. Part of the 1:1
;                    annotated source assembled by rob3.asm.
;
; PROVENANCE OF ANNOTATIONS
;   [BYTE]  = Verified by decoding the raw ROM bytes (xxd of the .BIN).
;   [SIM]   = Verified dynamically in the ucSim/s51 simulator.
;   [HW]    = Confirmed by cross-referencing the hardware schematic docs under
;             hardware/board/.
;   [INFER] = Inferred from context / hardware; NOT yet proven.
;
; NOTE ON THE ORIGINAL disasm51 LISTING (firmware/src/main.asm)
;   The auto-generated main.asm mislabels the reset target as "jump_05FF"
;   and renders the 0xFF EPROM padding as endless "MOV R7,A". The byte-level
;   truth is that the reset vector is  LJMP 0x0600  and real init code begins
;   at 0x0600. Addresses in this tree are the true byte offsets. [BYTE]
;
;------------------------------------------------------------------------------
; CONTROL BOARD IC COMPLEMENT (as reported for this hardware)
;------------------------------------------------------------------------------
;   8031            - Host CPU (MCS-51), external ROM/RAM bus, XTAL 11.0592 MHz
;   EPROM 8K        - M2764A, holds this firmware (code memory)
;   SRAM 8K         - External data RAM; stores robot programs (probed at boot)
;   8255            - Programmable Peripheral Interface (Ports A/B/C + control)
;   74LS138         - 3-to-8 decoder. [HW] Generates the device selects seen
;                     as DPH values on MOVX. Real CPU selects are B=A11, C=A12;
;                     input A is tied to output Y4 (self-latch, not an address
;                     line). See EXTERNAL DEVICE MAP for the DPH->Yn table.
;   74HC373         - Octal transparent latch. [INFER] AD0-AD7 address latch for
;                     the 8031 multiplexed low-address/data bus.
;   74LS244         - Octal buffer/line driver. [INFER] Input read path
;                     (e.g. keyboard / feedback bus onto the data bus).
;   L293 x3         - Dual H-bridge motor drivers. 3 x 2 channels = up to 6
;                     motor channels -> matches the 6 robot axes driven from
;                     8255 Port A / Port C. [INFER on exact channel mapping]
;   ADC             - ADC0808/0809 8-bit, 8-channel SAR ADC. [HW] Axis position
;                     feedback read via MOVX at DPH=0x58/0x59 (74LS138 Y6/Y7),
;                     A8 = channel line ADD-A. Feedback is ANALOG, not a
;                     quadrature encoder. EOC -> INT1 (8031 pin 13).
;   M34004          - [INFER] Function not yet confirmed (driver/array?).
;   MAX1044         - Switched-capacitor voltage inverter; generates a negative
;                     rail (e.g. for the ADC / analog front end). Not directly
;                     firmware-visible.
;   MM74C04N x2     - Hex inverters. [INFER] General logic / signal inversion.
;   74HC14          - Hex Schmitt-trigger inverter. [INFER] Input signal
;                     conditioning (e.g. the P3.0 serial/baud-detect input).
;
;------------------------------------------------------------------------------
; EXTERNAL DEVICE MAP (DPH selects the device on MOVX @DPTR)
;   DPH   Device                                   Confirmation
;   0x48  Aux / axis-select latch (74LS138 Y2/Y3)  [HW] decode: A12=0,A11=1
;   0x50  8255 Port A  (motor phase outputs)       [BYTE] init writes 0x00
;   0x51  8255 Port B  (general digital out)       [BYTE] init writes 0xFF
;   0x52  8255 Port C  (motor phase outputs)       [BYTE] init writes 0x00
;   0x53  8255 Control register                    [BYTE] init writes 0x80
;   0x58  ADC / axis feedback, channel A8=0        [BYTE] init writes 0x00
;   0x59  ADC / axis feedback, channel A8=1        [BYTE] init writes 0x01
;   0x80  External SRAM window base                [BYTE] probe starts here
;   0xA0  External SRAM (alt page)                 [BYTE] probe fallback
;
;   DECODER DERIVATION (confirmed against hardware/board/74LS138.md):        [HW]
;     The 74LS138 real CPU selects are B = A11 and C = A12; input A (pin 1) is
;     tied to output Y4 (pin 11) as a self-latch, so A is NOT a CPU address
;     line. A14/A15 gate peripheral space (A14=1,A15=0) vs external SRAM
;     (A15=1). Thus the peripheral DPH values decode purely on A11/A12:
;         A12=0,A11=1 -> Y2/Y3 region -> DPH 0x48 (aux/axis latch)
;         A12=1,A11=0 -> Y4/Y5 region -> DPH 0x50..0x53 (8255; A0/A1 pick port)
;         A12=1,A11=1 -> Y6/Y7 region -> DPH 0x58/0x59 (ADC; Y7 -> ADC pin 22)
;     0x50..0x53 are distinguished by the 8255's OWN A0/A1, not the decoder.
;     0x58 vs 0x59 differ only in A8 = the ADC channel line ADD A (only ADD A
;     is CPU-driven; ADD B/ADD C are strapped). See hardware/board/adc.md.
;------------------------------------------------------------------------------
; INTERRUPT VECTORS (actual targets, verified from ROM bytes)
;   0x0000 RESET   -> LJMP 0x0600  (init)
;   0x0003 EXT0    -> LJMP 0x0040  (EMERGENCY-OFF handler; INT0 = P3.2, active LOW)
;   0x000B TIMER0  -> LJMP 0x0080  (system tick ISR)
;   0x0013 EXT1    -> LJMP 0x00C0  (axis servo ISR)
;   0x001B TIMER1  -> (0xFF, no handler installed)
;   0x0023 SERIAL  -> 0xFF fillers, fall through to LJMP 0x0300 at 0x0035
;                     -> RS232 UART ISR at 0x0300 (ES enabled via IE=0x17)
;==============================================================================

;==============================================================================
; VECTOR TABLE
;==============================================================================

;   NOTE ON THE 0xFF PADDING: the unused EPROM bytes between these vectors are
;   0xFF. The build does NOT emit them here — objcopy's --gap-fill=0xFF fills
;   any address this source leaves undefined, which reproduces the EPROM 1:1.
;   Only NON-0xFF bytes (the LJMPs and the dead data at 0x0020) are emitted.

        .org    0x0000
reset_vector:
        ljmp    init_start          ; 02 06 00  RESET -> init_start (init.asm)  [BYTE]

        .org    0x0003
ext_int0_vector:
        ljmp    emergency_off       ; 02 00 40  EXT0 -> EMERGENCY-OFF (ext0_estop.asm) [BYTE]

        .org    0x000B
timer0_vector:
        ljmp    timer0_isr          ; 02 00 80  Timer 0 system tick (timer0_tick.asm) [BYTE]

        .org    0x0013
ext_int1_vector:
        ljmp    0x00C0              ; 02 00 C0  EXT1 axis servo ISR (ext1_servo.asm) [BYTE]

;       0x001B  TIMER1 vector: 0xFF padding (objcopy fill). Timer 1 is only the
;       UART baud generator; its interrupt (ET1) is NEVER enabled. [BYTE]

        .org    0x0020
timer1_deaddata:
        .db     0x00,0x12,0x22      ; 00 12 22  DEAD DATA (never reached).    [BYTE]
                                    ; A disassembler shows NOP / LCALL 0x22FF,
                                    ; but nothing branches to 0x0020 and the CPU
                                    ; never vectors to 0x001B. LCALL 0x22FF also
                                    ; targets outside the 8 KB ROM. Emitted here
                                    ; because it is NON-0xFF and must match 1:1.

;       0x0023  SERIAL vector: 0xFF padding; execution FALLS THROUGH the 0xFF
;       fillers to the real LJMP at 0x0035 (see below).                      [BYTE]

        .org    0x0035
serial_vector_jmp:
        ljmp    0x0300              ; 02 03 00  -> RS232 UART ISR (rs232.asm) [BYTE]
;
;   The serial interrupt IS enabled: init executes  MOV IE,#0x17  at 0x0739
;   (ES+EX1+ET0+EX0). Handler prologue @ 0x0300 confirms the UART ISR:
;       0300: C0 D0        PUSH PSW
;       0302: D2 D4        SETB PSW.4        ; ISR register bank
;       0305: 30 98 4A     JNB  SCON.0(RI),..; test receive flag
;       0308: C2 98        CLR  SCON.0(RI)   ; ack received byte
;       030A: E5 99        MOV  A,SBUF       ; read received byte
;       030C: 75 18 14     MOV  0x18,#0x14   ; reload serial timeout counter
;
;   CORRECTION HISTORY: an earlier draft first claimed "LJMP 0x0300 at 0x0023"
;   (wrong address), then wrongly claimed "no serial handler exists". Both were
;   incorrect. The truth (verified from ROM bytes): vector slot is 0xFF, the
;   LJMP 0x0300 sits at 0x0035 reached by fall-through, and the ISR at 0x0300
;   is the RS232 UART handler. [BYTE]


