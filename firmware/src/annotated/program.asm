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
;                    rs232.asm (the same programs are uploaded
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
; decodes (see rs232.asm): the executor reads one instruction
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
        ; symbols (the inc/*.inc equates) are provided by
        ; the top file rob3.asm, which includes this region in address order.

;==============================================================================
; PREPROCESSOR / LABEL-TABLE BUILDER  prog_prepare (0x0803)         [BYTE][INFER]
;   Entry 0x07FF: if no program loaded (0x28.1 clear) -> prog_end (0x0880).
;   Entry 0x0803: (re)builds the label table by scanning the program body for
;   MARK (0x1F) instructions and recording each label's PC. Also validates the
;   program header sentinel.
;==============================================================================
        ; org 0x07FF
; prog_check:                         ; 0x07FF
        ; mov     R7,A                ; 07FF: FF (padding-decoded; harmless)
        ; jnb     0x28.1,prog_end     ; 0800: 30 41 xx  no program loaded -> 0x0880
        ; falls into 0x0802/0x0803

        ; org 0x0802
; prog_prepare_e:                     ; 0x0802 (alt entry)
        ; mov     R5,#0xD2            ; 0802: 7D D2 (overlap byte; real entry is 0x0803)
        ; org 0x0803
; prog_prepare:                       ; 0x0803
        ; setb    0x28.1              ; 0803: mark program loaded
        ; mov     0x83,0x3E           ; 0805: DPH = 0x3E (label-table page 0x80)
        ; mov     0x82,#0xEE          ; 0808: DPL = 0xEE
; pp_clear:                           ; 0x080B  clear the label table 0x80EE..0x8000
        ; clr     A
        ; movx    @DPTR,A             ; 080C: label-table[DPL] = 0
        ; dec     0x82                ; DPL--
        ; mov     A,0x3F              ; (writes body-page marker interleaved)
        ; movx    @DPTR,A
        ; djnz    0x82,pp_clear       ; 0812: until DPL wraps
        ; clr     A
        ; movx    @DPTR,A
        ; mov     0x82,#0xFE          ; DPL = 0xFE (program header slot)
        ; movx    A,@DPTR             ; read header byte
        ; mov     0x7E,A
        ; mov     0x76,A
        ; anl     A,#0x07             ; low 3 bits
        ; jnz     prog_end            ; 0824: malformed header -> 0x0880          [INFER]
        ; inc     DPTR
        ; movx    A,@DPTR             ; read second header byte (length hi)
        ; mov     0x7F,A
        ; orl     A,0x7E
        ; jz      prog_end            ; 082D: empty program -> 0x0880             [INFER]
        ; mov     A,0x3F
        ; add     A,0x7F              ; body page + length -> end page
        ; mov     0x77,A
        ; mov     0x83,A
        ; mov     0x82,0x7E
        ; movx    A,@DPTR
        ; cjne    A,#0x83,prog_end    ; 0838: verify end sentinel 0x83 -> else 0x0880 [INFER]

; pp_scan:                            ; 0x083A  scan loop: advance, read opcode
        ; mov     A,#0xF8             ; 083A: -8 (advance PC by 8-byte slot, backwards scan)
; pp_adv:                             ; 0x083C
        ; add     A,0x82              ; 083C: DPL += A
        ; mov     0x82,A
        ; jnc     pp_no_borrow        ; 083E -> 0x084E
        ; jnz     pp_check_end        ; -> 0x0850
        ; mov     A,0x83
        ; cjne    A,0x3F,pp_check_end ; reached body start page?
        ; movx    A,@DPTR
        ; jb      0xE0.7,prog_end     ; opcode.7 (end marker) -> 0x0880
        ; ret                         ; scan complete
; pp_no_borrow:                       ; 0x084E
        ; dec     0x83                ; DPH--
; pp_check_end:                       ; 0x0850
        ; movx    A,@DPTR             ; read opcode
        ; jb      0xE0.7,prog_end     ; 0850: opcode.7 set (end) -> 0x0880
        ; cjne    A,#0x36,pp_not36    ; 0853: opcode 0x36 -> 3-byte instr handling [INFER]
        ; inc     DPTR                ; skip its 3 operand bytes
        ; inc     DPTR
        ; inc     DPTR
        ; clr     A
        ; movx    @DPTR,A
        ; mov     A,#0xF5             ; advance -11
        ; sjmp    pp_adv
; pp_not36:                           ; 0x0860
        ; cjne    A,#0x1F,pp_scan     ; 0860: opcode 0x1F = MARK (label def) else rescan [INFER]
        ; inc     DPTR
        ; movx    A,@DPTR             ; read the label number
        ; rl      A                   ; ×2 (2-byte label-table entries)
        ; dec     0x82
        ; xch     A,0x82
        ; mov     0x7E,A
        ; mov     0x7F,0x83
        ; mov     0x83,0x3E           ; label-table page 0x80
        ; movx    @DPTR,A             ; store current PC lo into label[m]
        ; inc     DPTR
        ; mov     A,0x7F
        ; movx    @DPTR,A             ; store PC hi into label[m]+1
        ; mov     0x83,A
        ; mov     0x82,0x7E
        ; sjmp    pp_scan             ; continue scanning

; prog_end:                           ; 0x0880  finalize: write the end-marker
        ; anl     0x28,#0x01          ; 0880: keep only "loaded"; clear run/motion/cond
        ; mov     0x82,#0xFD          ; header area 0x80FD..
        ; mov     0x83,0x3E
        ; mov     A,#0x80             ; end sentinel bytes
        ; movx    @DPTR,A
        ; inc     DPTR
        ; clr     A
        ; mov     0x76,A
        ; mov     0x77,0x3F
        ; movx    @DPTR,A
        ; inc     DPTR
        ; movx    @DPTR,A
        ; inc     DPTR
        ; mov     A,#0x83             ; 0x83 sentinel
        ; movx    @DPTR,A
        ; ret

;==============================================================================
; MOTION EXECUTOR + PROGRAM-STEP GATE  motion_exec (0x08FF)          [BYTE][INFER]
;   Called every main-loop pass (0x0797). If a program is running it advances
;   axis motion, and when the current step's motion is complete it fetches and
;   executes the NEXT program instruction (prog_exec, 0x0941).
;==============================================================================
        .org    0x0800
        jnb 0x41, L_0880                    ; 30 41 7D  0800
        setb 0x41                           ; D2 41  0803
        mov 0x83, 0x3E                      ; 85 3E 83  0805
        mov 0x82, #0xEE                     ; 75 82 EE  0808
L_080B:
        clr A                               ; E4  080B
        movx @DPTR, A                       ; F0  080C
        dec 0x82                            ; 15 82  080D
        mov A, 0x3F                         ; E5 3F  080F
        movx @DPTR, A                       ; F0  0811
        djnz 0x82, L_080B                   ; D5 82 F6  0812
        clr A                               ; E4  0815
        movx @DPTR, A                       ; F0  0816
        mov 0x82, #0xFE                     ; 75 82 FE  0817
        movx A, @DPTR                       ; E0  081A
        mov 0x7E, A                         ; F5 7E  081B
        mov 0x76, A                         ; F5 76  081D
        anl A, #0x07                        ; 54 07  081F
        jnz L_0880                          ; 70 5D  0821
        inc DPTR                            ; A3  0823
        movx A, @DPTR                       ; E0  0824
        mov 0x7F, A                         ; F5 7F  0825
        orl A, 0x7E                         ; 45 7E  0827
        jz L_0880                           ; 60 55  0829
        mov A, 0x3F                         ; E5 3F  082B
        add A, 0x7F                         ; 25 7F  082D
        mov 0x77, A                         ; F5 77  082F
        mov 0x83, A                         ; F5 83  0831
        mov 0x82, 0x7E                      ; 85 7E 82  0833
        movx A, @DPTR                       ; E0  0836
        cjne A, #0x83, L_0880               ; B4 83 46  0837
L_083A:
        mov A, #0xF8                        ; 74 F8  083A
L_083C:
        add A, 0x82                         ; 25 82  083C
        mov 0x82, A                         ; F5 82  083E
        jnc L_084E                          ; 50 0C  0840
        jnz L_0850                          ; 70 0C  0842
        mov A, 0x83                         ; E5 83  0844
        cjne A, 0x3F, L_0850                ; B5 3F 07  0846
        movx A, @DPTR                       ; E0  0849
        jb 0xE7, L_0880                     ; 20 E7 33  084A
        ret                                 ; 22  084D
L_084E:
        dec 0x83                            ; 15 83  084E
L_0850:
        movx A, @DPTR                       ; E0  0850
        jb 0xE7, L_0880                     ; 20 E7 2C  0851
        cjne A, #0x36, L_0860               ; B4 36 09  0854
        inc DPTR                            ; A3  0857
        inc DPTR                            ; A3  0858
        inc DPTR                            ; A3  0859
        clr A                               ; E4  085A
        movx @DPTR, A                       ; F0  085B
        mov A, #0xF5                        ; 74 F5  085C
        sjmp L_083C                         ; 80 DC  085E
L_0860:
        cjne A, #0x1F, L_083A               ; B4 1F D7  0860
        inc DPTR                            ; A3  0863
        movx A, @DPTR                       ; E0  0864
        rl A                                ; 23  0865
        dec 0x82                            ; 15 82  0866
        xch A, 0x82                         ; C5 82  0868
        mov 0x7E, A                         ; F5 7E  086A
        mov 0x7F, 0x83                      ; 85 83 7F  086C
        mov 0x83, 0x3E                      ; 85 3E 83  086F
        movx @DPTR, A                       ; F0  0872
        inc DPTR                            ; A3  0873
        mov A, 0x7F                         ; E5 7F  0874
        movx @DPTR, A                       ; F0  0876
        mov 0x83, A                         ; F5 83  0877
        mov 0x82, 0x7E                      ; 85 7E 82  0879
        sjmp L_083A                         ; 80 BC  087C
        mov R7, A                           ; FF  087E
        mov R7, A                           ; FF  087F
L_0880:
        anl 0x28, #0x01                     ; 53 28 01  0880
        mov 0x82, #0xFD                     ; 75 82 FD  0883
        mov 0x83, 0x3E                      ; 85 3E 83  0886
        mov A, #0x80                        ; 74 80  0889
        movx @DPTR, A                       ; F0  088B
        inc DPTR                            ; A3  088C
        clr A                               ; E4  088D
        mov 0x76, A                         ; F5 76  088E
        mov 0x77, 0x3F                      ; 85 3F 77  0890
        movx @DPTR, A                       ; F0  0893
        inc DPTR                            ; A3  0894
        movx @DPTR, A                       ; F0  0895
        inc DPTR                            ; A3  0896
        mov A, #0x83                        ; 74 83  0897
        movx @DPTR, A                       ; F0  0899
        ret                                 ; 22  089A
        mov R7, A                           ; FF  089B
        mov R7, A                           ; FF  089C
        mov R7, A                           ; FF  089D
        mov R7, A                           ; FF  089E
        mov R7, A                           ; FF  089F
        mov R7, A                           ; FF  08A0
        mov R7, A                           ; FF  08A1
        mov R7, A                           ; FF  08A2
        mov R7, A                           ; FF  08A3
        mov R7, A                           ; FF  08A4
        mov R7, A                           ; FF  08A5
        mov R7, A                           ; FF  08A6
        mov R7, A                           ; FF  08A7
        mov R7, A                           ; FF  08A8
        mov R7, A                           ; FF  08A9
        mov R7, A                           ; FF  08AA
        mov R7, A                           ; FF  08AB
        mov R7, A                           ; FF  08AC
        mov R7, A                           ; FF  08AD
        mov R7, A                           ; FF  08AE
        mov R7, A                           ; FF  08AF
        mov R7, A                           ; FF  08B0
        mov R7, A                           ; FF  08B1
        mov R7, A                           ; FF  08B2
        mov R7, A                           ; FF  08B3
        mov R7, A                           ; FF  08B4
        mov R7, A                           ; FF  08B5
        mov R7, A                           ; FF  08B6
        mov R7, A                           ; FF  08B7
        mov R7, A                           ; FF  08B8
        mov R7, A                           ; FF  08B9
        mov R7, A                           ; FF  08BA
        mov R7, A                           ; FF  08BB
        mov R7, A                           ; FF  08BC
        mov R7, A                           ; FF  08BD
        mov R7, A                           ; FF  08BE
        mov R7, A                           ; FF  08BF
        mov R7, A                           ; FF  08C0
        mov R7, A                           ; FF  08C1
        mov R7, A                           ; FF  08C2
        mov R7, A                           ; FF  08C3
        mov R7, A                           ; FF  08C4
        mov R7, A                           ; FF  08C5
        mov R7, A                           ; FF  08C6
        mov R7, A                           ; FF  08C7
        mov R7, A                           ; FF  08C8
        mov R7, A                           ; FF  08C9
        mov R7, A                           ; FF  08CA
        mov R7, A                           ; FF  08CB
        mov R7, A                           ; FF  08CC
        mov R7, A                           ; FF  08CD
        mov R7, A                           ; FF  08CE
        mov R7, A                           ; FF  08CF
        mov R7, A                           ; FF  08D0
        mov R7, A                           ; FF  08D1
        mov R7, A                           ; FF  08D2
        mov R7, A                           ; FF  08D3
        mov R7, A                           ; FF  08D4
        mov R7, A                           ; FF  08D5
        mov R7, A                           ; FF  08D6
        mov R7, A                           ; FF  08D7
        mov R7, A                           ; FF  08D8
        mov R7, A                           ; FF  08D9
        mov R7, A                           ; FF  08DA
        mov R7, A                           ; FF  08DB
        mov R7, A                           ; FF  08DC
        mov R7, A                           ; FF  08DD
        mov R7, A                           ; FF  08DE
        mov R7, A                           ; FF  08DF
        mov R7, A                           ; FF  08E0
        mov R7, A                           ; FF  08E1
        mov R7, A                           ; FF  08E2
        mov R7, A                           ; FF  08E3
        mov R7, A                           ; FF  08E4
        mov R7, A                           ; FF  08E5
        mov R7, A                           ; FF  08E6
        mov R7, A                           ; FF  08E7
        mov R7, A                           ; FF  08E8
        mov R7, A                           ; FF  08E9
        mov R7, A                           ; FF  08EA
        mov R7, A                           ; FF  08EB
        mov R7, A                           ; FF  08EC
        mov R7, A                           ; FF  08ED
        mov R7, A                           ; FF  08EE
        mov R7, A                           ; FF  08EF
        mov R7, A                           ; FF  08F0
        mov R7, A                           ; FF  08F1
        mov R7, A                           ; FF  08F2
        mov R7, A                           ; FF  08F3
        mov R7, A                           ; FF  08F4
        mov R7, A                           ; FF  08F5
        mov R7, A                           ; FF  08F6
        mov R7, A                           ; FF  08F7
        mov R7, A                           ; FF  08F8
        mov R7, A                           ; FF  08F9
        mov R7, A                           ; FF  08FA
        mov R7, A                           ; FF  08FB
        mov R7, A                           ; FF  08FC
        mov R7, A                           ; FF  08FD
        mov R7, A                           ; FF  08FE
        mov R7, A                           ; FF  08FF
        jb 0x44, L_0906                     ; 20 44 03  0900
        jnb 0x43, L_0940                    ; 30 43 3A  0903
L_0906:
        mov 0x83, #0x51                     ; 75 83 51  0906
        mov A, 0x1F                         ; E5 1F  0909
        movx @DPTR, A                       ; F0  090B
        mov A, 0x26                         ; E5 26  090C
        jz L_0941                           ; 60 31  090E
        jnb 0xE0, L_091E                    ; 30 E0 0B  0910
        mov A, 0x21                         ; E5 21  0913
        cjne A, #0x3F, L_0940               ; B4 3F 28  0915
        mov A, 0x2B                         ; E5 2B  0918
        jnz L_0940                          ; 70 24  091A
        sjmp L_093B                         ; 80 1D  091C
L_091E:
        jnb 0xE1, L_092E                    ; 30 E1 0D  091E
        jnb 0x1D, L_0940                    ; 30 1D 1C  0921
        clr 0x1D                            ; C2 1D  0924
        djnz 0x1A, L_0940                   ; D5 1A 17  0926
        djnz 0x1B, L_0940                   ; D5 1B 14  0929
        sjmp L_093B                         ; 80 0D  092C
L_092E:
        mov A, 0x90                         ; E5 90  092E
        jnb 0x38, L_0937                    ; 30 38 04  0930
        anl A, R7                           ; 5F  0933
        jz L_093B                           ; 60 05  0934
        ret                                 ; 22  0936
L_0937:
        orl A, R7                           ; 4F  0937
        cjne A, #0xFF, L_0940               ; B4 FF 05  0938
L_093B:
        mov 0x26, #0x00                     ; 75 26 00  093B
        clr 0x44                            ; C2 44  093E
L_0940:
        ret                                 ; 22  0940
L_0941:
        clr 0x44                            ; C2 44  0941
        mov 0x82, 0x66                      ; 85 66 82  0943
        mov 0x83, 0x67                      ; 85 67 83  0946
        movx A, @DPTR                       ; E0  0949
        mov R0, A                           ; F8  094A
        mov 0x27, A                         ; F5 27  094B
L_094D:
        jnb 0xE7, L_0954                    ; 30 E7 04  094D
        anl 0x28, #0x03                     ; 53 28 03  0950
        ret                                 ; 22  0953
L_0954:
        jnb 0xE6, 0x09A9                    ; 30 E6 52  0954
        jnb 0xE5, L_099A                    ; 30 E5 40  0957
        inc DPTR                            ; A3  095A
        mov C, 0xE3                         ; A2 E3  095B
        mov 0x30, C                         ; 92 30  095D
        mov 0x44, C                         ; 92 44  095F
        anl A, #0x07                        ; 54 07  0961
        cjne A, #0x07, L_0982               ; B4 07 1C  0963
        mov R0, #0x40                       ; 78 40  0966
        mov R7, #0x06                       ; 7F 06  0968
L_096A:
        movx A, @DPTR                       ; E0  096A
        mov @R0, A                          ; F6  096B
        inc DPTR                            ; A3  096C
        inc R0                              ; 08  096D
        djnz R7, L_096A                     ; DF FA  096E
        inc DPTR                            ; A3  0970
        inc DPTR                            ; A3  0971
        mov R0, #0x70                       ; 78 70  0972
        mov R7, #0x06                       ; 7F 06  0974
L_0976:
        movx A, @DPTR                       ; E0  0976
        mov @R0, A                          ; F6  0977
        inc DPTR                            ; A3  0978
        inc R0                              ; 08  0979
        djnz R7, L_0976                     ; DF FA  097A
        mov A, #0x3F                        ; 74 3F  097C
        mov R7, #0x10                       ; 7F 10  097E
        sjmp L_0993                         ; 80 11  0980
L_0982:
        add A, #0x40                        ; 24 40  0982
        mov R0, A                           ; F8  0984
        movx A, @DPTR                       ; E0  0985
        mov @R0, A                          ; F6  0986
        orl 0x00, #0x70                     ; 43 00 70  0987
        inc DPTR                            ; A3  098A
        movx A, @DPTR                       ; E0  098B
        mov @R0, A                          ; F6  098C
        mov R7, #0x08                       ; 7F 08  098D
        mov A, R0                           ; E8  098F
        anl A, #0x17                        ; 54 17  0990
        movc A, @A + PC                     ; 83  0992
L_0993:
        orl 0x2B, A                         ; 42 2B  0993
        orl 0x2C, A                         ; 42 2C  0995
        mov A, R7                           ; EF  0997
        sjmp L_0A03                         ; 80 69  0998
L_099A:
        anl 0x28, #0x07                     ; 53 28 07  099A
        sjmp L_0A01                         ; 80 62  099D
        mov R7, A                           ; FF  099F
        mov R7, A                           ; FF  09A0
        mov R7, A                           ; FF  09A1
        mov R7, A                           ; FF  09A2
        ajmp 0x0802                         ; 01 02  09A3
        inc A                               ; 04  09A5
        inc R0                              ; 08  09A6
        jbc 0x20, L_094D                    ; 10 20 A3  09A7
        jb 0xE5, L_09F1                     ; 20 E5 44  09AA
        jb 0xE4, L_09D1                     ; 20 E4 21  09AD
        mov 0x21, #0x00                     ; 75 21 00  09B0
        mov C, 0xE3                         ; A2 E3  09B3
        mov 0x30, C                         ; 92 30  09B5
        mov 0x44, C                         ; 92 44  09B7
        anl A, #0x07                        ; 54 07  09B9
        cjne A, #0x07, L_09C4               ; B4 07 06  09BB
        mov R0, #0x50                       ; 78 50  09BE
        mov R7, #0x06                       ; 7F 06  09C0
        sjmp L_09C9                         ; 80 05  09C2
L_09C4:
        add A, #0x50                        ; 24 50  09C4
        mov R0, A                           ; F8  09C6
        mov R7, #0x01                       ; 7F 01  09C7
L_09C9:
        movx A, @DPTR                       ; E0  09C9
        mov @R0, A                          ; F6  09CA
        inc DPTR                            ; A3  09CB
        inc R0                              ; 08  09CC
        djnz R7, L_09C9                     ; DF FA  09CD
        sjmp L_0A01                         ; 80 30  09CF
L_09D1:
        jb 0xE3, L_09DE                     ; 20 E3 0A  09D1
        anl A, #0x03                        ; 54 03  09D4
        mov R2, A                           ; FA  09D6
        movx A, @DPTR                       ; E0  09D7
        mov R0, A                           ; F8  09D8
        lcall 0x07D3                        ; 12 07 D3  09D9
        sjmp L_0A01                         ; 80 23  09DC
L_09DE:
        jb 0xE2, L_09EF                     ; 20 E2 0E  09DE
        setb 0x31                           ; D2 31  09E1
        setb 0x44                           ; D2 44  09E3
        movx A, @DPTR                       ; E0  09E5
        mov 0x1A, A                         ; F5 1A  09E6
        inc DPTR                            ; A3  09E8
        movx A, @DPTR                       ; E0  09E9
        inc A                               ; 04  09EA
        mov 0x1B, A                         ; F5 1B  09EB
        sjmp L_0A01                         ; 80 12  09ED
L_09EF:
        sjmp L_0A01                         ; 80 10  09EF
L_09F1:
        jnb 0xE4, L_0A01                    ; 30 E4 0D  09F1
        jb 0xE3, L_0A01                     ; 20 E3 0A  09F4
        add A, #0xCE                        ; 24 CE  09F7
        jc L_0A0C                           ; 40 11  09F9
        movx A, @DPTR                       ; E0  09FB
        mov R7, A                           ; FF  09FC
        setb 0x32                           ; D2 32  09FD
        setb 0x44                           ; D2 44  09FF
L_0A01:
        mov A, #0x08                        ; 74 08  0A01
L_0A03:
        add A, 0x66                         ; 25 66  0A03
        mov 0x66, A                         ; F5 66  0A05
        jnc L_0A0B                          ; 50 02  0A07
        inc 0x67                            ; 05 67  0A09
L_0A0B:
        ret                                 ; 22  0A0B
L_0A0C:
        movx A, @DPTR                       ; E0  0A0C
        mov R0, A                           ; F8  0A0D
        inc DPTR                            ; A3  0A0E
        jb 0x3A, L_0A23                     ; 20 3A 11  0A0F
        movx A, @DPTR                       ; E0  0A12
        jnb 0x38, L_0A1C                    ; 30 38 06  0A13
        anl A, 0x90                         ; 55 90  0A16
        jnz L_0A01                          ; 70 E7  0A18
        sjmp L_0A33                         ; 80 17  0A1A
L_0A1C:
        orl A, 0x90                         ; 45 90  0A1C
        cjne A, #0xFF, L_0A01               ; B4 FF E0  0A1E
        sjmp L_0A33                         ; 80 10  0A21
L_0A23:
        jnb 0x39, L_0A34                    ; 30 39 0E  0A23
        movx A, @DPTR                       ; E0  0A26
        mov R7, A                           ; FF  0A27
        inc DPTR                            ; A3  0A28
        movx A, @DPTR                       ; E0  0A29
        inc A                               ; 04  0A2A
        cjne A, 0x07, L_0A32                ; B5 07 04  0A2B
        clr A                               ; E4  0A2E
        movx @DPTR, A                       ; F0  0A2F
        sjmp L_0A01                         ; 80 CF  0A30
L_0A32:
        movx @DPTR, A                       ; F0  0A32
L_0A33:
        mov A, R0                           ; E8  0A33
L_0A34:
        rl A                                ; 23  0A34
        mov 0x82, A                         ; F5 82  0A35
        mov 0x83, 0x3E                      ; 85 3E 83  0A37
        movx A, @DPTR                       ; E0  0A3A
        mov 0x66, A                         ; F5 66  0A3B
        inc DPTR                            ; A3  0A3D
        movx A, @DPTR                       ; E0  0A3E
        mov 0x67, A                         ; F5 67  0A3F
        ret                                 ; 22  0A41
