;==============================================================================
; ROB3 FIRMWARE — MAIN LOOP (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : the idle super-loop entered at 0x074D by fall-through from
;                    init. Services motion/axis flags, then polls the teach-
;                    pendant keypad (gated by P3.2/P3.4). Part of the 1:1
;                    annotated source assembled by rob3.asm.
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. Unmarked instruction lines are [BYTE].
;
;==============================================================================
; MAIN LOOP  (0x074D -> 0x07C7)                          [BYTE][SIM][HW]
;------------------------------------------------------------------------------
; The idle super-loop. It services motion/axis flags, then — gated by three
; Port-3 input lines — polls the teach-pendant keypad. All three P3 gate lines
; are conditioned by MM74C04N #1 (hardware/board/MM74C04N.md), which is why the
; board needs BOTH the Teachbox AND the RS-232 shorting connector installed to
; run (hardware/teachbox/README.md "Hardware requirements").
;
; THREE GATES that must be satisfied for the keypad ever to be scanned — each
; verified by tracing the PC in ucSim and forcing the pin state:            [SIM]
;
;   GATE 1  EMERGENCY-OFF (P3.2 / INT0).  If P3.2 is LOW the level-triggered
;           INT0 keeps vectoring to the emergency_off handler (0x0040), which
;           never returns to the loop. P3.2 must be HIGH.           [BYTE][SIM]
;
;   GATE 3  TEACHBOX-POLL ENABLE (P3.4 / T0).  At 0x07AB:
;               20 B4 16   JB  P3.4, tb_poll (0x07C4)
;           the keypad scanner is CALLED only when P3.4 (8031 pin 14, T0,
;           bit addr 0xB4) reads HIGH; otherwise the loop skips the poll. So
;           P3.4 must be HIGH.                                       [BYTE][SIM]
;           (GATE 2 — the INT1/ADC servo ISR appearing to hog the CPU — is not
;            a real gate: once GATE 3 passes, the loop reaches tb_poll on the
;            first pass even with INT1 active. It only *looked* like a block
;            while the CPU was trapped by GATE 1.)                      [SIM]
;
;   GATE 4  KEYPAD DEBOUNCE (in kbd_scan, 0x0C00).  Even with the scanner
;           called, a key is only ACCEPTED (→ kbd_handle) after it survives the
;           two-stage debounce. The accept path at 0x0C41 is guarded by
;               30 06 1B   JNB 0x20.6, ret_zero
;           so flag 0x20.6 ("ready for a new key") must be SET — and it is only
;           set by the key_release path (SETB 0x20.6) when the scanner first
;           sees NO key. So the required cadence is RELEASE → PRESS-and-HOLD:
;           a release sets 0x20.6, then a held key is accepted a few scan passes
;           later (≈3 passes / ~24k instructions in ucSim). Holding a key from
;           reset without a prior release leaves 0x20.6 clear and the key is
;           never dispatched.                                          [SIM]
;           (Verified: idle-release first → 0x20 bit6 set → press row3/grp2 →
;            kbd_handle reached at ~24000 stepped instructions.)
;
; SIM IMPLICATION: to exercise the real keypad path in ucSim you must present
; P3.2=1 and P3.4=1 (the "RS-232 shorting connector present" pin state) and
; HOLD the key across several scan passes. The `loopback` cl_hw module
; (simulator/ucsim-modules/loopback/) drives P3.2/P3.4 for exactly this reason.
;------------------------------------------------------------------------------
        ; org 0x074D
; main_loop:
        ; clr     0xAF                ; C2 AF     EA = 0 (guard the flag section)
        ; setb    0xD4                ; D2 D4     PSW.4 = 1 (register bank 2)
        ; jnb     0x2F,ml_0782        ; 30 2F 2C  bit 0x25.7 (motion active?) clear -> skip
        ; ... (motion/axis servicing 0x0757..0x0781; annotated in a later pass)
; ml_0782:
        ; ... (0x0782..0x07A8 clears/sets the housekeeping flags 0x20.x/0x28.x)
        ; clr     0xAF                ; C2 AF     EA = 0 again before the poll gate
        ; jb      0xB4,tb_poll        ; 20 B4 16  GATE 3: poll keypad only if P3.4 HIGH
        ; --- P3.4 LOW: skip the keypad poll this pass ---
        ; clr     A                   ; E4
        ; mov     0x26,A              ; F5 26
        ; mov     0x66,A              ; F5 66
        ; mov     0x67,0x3F           ; 85 3F 67
        ; lcall   0x0803              ; 12 08 03
        ; (0x07B7.. more housekeeping, then loops back to main_loop)
        ; falls around to the tb_poll call site below when P3.4 is HIGH:
        .org    0x074D
L_074D:
        clr 0xAF                            ; C2 AF  074D
        setb 0xD4                           ; D2 D4  074F
        jnb 0x2F, L_0780                    ; 30 2F 2C  0751
        mov A, 0x21                         ; E5 21  0754
        cjne A, #0x3F, L_0763               ; B4 3F 0A  0756
        mov A, 0x2B                         ; E5 2B  0759
        jnz L_0780                          ; 70 23  075B
        mov C, 0x19                         ; A2 19  075D
        mov 0x2A, C                         ; 92 2A  075F
        sjmp L_077E                         ; 80 1B  0761
L_0763:
        jnb 0x1E, L_0780                    ; 30 1E 1A  0763
        clr 0x1E                            ; C2 1E  0766
        djnz 0x19, L_0780                   ; D5 19 15  0768
        clr 0x00                            ; C2 00  076B
        clr A                               ; E4  076D
        mov 0x83, #0x50                     ; 75 83 50  076E
        movx @DPTR, A                       ; F0  0771
        mov 0x4E, A                         ; F5 4E  0772
        mov 0x83, #0x52                     ; 75 83 52  0774
        movx @DPTR, A                       ; F0  0777
        mov 0x4F, A                         ; F5 4F  0778
        mov R4, #0xF7                       ; 7C F7  077A
        setb 0x2B                           ; D2 2B  077C
L_077E:
        clr 0x2F                            ; C2 2F  077E
L_0780:
        jnb 0x18, L_0785                    ; 30 18 02  0780
        acall 0x0541                        ; B1 41  0783
L_0785:
        jnb 0x1F, L_0797                    ; 30 1F 0F  0785
        clr 0x1F                            ; C2 1F  0788
        jnb 0x22, L_0797                    ; 30 22 0A  078A
        djnz 0x18, L_0797                   ; D5 18 07  078D
        anl 0x24, #0xF0                     ; 53 24 F0  0790
        mov R4, #0xF1                       ; 7C F1  0793
        setb 0x2B                           ; D2 2B  0795
L_0797:
        clr 0xD4                            ; C2 D4  0797
        lcall 0x0900                        ; 12 09 00  0799
        setb 0xAF                           ; D2 AF  079C
        jnb 0x04, L_074D                    ; 30 04 AC  079E
        jnb 0x02, L_074D                    ; 30 02 A9  07A1
        clr 0x04                            ; C2 04  07A4
        jb 0x43, L_074D                     ; 20 43 A4  07A6
        clr 0xAF                            ; C2 AF  07A9
        jb 0xB4, L_07C4                     ; 20 B4 16  07AB
        clr A                               ; E4  07AE
        mov 0x26, A                         ; F5 26  07AF
        mov 0x66, A                         ; F5 66  07B1
        mov 0x67, 0x3F                      ; 85 3F 67  07B3
        lcall 0x0803                        ; 12 08 03  07B6
        jnb 0x41, L_07CC                    ; 30 41 10  07B9
        mov 0x1F, #0xFF                     ; 75 1F FF  07BC
        orl 0x28, #0x0C                     ; 43 28 0C  07BF
        sjmp L_07CC                         ; 80 08  07C2
L_07C4:
        lcall 0x0C00                        ; 12 0C 00  07C4
        jz L_07CC                           ; 60 03  07C7
        lcall 0x0C80                        ; 12 0C 80  07C9
L_07CC:
        setb 0xAF                           ; D2 AF  07CC
        ajmp 0x074D                         ; E1 4D  07CE
        anl A, #0x03                        ; 54 03  07D0
        mov R2, A                           ; FA  07D2
        mov A, 0x1F                         ; E5 1F  07D3
        djnz R2, L_07DA                     ; DA 03  07D5
        orl A, R0                           ; 48  07D7
        sjmp L_07E5                         ; 80 0B  07D8
L_07DA:
        djnz R2, L_07DF                     ; DA 03  07DA
        anl A, R0                           ; 58  07DC
        sjmp L_07E5                         ; 80 06  07DD
L_07DF:
        djnz R2, L_07E4                     ; DA 03  07DF
        xrl A, R0                           ; 68  07E1
        sjmp L_07E5                         ; 80 01  07E2
L_07E4:
        mov A, R0                           ; E8  07E4
L_07E5:
        mov 0x7F, 0x83                      ; 85 83 7F  07E5
        mov 0x83, #0x51                     ; 75 83 51  07E8
        mov 0x1F, A                         ; F5 1F  07EB
        movx @DPTR, A                       ; F0  07ED
        mov 0x83, 0x7F                      ; 85 7F 83  07EE
        ret                                 ; 22  07F1
