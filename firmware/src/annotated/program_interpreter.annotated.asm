;==============================================================================
; ROB3 FIRMWARE — PROGRAM INTERPRETER (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the stored-program subsystem:
;                    the label-table PREPROCESSOR (0x0803), the instruction
;                    EXECUTOR (0x0941, reached via the motion-executor gate at
;                    0x08FF), and the label->PC RESOLVER (0x0A33). Companion to
;                    rs232_serial.annotated.asm (the same programs are uploaded
;                    over serial via the 0x81 block command and started by the
;                    hdr.7=1 system commands) and the Teachbox instruction set
;                    in hardware/teachbox/README.md.
;
; PROVENANCE TAGS
;   [BYTE] = decoded directly from the ROM bytes.
;   [HW]   = confirmed against a hardware/manual doc.
;   [SIM]  = confirmed by running the ROM in ucSim and observing state.
;   [INFER]= inferred from context; treat as a hypothesis to confirm.
;   DEFAULT: unmarked instruction lines are [BYTE]. The per-opcode SEMANTICS
;   (which teachbox instruction each encoding is) are [INFER] unless a [SIM]
;   note upgrades them; the control flow, PC handling, and SRAM layout are
;   [BYTE]/[SIM].
;
;==============================================================================
; BIG PICTURE — how a stored program works                          [BYTE][SIM]
;------------------------------------------------------------------------------
; Programs live in the external HM6264 8 KB SRAM (page base in IRAM 0x3E = 0x80,
; body page 0x3F = 0x81):
;   0x8000..0x80FF (page 0x80) : LABEL TABLE — 2 bytes per label (a 16-bit PC),
;                                so up to ~128 labels (manual: MARK m = 0..118).
;                                Header/count + end-marker live at 0x80EE..0x80FF.
;   0x8100..0x9FFF (pages 0x81+): PROGRAM BODY (instruction stream). PC = the
;                                16-bit IRAM pair 0x66(lo):0x67(hi).            [SIM]
;
; INSTRUCTION ENCODING = the SAME command-byte bit fields the RS-232 handler
; decodes (see rs232_serial.annotated.asm): the executor reads one instruction
; opcode into 0x27, then branches on ACC bits .7/.6/.5/.4 and the low-3 axis
; field exactly like rx_dispatch's cmd_class0. So a "POS all axes" program step
; is the same 0x47/0x07/0x77-style byte followed by its operand bytes. Most
; instructions occupy a FIXED 8-byte slot (PC += 8 at 0x0A01/0x0A03); a few
; advance differently.                                                     [SIM]
;   [SIM] Verified: a 0x47 opcode at 0x8100 is fetched into 0x27 and the PC
;   advances 0x8100 -> 0x8108 (an 8-byte instruction slot).
;
; The teachbox editor and the serial 0x81 uploader write the SAME bytes into
; this store; the executor here runs them. Opcodes seen in the preprocessor:
; 0x1F = MARK (label definition), 0x36 = a 3-byte instruction (see below).
;
;==============================================================================
        .include "rob3.inc"

;==============================================================================
; PREPROCESSOR / LABEL-TABLE BUILDER  prog_prepare (0x0803)         [BYTE][INFER]
;   Entry 0x07FF: if no program loaded (0x28.1 clear) -> prog_end (0x0880).
;   Entry 0x0803: (re)builds the label table by scanning the program body for
;   MARK (0x1F) instructions and recording each label's PC. Also validates the
;   program header sentinel.
;==============================================================================
        org     0x07FF
prog_check:                         ; 0x07FF
        mov     R7,A                ; 07FF: FF (padding-decoded; harmless)
        jnb     0x28.1,prog_end     ; 0800: 30 41 xx  no program loaded -> 0x0880
        ; falls into 0x0802/0x0803

        org     0x0802
prog_prepare_e:                     ; 0x0802 (alt entry)
        mov     R5,#0xD2            ; 0802: 7D D2 (overlap byte; real entry is 0x0803)
        org     0x0803
prog_prepare:                       ; 0x0803
        setb    0x28.1              ; 0803: mark program loaded
        mov     0x83,0x3E           ; 0805: DPH = 0x3E (label-table page 0x80)
        mov     0x82,#0xEE          ; 0808: DPL = 0xEE
pp_clear:                           ; 0x080B  clear the label table 0x80EE..0x8000
        clr     A
        movx    @DPTR,A             ; 080C: label-table[DPL] = 0
        dec     0x82                ; DPL--
        mov     A,0x3F              ; (writes body-page marker interleaved)
        movx    @DPTR,A
        djnz    0x82,pp_clear       ; 0812: until DPL wraps
        clr     A
        movx    @DPTR,A
        mov     0x82,#0xFE          ; DPL = 0xFE (program header slot)
        movx    A,@DPTR             ; read header byte
        mov     0x7E,A
        mov     0x76,A
        anl     A,#0x07             ; low 3 bits
        jnz     prog_end            ; 0824: malformed header -> 0x0880          [INFER]
        inc     DPTR
        movx    A,@DPTR             ; read second header byte (length hi)
        mov     0x7F,A
        orl     A,0x7E
        jz      prog_end            ; 082D: empty program -> 0x0880             [INFER]
        mov     A,0x3F
        add     A,0x7F              ; body page + length -> end page
        mov     0x77,A
        mov     0x83,A
        mov     0x82,0x7E
        movx    A,@DPTR
        cjne    A,#0x83,prog_end    ; 0838: verify end sentinel 0x83 -> else 0x0880 [INFER]

pp_scan:                            ; 0x083A  scan loop: advance, read opcode
        mov     A,#0xF8             ; 083A: -8 (advance PC by 8-byte slot, backwards scan)
pp_adv:                             ; 0x083C
        add     A,0x82              ; 083C: DPL += A
        mov     0x82,A
        jnc     pp_no_borrow        ; 083E -> 0x084E
        jnz     pp_check_end        ; -> 0x0850
        mov     A,0x83
        cjne    A,0x3F,pp_check_end ; reached body start page?
        movx    A,@DPTR
        jb      0xE0.7,prog_end     ; opcode.7 (end marker) -> 0x0880
        ret                         ; scan complete
pp_no_borrow:                       ; 0x084E
        dec     0x83                ; DPH--
pp_check_end:                       ; 0x0850
        movx    A,@DPTR             ; read opcode
        jb      0xE0.7,prog_end     ; 0850: opcode.7 set (end) -> 0x0880
        cjne    A,#0x36,pp_not36    ; 0853: opcode 0x36 -> 3-byte instr handling [INFER]
        inc     DPTR                ; skip its 3 operand bytes
        inc     DPTR
        inc     DPTR
        clr     A
        movx    @DPTR,A
        mov     A,#0xF5             ; advance -11
        sjmp    pp_adv
pp_not36:                           ; 0x0860
        cjne    A,#0x1F,pp_scan     ; 0860: opcode 0x1F = MARK (label def) else rescan [INFER]
        inc     DPTR
        movx    A,@DPTR             ; read the label number
        rl      A                   ; ×2 (2-byte label-table entries)
        dec     0x82
        xch     A,0x82
        mov     0x7E,A
        mov     0x7F,0x83
        mov     0x83,0x3E           ; label-table page 0x80
        movx    @DPTR,A             ; store current PC lo into label[m]
        inc     DPTR
        mov     A,0x7F
        movx    @DPTR,A             ; store PC hi into label[m]+1
        mov     0x83,A
        mov     0x82,0x7E
        sjmp    pp_scan             ; continue scanning

prog_end:                           ; 0x0880  finalize: write the end-marker
        anl     0x28,#0x01          ; 0880: keep only "loaded"; clear run/motion/cond
        mov     0x82,#0xFD          ; header area 0x80FD..
        mov     0x83,0x3E
        mov     A,#0x80             ; end sentinel bytes
        movx    @DPTR,A
        inc     DPTR
        clr     A
        mov     0x76,A
        mov     0x77,0x3F
        movx    @DPTR,A
        inc     DPTR
        movx    @DPTR,A
        inc     DPTR
        mov     A,#0x83             ; 0x83 sentinel
        movx    @DPTR,A
        ret

;==============================================================================
; MOTION EXECUTOR + PROGRAM-STEP GATE  motion_exec (0x08FF)          [BYTE][INFER]
;   Called every main-loop pass (0x0797). If a program is running it advances
;   axis motion, and when the current step's motion is complete it fetches and
;   executes the NEXT program instruction (prog_exec, 0x0941).
;==============================================================================
        org     0x08FF
motion_exec:                        ; 0x08FF
        mov     R7,A                ; 08FF
        jb      0x28.4,me_step      ; 0900: conditional flag set -> 0x0906
        jnb     0x28.3,me_ret       ; 0903: no motion active -> 0x0940
me_step:                            ; 0x0906
        mov     0x83,#0x51          ; 0906: DPH = 0x51 -> 8255 Port B
        mov     A,0x1F
        movx    @DPTR,A              ; refresh Port B digital-output shadow      [HW]
        mov     A,0x26              ; 0x26 = program-exec control
        jz      prog_exec           ; 090E: 0 -> fetch next instruction (0x0941)
        jnb     0xE0.0,me_wait_tim  ; 0911: control.0 clear -> timer wait (0x091E)
        mov     A,0x21              ; motion-completion check (all-axes mask)
        cjne    A,#0x3F,me_ret      ; 0916: not all -> keep waiting
        mov     A,0x2B
        jnz     me_ret              ; 091A: still moving -> wait
        sjmp    me_done             ; -> 0x093B
me_wait_tim:                        ; 0x091E  (control.1: TIM delay wait)
        jnb     0xE0.1,me_wait_in   ; 091E
        jnb     0x23.5,me_ret       ; 0921: 50 ms tick?
        clr     0x23.5
        djnz    0x1A,me_ret         ; 0926: decrement delay lo
        djnz    0x1B,me_ret         ; 0928: decrement delay hi  (TIM t x 100ms)  [INFER]
        sjmp    me_done
me_wait_in:                         ; 0x092E  (IF: wait on a digital input)
        mov     A,0x90              ; read P1 (digital inputs)                   [HW]
        jnb     0x27.0,me_wait_in2  ; 0931
        anl     A,R7
        jz      me_done             ; input low -> condition met
        ret
me_wait_in2:                        ; 0x0937
        orl     A,R7
        cjne    A,#0xFF,me_ret      ; 0937
me_done:                            ; 0x093B
        mov     0x26,#0x00          ; 093B: clear exec-control -> fetch next instr
        clr     0x28.4
me_ret:                             ; 0x0940
        ret

;==============================================================================
; INSTRUCTION EXECUTOR  prog_exec (0x0941)                          [BYTE][SIM]
;   Fetch the opcode at PC (0x66:0x67) into 0x27, decode by the command bit
;   fields (same layout as the RS-232 dispatch), apply it, advance PC.
;==============================================================================
prog_exec:                          ; 0x0941
        clr     0x28.4              ; 0941: clear conditional flag
        mov     0x82,0x66           ; DPL = PC lo
        mov     0x83,0x67           ; DPH = PC hi
        movx    A,@DPTR             ; fetch the instruction opcode              [SIM]
        mov     R0,A
        mov     0x27,A              ; 0x27 = current instruction descriptor     [SIM]
pe_decode:                          ; 0x094D
        jnb     0xE0.7,pe_class0    ; 094D: opcode.7 clear -> 0x0954
        anl     0x28,#0x03          ; 094D+: opcode.7 set = PROGRAM END -> stop  [SIM]
        ret                         ;   (clears run/motion, keeps loaded/.0).
                                    ;   [SIM] opcode 0x80 reaches here, 0x27=0x80.

; --- opcode.7=0 .6=1 : POSITIONING instruction (POS / move) ------------------
pe_class0:                          ; 0x0954
        jnb     0xE0.6,pe_lowclass  ; 0954: .6 clear -> 0x09A9
        jnb     0xE0.5,pe_pos_speed ; 0957: .5 clear -> 0x099A
        inc     DPTR
        mov     C,0xE0.3            ; ack/conditional bit -> control            [INFER]
        mov     0x26.0,C
        mov     0x28.4,C
        anl     A,#0x07             ; axis field
        cjne    A,#0x07,pe_pos_one  ; 0961: != 7 -> single axis (0x0982)
        mov     R0,#0x40            ; all axes: copy 6 target bytes -> 0x40..0x45
        mov     R7,#0x06
pe_pos_all:                         ; 0x096A
        movx    A,@DPTR
        mov     @R0,A
        inc     DPTR
        inc     R0
        djnz    R7,pe_pos_all       ; 096A
        inc     DPTR
        inc     DPTR
        mov     R0,#0x70            ; then 6 more bytes -> 0x70..0x75 (decel/spd) [INFER]
        mov     R7,#0x06
pe_pos_all2:                        ; 0x0976
        movx    A,@DPTR
        mov     @R0,A
        inc     DPTR
        inc     R0
        djnz    R7,pe_pos_all2
        mov     A,#0x3F             ; motion mask = all 6 axes
        mov     R7,#0x10
        sjmp    pe_arm_mask         ; -> 0x0993
pe_pos_one:                         ; 0x0982  single-axis positioning
        add     A,#0x40             ; target[0x40+axis]
        mov     R0,A
        movx    A,@DPTR
        mov     @R0,A               ; target = operand
        orl     0x00,#0x70          ; (bank flag)                               [INFER]
        inc     DPTR
        movx    A,@DPTR
        mov     @R0,A
        mov     R7,#0x08
        mov     A,R0
        anl     A,#0x17
        movc    A,@A+PC             ; 1<<axis bit table
pe_arm_mask:                        ; 0x0993
        orl     0x2B,A              ; set "need move" / "moving" masks
        orl     0x2C,A
        mov     A,R7
        sjmp    pe_advance          ; -> 0x0A03
pe_pos_speed:                       ; 0x099A  (.6=1 .5=0): speed/other variant
        anl     0x28,#0x07
        sjmp    pe_adv8             ; -> 0x0A01

; --- opcode.7=0 .6=0 : POS-store / OUT / TIM / IF family ---------------------
pe_lowclass:                        ; 0x09A9
        inc     DPTR
        jb      0xE0.5,pe_if_goto   ; 09AA: .5 set -> 0x09F1 (IF / GOTO / wait)
        jb      0xE0.4,pe_out_tim   ; 09AD: .4 set -> 0x09D1 (OUT / TIM)
        mov     0x21,#0x00          ; else: store CURRENT POSITION (POS/teach)  [SIM]
        mov     C,0xE0.3
        mov     0x26.0,C
        mov     0x28.4,C
        anl     A,#0x07
        cjne    A,#0x07,pe_posst_one; 09BB: != 7 -> single
        mov     R0,#0x50            ; all axes: 6 bytes -> current pos 0x50..0x55 [SIM]
        mov     R7,#0x06
        sjmp    pe_posst_cp
pe_posst_one:                       ; 0x09C4
        add     A,#0x50
        mov     R0,A
        mov     R7,#0x01
pe_posst_cp:                        ; 0x09C9
        movx    A,@DPTR
        mov     @R0,A               ; [SIM] opcode 0x07 + operands A1..A6 -> 0x50..0x55,
        inc     DPTR                ;   PC advanced 0x8100 -> 0x8108 (8-byte slot).
        inc     R0
        djnz    R7,pe_posst_cp
        sjmp    pe_adv8
pe_out_tim:                         ; 0x09D1  (.4 set)
        jb      0xE0.3,pe_tim       ; 09D1: .3 set -> TIM (0x09DE)
        anl     A,#0x03             ; OUT: k selects set/clear/toggle           [INFER]
        mov     R2,A
        movx    A,@DPTR
        mov     R0,A
        lcall   portb_write         ; 09D9: 0x07D2 -> drive Port B digital out  [HW]
        sjmp    pe_adv8
pe_tim:                             ; 0x09DE  (TIM t: set delay counters)
        jb      0xE0.2,pe_adv8      ; 09DE
        setb    0x26.1              ; mark "timer wait" mode
        setb    0x28.4
        movx    A,@DPTR
        mov     0x1A,A              ; delay lo                                   [INFER]
        inc     DPTR
        movx    A,@DPTR
        inc     A
        mov     0x1B,A              ; delay hi  (TIM t x 100ms)                  [INFER]
        sjmp    pe_adv8
pe_if_goto:                         ; 0x09F1  (.5 set: IF/GOTO)
        jnb     0xE0.4,pe_adv8      ; 09F1
        jb      0xE0.3,pe_adv8      ; 09F4
        add     A,#0xCE             ; range test
        jc      pe_if_cond          ; 09F9 -> 0x0A0C (conditional GOTO)
        movx    A,@DPTR
        mov     R7,A
        setb    0x26.2
        setb    0x28.4
pe_adv8:                            ; 0x0A01  advance PC by the 8-byte slot
        mov     A,#0x08
pe_advance:                         ; 0x0A03
        add     A,0x66              ; PC lo += A
        mov     0x66,A
        jnc     pe_ret              ; 0A08
        inc     0x67                ; carry -> PC hi
pe_ret:                             ; 0x0A0B
        ret

pe_if_cond:                         ; 0x0A0C  IF input [.] GOTO label
        movx    A,@DPTR
        mov     R0,A
        inc     DPTR
        jb      0x27.2,pe_if_lbl    ; 0A10
        movx    A,@DPTR
        jnb     0x27.0,pe_if_or     ; 0A15
        anl     A,0x90              ; AND with P1 inputs                         [HW]
        jnz     pe_adv8             ; condition false -> next instr
        sjmp    prog_goto           ; -> 0x0A33 (take the branch)
pe_if_or:                           ; 0x0A1C
        orl     A,0x90
        cjne    A,#0xFF,pe_adv8     ; 0A1C
        sjmp    prog_goto
pe_if_lbl:                          ; 0x0A23
        jnb     0x27.1,prog_goto_a  ; 0A23 -> 0x0A34
        movx    A,@DPTR             ; GOTO m , n times: decrement the counter
        mov     R7,A
        inc     DPTR
        movx    A,@DPTR
        inc     A
        cjne    A,0x07,pe_cnt_dec   ; 0A2C
        clr     A
        movx    @DPTR,A             ; counter exhausted -> fall through
        sjmp    pe_adv8
pe_cnt_dec:                         ; 0x0A32
        movx    @DPTR,A             ; store decremented counter, then take branch

;==============================================================================
; LABEL RESOLVER  prog_goto (0x0A33)                                [BYTE][SIM]
;   Resolve label m (in R0) to its stored PC and set 0x66:0x67, so the executor
;   continues at the labelled instruction (GOTO m / RUN m).
;==============================================================================
prog_goto:                          ; 0x0A33
        mov     A,R0                ; A = label number
prog_goto_a:                        ; 0x0A34
        rl      A                   ; ×2 (2-byte label-table entries)
        mov     0x82,A              ; DPL = 2*m (index into page-0x80 table)
        mov     0x83,0x3E           ; DPH = 0x3E (label-table page 0x80)
        movx    A,@DPTR
        mov     0x66,A              ; PC lo = label[m]
        inc     DPTR
        movx    A,@DPTR
        mov     0x67,A              ; PC hi = label[m]+1
        ret

;==============================================================================
; OPCODE MAP (as decoded by prog_exec / prog_prepare)               [BYTE][INFER]
;------------------------------------------------------------------------------
; Opcodes share the RS-232 command bit fields (bit7/6/5/4 + low-3 axis):
;   .7 = 1                       PROGRAM END (stop; keeps "loaded")
;   .7=0 .6=1 .5=1               POSITIONING / move-with-target (POS a . n):
;                                axis 0..5 or 7=all; targets -> 0x40.., mask armed
;   .7=0 .6=1 .5=0               position + speed variant
;   .7=0 .6=0 .5=0 .4=0          store CURRENT POSITION (teach POS)
;   .7=0 .6=0 .5=0 .4=1 .3=0     OUT k +/- (digital output via Port B)
;   .7=0 .6=0 .5=0 .4=1 .3=1     TIM t (delay t; counters 0x1A/0x1B, x100ms)
;   .7=0 .6=0 .5=1               IF i [. m] / GOTO m [. n] (branch on P1 inputs
;                                or unconditional; label via prog_goto 0x0A33)
;   0x1F                         MARK m (label definition; recorded by prog_prepare)
;   0x36                         a 3-byte instruction (skipped by the scanner)   [INFER]
; Instruction slot: most advance PC by 8 (pe_adv8); MARK/0x36 handled specially.
; The exact operand layout per opcode is [INFER] beyond the [SIM]-checked fetch
; + 8-byte advance and the label-table build; a fuller [SIM] pass (craft each
; instruction in SRAM, single-step, observe effects) is the follow-up.
;==============================================================================
