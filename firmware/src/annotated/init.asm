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
; Reached from the reset vector. Brings up: warm-up delay, 8255 PPI, axis
; select, internal RAM clear, stack, external SRAM sizing/probe, program-area
; header, interrupt enables, then falls into the main loop.
; All opcodes below are [BYTE]-verified from the ROM image. Items describing
; run-time *behavior* (which probe branch is taken, measured baud, delay
; durations) are marked [SIM] where confirmed or [INFER] where still pending.
;==============================================================================
        .org    0x0600
        mov A, #0x78                        ; 74 78  0600
L_0602:
        djnz R0, L_0602                     ; D8 FE  0602
        djnz 0xE0, L_0602                   ; D5 E0 FB  0604
        mov 0x83, #0x48                     ; 75 83 48  0607
L_060A:
        movx @DPTR, A                       ; F0  060A
        djnz R0, L_060A                     ; D8 FD  060B
L_060D:
        djnz R0, L_060D                     ; D8 FE  060D
        mov 0x83, #0x53                     ; 75 83 53  060F
        mov A, #0x80                        ; 74 80  0612
        movx @DPTR, A                       ; F0  0614
        clr A                               ; E4  0615
        dec 0x83                            ; 15 83  0616
        movx @DPTR, A                       ; F0  0618
        dec 0x83                            ; 15 83  0619
        mov A, #0xFF                        ; 74 FF  061B
        movx @DPTR, A                       ; F0  061D
        dec 0x83                            ; 15 83  061E
        clr A                               ; E4  0620
        movx @DPTR, A                       ; F0  0621
        mov 0x83, #0x59                     ; 75 83 59  0622
        mov A, #0x01                        ; 74 01  0625
        movx @DPTR, A                       ; F0  0627
        mov R0, #0x7F                       ; 78 7F  0628
        clr A                               ; E4  062A
        mov 0xD0, A                         ; F5 D0  062B
L_062D:
        mov @R0, A                          ; F6  062D
        djnz R0, L_062D                     ; D8 FD  062E
        mov 0x81, #0x31                     ; 75 81 31  0630
        mov 0x47, #0xFF                     ; 75 47 FF  0633
        mov 0x1F, #0xFF                     ; 75 1F FF  0636
        mov DPTR, #0x8000                   ; 90 80 00  0639
L_063C:
        movx A, @DPTR                       ; E0  063C
        cpl A                               ; F4  063D
        movx @DPTR, A                       ; F0  063E
        mov R0, A                           ; F8  063F
        movx A, @DPTR                       ; E0  0640
        xrl A, R0                           ; 68  0641
        jz L_064E                           ; 60 0A  0642
        jbc 0x47, L_0672                    ; 10 47 2B  0644
        setb 0x47                           ; D2 47  0647
        mov 0x83, #0xA0                     ; 75 83 A0  0649
        sjmp L_063C                         ; 80 EE  064C
L_064E:
        mov A, R0                           ; E8  064E
        cpl A                               ; F4  064F
        movx @DPTR, A                       ; F0  0650
        mov 0x3E, 0x83                      ; 85 83 3E  0651
        mov 0x3F, 0x3E                      ; 85 3E 3F  0654
        inc 0x3F                            ; 05 3F  0657
        mov 0x28, #0x03                     ; 75 28 03  0659
        mov 0x82, #0xF0                     ; 75 82 F0  065C
        mov R0, #0x08                       ; 78 08  065F
L_0661:
        movx A, @DPTR                       ; E0  0661
        cjne A, 0x00, L_0667                ; B5 00 02  0662
        sjmp L_066C                         ; 80 05  0665
L_0667:
        mov A, 0x00                         ; E5 00  0667
        movx @DPTR, A                       ; F0  0669
        clr 0x41                            ; C2 41  066A
L_066C:
        inc DPTR                            ; A3  066C
        djnz R0, L_0661                     ; D8 F2  066D
        lcall 0x0800                        ; 12 08 00  066F
L_0672:
        mov 0x08, #0x48                     ; 75 08 48  0672
        mov 0x22, #0x01                     ; 75 22 01  0675
        mov 0x83, #0x58                     ; 75 83 58  0678
        clr A                               ; E4  067B
        movx @DPTR, A                       ; F0  067C
        mov 0xA8, #0x84                     ; 75 A8 84  067D
L_0680:
        jb 0x10, L_0680                     ; 20 10 FD  0680
L_0683:
        jnb 0x10, L_0683                    ; 30 10 FD  0683
        clr 0xAF                            ; C2 AF  0686
        mov R7, #0x06                       ; 7F 06  0688
        mov R0, #0x58                       ; 78 58  068A
        mov R1, #0x50                       ; 79 50  068C
L_068E:
        mov A, @R0                          ; E6  068E
        mov @R1, A                          ; F7  068F
        inc R0                              ; 08  0690
        inc R1                              ; 09  0691
        djnz R7, L_068E                     ; DF FA  0692
        mov R7, #0x06                       ; 7F 06  0694
        mov R0, #0x48                       ; 78 48  0696
        mov A, #0x01                        ; 74 01  0698
L_069A:
        mov @R0, A                          ; F6  069A
        inc R0                              ; 08  069B
        djnz R7, L_069A                     ; DF FC  069C
        mov 0x89, #0x21                     ; 75 89 21  069E
        mov 0x88, #0x00                     ; 75 88 00  06A1
        mov 0x98, #0x50                     ; 75 98 50  06A4
        jb 0xB0, L_06B1                     ; 20 B0 07  06A7
        mov 0xA8, #0x07                     ; 75 A8 07  06AA
        setb 0x02                           ; D2 02  06AD
        ajmp 0x073C                         ; E1 3C  06AF
L_06B1:
        jb 0xB2, L_06B6                     ; 20 B2 02  06B1
        setb 0x02                           ; D2 02  06B4
L_06B6:
        clr A                               ; E4  06B6
        mov 0x88, A                         ; F5 88  06B7
        mov 0x8A, A                         ; F5 8A  06B9
        mov 0x8C, A                         ; F5 8C  06BB
        mov R0, #0x01                       ; 78 01  06BD
L_06BF:
        jb 0xB0, L_06BF                     ; 20 B0 FD  06BF
        setb 0x8C                           ; D2 8C  06C2
L_06C4:
        jb 0x8D, L_06B6                     ; 20 8D EF  06C4
        jnb 0xB0, L_06C4                    ; 30 B0 FA  06C7
        acall 0x06E4                        ; D1 E4  06CA
L_06CC:
        jb 0x8D, L_06B6                     ; 20 8D E7  06CC
        jb 0xB0, L_06CC                     ; 20 B0 FA  06CF
        acall 0x06E4                        ; D1 E4  06D2
L_06D4:
        jb 0x8D, L_06B6                     ; 20 8D DF  06D4
        jnb 0xB0, L_06D4                    ; 30 B0 FA  06D7
        acall 0x06E4                        ; D1 E4  06DA
L_06DC:
        jb 0x8D, L_06F3                     ; 20 8D 14  06DC
        jb 0xB0, L_06DC                     ; 20 B0 FA  06DF
        sjmp L_06B6                         ; 80 D2  06E2
L_06E4:
        clr 0x8C                            ; C2 8C  06E4
        mov @R0, 0x8A                       ; A6 8A  06E6
        inc R0                              ; 08  06E8
        mov @R0, 0x8C                       ; A6 8C  06E9
        mov 0x8A, A                         ; F5 8A  06EB
        mov 0x8C, A                         ; F5 8C  06ED
        setb 0x8C                           ; D2 8C  06EF
        inc R0                              ; 08  06F1
        ret                                 ; 22  06F2
L_06F3:
        mov R7, #0x01                       ; 7F 01  06F3
L_06F5:
        mov A, R2                           ; EA  06F5
        jz L_070A                           ; 60 12  06F6
        mov R0, #0x06                       ; 78 06  06F8
L_06FA:
        clr C                               ; C3  06FA
        mov A, @R0                          ; E6  06FB
        rrc A                               ; 13  06FC
        mov @R0, A                          ; F6  06FD
        dec R0                              ; 18  06FE
        mov A, @R0                          ; E6  06FF
        rrc A                               ; 13  0700
        mov @R0, A                          ; F6  0701
        djnz R0, L_06FA                     ; D8 F6  0702
        clr C                               ; C3  0704
        mov A, R7                           ; EF  0705
        rlc A                               ; 33  0706
        mov R7, A                           ; FF  0707
        sjmp L_06F5                         ; 80 EB  0708
L_070A:
        mov A, R1                           ; E9  070A
        mov 0xF0, #0x06                     ; 75 F0 06  070B
        div AB                              ; 84  070E
        add A, #0x08                        ; 24 08  070F
        anl A, #0xF0                        ; 54 F0  0711
        cjne A, #0x20, L_06B6               ; B4 20 A0  0713
        mov A, R3                           ; EB  0716
        add A, #0x08                        ; 24 08  0717
        anl A, #0xF0                        ; 54 F0  0719
        cjne A, #0x20, L_06B6               ; B4 20 98  071B
        mov A, R5                           ; ED  071E
        clr C                               ; C3  071F
        rrc A                               ; 13  0720
        add A, #0x08                        ; 24 08  0721
        anl A, #0xF0                        ; 54 F0  0723
        cjne A, #0x20, L_06B6               ; B4 20 8E  0725
        mov A, R7                           ; EF  0728
        dec A                               ; 14  0729
        cpl A                               ; F4  072A
        mov 0x8D, A                         ; F5 8D  072B
        setb 0x8E                           ; D2 8E  072D
        mov 0x99, #0x15                     ; 75 99 15  072F
L_0732:
        jnb 0x99, L_0732                    ; 30 99 FD  0732
        clr 0x99                            ; C2 99  0735
        setb 0x18                           ; D2 18  0737
        mov 0xA8, #0x17                     ; 75 A8 17  0739
L_073C:
        mov 0x1D, #0x0A                     ; 75 1D 0A  073C
        mov 0x8C, #0xE8                     ; 75 8C E8  073F
        setb 0x8C                           ; D2 8C  0742
        setb 0x00                           ; D2 00  0744
        clr A                               ; E4  0746
        mov 0x83, #0x58                     ; 75 83 58  0747
        movx @DPTR, A                       ; F0  074A
        setb 0xAF                           ; D2 AF  074B
