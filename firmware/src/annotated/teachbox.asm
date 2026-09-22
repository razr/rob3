;==============================================================================
; ROB3 FIRMWARE — TEACHBOX INTERFACE (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the TEACHBOX keypad/LED code.
;                    Companion to firmware/src/annotated/vectors.asm/init.asm (init) and
;                    the hardware docs under hardware/teachbox/.
;
; PROVENANCE TAGS
;   [BYTE] = decoded directly from the ROM bytes (verified in ucSim `dc`).
;   [HW]   = confirmed against the hardware schematic docs (hardware/teachbox/,
;            hardware/connectors/db25.md).
;   [INFER]= inferred from context; treat as a hypothesis to confirm.
;
; HARDWARE MODEL (see hardware/teachbox/board.md, led.md, ../connectors/db25.md)
;   The Teachbox is a 5x5 key matrix + 8 indicator LEDs on a DB25 connector.
;   A 74LS138 3-to-8 decoder (A0=DB25 23, A1=10, A2=22; /E=DB25 9) is driven by
;   8255 lines to strobe one matrix ROW (/Y0../Y7) at a time. The pressed
;   COLUMN(s) are read back on the 8031's Port 1 (P1, SFR 0x90), top 3 bits =
;   the three column groups. The same decoder outputs also sink the indicator
;   LEDs (active-LOW). Firmware reaches the 8255 at DPH=0x51 (Port B, 5100H).
;
; RELEVANT INTERNAL RAM (from docs/reverse_engineering_notes.md)
;   0x20.1 : keyboard-event flag (set elsewhere; consumed at scanner entry)
;   0x46   : current row-strobe pattern being written out
;   0x47   : LED/row output latch (the value driven to the matrix/LEDs)
;   0x56   : last accepted key index (debounce "previous" value)
;   0x57   : debounce / auto-repeat down-counter
;   0x20.5 : "new key press pending" style flag  (bit 5 of 0x20)
;   0x20.6 : "key currently held" style flag     (bit 6 of 0x20)
;   R6     : key index accumulator during the scan (0..0x18 = 0..24)
;==============================================================================

        ; symbols (the inc/*.inc equates) are provided by
        ; the top file rob3.asm, which includes this region in address order.


;==============================================================================
; MAIN-LOOP CALL SITE  (0x07C4)                                          [BYTE]
;------------------------------------------------------------------------------
; The main loop calls the scanner; a nonzero return (a fresh key) dispatches to
; the key handler at 0x0C7F. A zero return means "no new key".
;==============================================================================
        ; org 0x07C4
; tb_poll:
        ; lcall   kbd_scan            ; 12 0C 00  -> scan the 5x5 matrix (enters 0x0C00)
        ; jz      tb_poll_done        ; 60 03     A==0 -> no new key, skip
        ; lcall   kbd_handle          ; 12 0C 80  -> process the captured key (0x0C80)
; tb_poll_done:
        ; setb    IE_EA               ; 0xA8.7 (D2 AF)  EA = 1 (re-enable interrupts)
        ; ajmp    0x074D              ; E1 4D     back to the main loop


;==============================================================================
; KEYPAD SCANNER  kbd_scan (0x0BFF -> 0x0C6B)                       [BYTE][HW]
;------------------------------------------------------------------------------
; Returns A = key index (0x00..0x18 for the 25 keys) once a NEW, debounced key
; is accepted, else A = 0. Uses R6 as the running key index across the 8 rows
; and 3 column groups. Column reads come from P1 (0x90), NOT an 8255 port.
;==============================================================================
        ; org 0x0BFF
        ; 0x0BFF: FF  (padding byte, MOV R7,A; the routine is CALLED at 0x0C00)
; kbd_scan:                           ; entry = 0x0C00
        ; jbc     SYS_KBD_EVENT_B,kbd_evt ; 0x20.1 (10 01 61) if kbd-event flag set: clear it
                                    ;           and take the event path (0x0C64)
        ; mov     SFR_DPH,#DEV_8255_PB ; 0x83=0x51 (75 83 51) DPH -> 8255 Port B (5100H) [HW]
        ; mov     R6,#0x00            ; 7E 00     R6 = running key index = 0
        ; mov     A,LED_LATCH         ; 0x47 (E5 47)  A = current LED/row latch value
        ; anl     A,#0x0F             ; 54 0F     keep low nibble = row strobe seed
; row_loop:
        ; movx    @DPTR,A             ; F0        drive the row strobe via the 8255
        ; mov     KBD_STROBE,A        ; 0x46 (F5 46)  remember the strobe pattern
        ; mov     A,SFR_P1            ; 0x90 (E5 90)  read column returns from P1 [HW]
        ; anl     A,#0xE0             ; 54 E0     keep top 3 bits = the 3 col groups
        ; jz      no_hit              ; 60 1A     no column low -> nothing in this row
        ; jb      0xE0.5,grp_hi       ; 20 E5 04  ACC.5 set -> group in the high pair
        ; swap    A                   ; C4        (re-pack the column bits...)
        ; rl      A                   ; 23
        ; sjmp    grp_done            ; 80 04
; grp_hi:
        ; anl     A,#0xC0             ; 54 C0     isolate the upper two group bits
        ; jnz     kbd_new             ; 70 2E     multiple/other group -> new-key path
; grp_done:
        ; xch     A,R6                ; CE        stage the group bits vs the index
        ; jnz     kbd_new             ; 70 2B     a real hit -> accept as new key
        ; mov     A,KBD_STROBE        ; 0x46 (E5 46)  recompute index from strobe...
        ; swap    A                   ; C4
        ; anl     A,#0x07             ; 54 07     row number 0..7
        ; inc     A                   ; 04
        ; add     A,R6                ; 2E        += accumulated group offset
        ; mov     R6,A                ; FE        R6 = updated key index
        ; add     A,#0xE7             ; 24 E7     (index - 0x19): test past 25 keys
        ; jc      kbd_new             ; 40 1F     wrapped past the last key -> accept
; no_hit:
        ; mov     A,KBD_STROBE        ; 0x46 (E5 46)  advance the row strobe...
        ; add     A,#0x10             ; 24 10     next matrix row (bit into 0x10 step)
        ; jnb     0xE0.7,row_loop     ; 30 E7 D6  more rows to scan -> loop
        ; --- scan finished with no new column hit: run the debounce logic ---
        ; mov     A,LED_LATCH         ; 0x47 (E5 47)  restore the idle LED/row latch
        ; movx    @DPTR,A             ; F0        ...drive it back out
        ; mov     A,R6                ; EE        A = key index found this pass
        ; xch     A,KBD_DEBOUNCE0     ; 0x56 (C5 56)  swap with the previous index
        ; cjne    A,KBD_DEBOUNCE0,key_changed ; 0x56 (B5 56 17) changed vs last pass?
        ; jz      key_release         ; 60 1C     both zero -> nothing held (release)
        ; jnb     SYS_FLAG_B6,ret_zero ; 0x20.6 (30 06 1B) not flagged held -> return 0
        ; jnb     SYS_FLAG_B5,key_repeat ; 0x20.5 (30 05 1A) auto-repeat pending?
        ; djnz    KBD_DEBOUNCE1,ret_zero ; 0x57 (D5 57 15) count down repeat timer
        ; mov     KBD_DEBOUNCE1,#0x03 ; 0x57 (75 57 03)  reload repeat timer
        ; ret                         ; 22        (A holds the repeating key index)

; kbd_new:
        ; mov     KBD_DEBOUNCE0,#0xFF ; 0x56 (75 56 FF)  mark "previous index" invalid
        ; mov     A,LED_LATCH         ; 0x47 (E5 47)  restore idle latch...
        ; movx    @DPTR,A             ; F0
        ; sjmp    ret_zero            ; 80 09     debounce: report nothing THIS pass

; key_changed:
        ; clr     SYS_FLAG_B5         ; 0x20.5 (C2 05)  clear the auto-repeat-pending flag
        ; mov     KBD_DEBOUNCE1,#0x23 ; 0x57 (75 57 23)  set initial key-repeat delay (35)
        ; sjmp    ret_zero            ; 80 02

; key_release:
        ; setb    SYS_FLAG_B6         ; 0x20.6 (D2 06)  mark "no key held" state
; key_repeat:
        ; clr     A                   ; E4        return A = 0 (no new key)
; ret_zero:
        ; ret                         ; 22

;------------------------------------------------------------------------------
; DEBOUNCE ACCEPT PROTOCOL — required press cadence                    [SIM]
;   The accept path is gated by `jnb 0x20.6, ret_zero` (0x0C41). Flag 0x20.6 is
;   set ONLY by key_release (above), i.e. after the scanner sees NO key. So a
;   key is dispatched to kbd_handle only in the sequence:
;       RELEASE (scanner sets 0x20.6)  ->  PRESS + HOLD (same index across
;       ~3 scan passes)  ->  accept, A = key index, call kbd_handle.
;   Holding a key from reset with no prior release leaves 0x20.6 clear, so the
;   index is latched into 0x56 (and 0x57 reloads to 0x23) but NEVER dispatched.
;   Verified in ucSim (with the loopback module so the poll runs): idle-release
;   first, then press row3/grp2 -> kbd_handle reached at ~24000 stepped
;   instructions. This is the behaviour a black-box test harness must reproduce.
;------------------------------------------------------------------------------

; key_hold_clear:
        ; clr     SYS_FLAG_B6         ; 0x20.6 (C2 06)
        ; ret                         ; 22

;------------------------------------------------------------------------------
; (row, group) -> KEY INDEX map  (as returned in A to kbd_handle)      [SIM]
;   Swept in ucSim (loopback module + release-then-hold): the scanner returns
;       index = row + 1 + (group-1)*8       row 0..7, group 1..3
;   i.e.  group 1: rows 0..7 -> 0x01..0x08
;         group 2: rows 0..7 -> 0x09..0x10
;         group 3: rows 0..7 -> 0x11..0x18
;   kbd_handle then does DEC A (0-based). AXIS SELECT is index 0x02..0x07
;   (group 1, rows 1..6) -> axis 0..5: verified each sets mode 0x29 = 0x40
;   (POSITION) as annotated in kbd_handle. (The full POS-digit value-entry and
;   commit sequence — pos_digit/pos_commit — depends on further editor state
;   [0x29.3, 0x2A.x, the 0x6E:0x6D accumulator] and is not yet fully mapped as a
;   black-box key sequence; the axis-select entry point is [SIM]-confirmed.)
;------------------------------------------------------------------------------

;------------------------------------------------------------------------------
; kbd_evt (0x0C64): keyboard-event branch taken when 0x20.1 was set. Loads a
; fixed index 0x19 (=25, one past the 25 keys 0..24), resets debounce state.
;------------------------------------------------------------------------------
        ; org 0x0C64
; kbd_evt:
        ; mov     A,#0x19             ; 74 19     A = 0x19 (sentinel index)
        ; 0x0C66 onward overlaps the next label:
        ; mov     R6,A                ; FE
        ; mov     KBD_DEBOUNCE0,A     ; 0x56 (F5 56)  previous index = 0x19
        ; clr     SYS_FLAG_B6         ; 0x20.6 (C2 06)  clear "key held"
        ; ret                         ; 22


;==============================================================================
; KEY HANDLER  kbd_handle (entry 0x0C80)                            [BYTE][INFER]
;------------------------------------------------------------------------------
; Entered from tb_poll with A = the key index (0x00..0x18) returned by kbd_scan.
; This is the Teachbox command/editor dispatcher (modes: INPUT / POSITION / RUN
; / STEP / DISPLAY / BREAK, per hardware/teachbox/README.md).
;
; This pass annotates the AXIS-SELECT / POSITION-mode entry — the code behind
; the manual's "press a numeric key 1..6 to select the axis, then jog it with
; +/-" and the "POS a . n ENT" positioning command. Other command handlers
; (MARK/GOTO/IF/OUT/TIM, RUN/STOP, editor) are reached from the same dispatch
; but are NOT annotated here and are flagged [INFER].
;
; IMPORTANT byte-vs-bit note: `jb 0x57` / `jb 0x56` use BIT addresses, i.e.
; bit 0x57 = byte 0x2A bit 7, bit 0x56 = byte 0x2A bit 6, and `setb 0x57`,
; `setb 0x55` likewise are bits of byte 0x2A. They are NOT the RAM bytes 0x55/
; 0x56/0x57. (Verified in ucSim: clearing byte 0x2A takes the axis path.)
;==============================================================================
        ; org 0x0C7F
        ; 0x0C7F: FF  (padding byte; the handler is CALLED at 0x0C80)
; kbd_handle:                         ; entry = 0x0C80
        ; dec     A                   ; 14        A = keyindex - 1 (0-base the index)
        ; cjne    A,#0x0E,kh_not_clr  ; B4 0E 09  was it the CLR key? [INFER: CLR=0x0E]
        ; clr     A                   ; E4        CLR pressed -> reset entry state:
        ; mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  clear numeric-arg buffer 0x6D
        ; mov     EDIT_STATE,A        ; 0x2A (F5 2A)  clear editor flag byte 0x2A
        ; orl     LED_LATCH,#0xF8     ; 0x47 (43 47 F8)  idle the row/LED strobe bits
        ; ret                         ; 22

; kh_not_clr:
        ; jb      EDIT_ERR_B7,kh_0cea ; 0x2A.7 (bit 0x57) (20 57 5A) arg-entry busy? [INFER]
        ; jb      EDIT_ERR_B6,kh_ret  ; 0x2A.6 (bit 0x56) (20 56 1E) already active? [INFER]
        ; setb    EDIT_ERR_B7         ; 0x2A.7 (bit 0x57) (D2 57)  mark arg-entry busy
        ; cjne    A,#0x0A,kh_ax_lo    ; B4 0A 09  key index-1 == 0x0A ? [INFER: mode key]
        ; --- (index-1)==0x0A branch: enter a mode with sub-state 0x20 --------
        ; mov     R3,#0x20            ; 7B 20
        ; mov     EDIT_MODE,#0x20     ; 0x29 (75 29 20)  mode/sub-state 0x29 = 0x20 [INFER]
        ; anl     LED_LATCH,#0xF7     ; 0x47 (53 47 F7)
        ; ret                         ; 22

; kh_ax_lo:
        ; jnc     kh_0cb2             ; 50 0F     index-1 > 0x0A -> higher-key dispatch
        ; ================= AXIS SELECT (POSITION mode) ======================
        ; Here A = keyindex-1 and is in 0x00..0x09. A second DEC gives the axis
        ; number; axes 0..5 are valid. Verified in ucSim:
        ;   key index 2 -> axis 0 -> R1 = 0x50
        ;   key index 3 -> axis 1 -> R1 = 0x51
        ;   key index 7 -> axis 5 -> R1 = 0x55
        ; i.e. axis = keyindex - 2, R1 = 0x50 + axis (pointer to that axis's
        ; current-position slot 0x50..0x55), and mode 0x29 := 0x40.        [BYTE]
        ; dec     A                   ; 14        A = keyindex - 2 = axis number
        ; cjne    A,#0x06,$+3         ; B4 06 00  set/clear C for the < 6 test
        ; jnc     kh_0d23             ; 50 7A     axis >= 6 -> not an axis key
        ; setb    EDIT_ERR_B5         ; 0x2A.5 (bit 0x55) (D2 55) "axis selected" [INFER]
        ; add     A,#CURPOS_BASE      ; 0x50 (24 50)  A = axis + 0x50 -> RAM pointer
        ; mov     R1,A                ; F9        R1 -> current position of this axis
        ; mov     EDIT_MODE,#0x40     ; 0x29 (75 29 40)  mode 0x29 = 0x40 (POSITION mode) [BYTE]
        ; ... POSITION-mode entry established: R1 now points at the selected
        ;     axis's position slot (0x50+axis). The +/- jog (kh_jog below) then
        ;     increments/decrements THAT slot. The POS-digit direct entry
        ;     (POS a . n) assembles a decimal value in (0x6E:0x6D) via *10+digit
        ;     and commits it with MOV @R1,0x6D at 0x0D9F — annotated below and
        ;     [SIM]-verified (typing 1,2,8 -> 128 into the axis slot).

;==============================================================================
; AXIS JOG  kh_jog (0x0E26)                                             [BYTE]
;------------------------------------------------------------------------------
; The manual's "a +/- ENT" — move the selected axis one step forward/back.
; Reached (with R1 -> the selected axis position slot 0x50+axis) when a +/-
; arrow key is processed. Direction is ACC bit 0:
;   ACC.0 = 0  -> INCREMENT the axis position (@R1), clamped at 0xFF
;   ACC.0 = 1  -> DECREMENT the axis position (@R1), clamped at 0x00
; then it arms the motion subsystem so the servo ISR drives the motor toward
; the new position.  Verified in ucSim:
;   @R1=0x80, ACC.0=0 -> 0x81 ; ACC.0=1 -> 0x7F
;   @R1=0xFF, ACC.0=0 -> stays 0xFF (no overflow)
;   @R1=0x00, ACC.0=1 -> stays 0x00 (no underflow)                       [BYTE]
;==============================================================================
        ; org 0x0E26
; kh_jog:
        ; orl     SYS_FLAGS,#0x60     ; 0x20 (43 20 60)  set flags 0x20.5+0x20.6 (jog active)
        ; jb      0xE0.0,kh_jog_dec   ; 20 E0 07  ACC.0 == 1 -> decrement path
        ; --- increment (e.g. the '+' direction) ---
        ; cjne    @R1,#0xFF,kh_jog_inc ; B7 FF 01 already at max? (0xFF)
        ; ret                         ; 22        clamp: do not overflow past 0xFF
; kh_jog_inc:
        ; inc     @R1                 ; 07        axis position += 1
        ; sjmp    kh_jog_move         ; 80 05
; kh_jog_dec:
        ; mov     A,@R1               ; E7        read current position
        ; jnz     kh_jog_dodec        ; 70 01     nonzero -> ok to decrement
        ; ret                         ; 22        clamp: do not underflow past 0x00
; kh_jog_dodec:
        ; dec     @R1                 ; 17        axis position -= 1
; kh_jog_move:
        ; mov     AXIS_ACTIVE,#0x00   ; 0x21 (75 21 00)  reset axis-active mask
        ; setb    0x2F                ; D2 2F     signal "motion requested" (0x2F.? bit)
        ; mov     0x19,#0x64          ; 75 19 64  arm the axis watchdog (0x19 byte, 0x64 ticks)
        ; ret                         ; 22        servo ISR (0x00C0) now drives the
                                    ;           motor toward the new @R1 position

;------------------------------------------------------------------------------
; Exit/other-branch stubs referenced above (targets confirmed, bodies [INFER]).
;==============================================================================
; POS-DIGIT DIRECT ENTRY  (the manual's "POS a . n ENT")               [BYTE][SIM]
;------------------------------------------------------------------------------
; The alternative to jogging with +/- : type a decimal number and commit it
; straight into the selected axis's position slot. Two pieces, both verified
; in ucSim:
;
;   (A) DECIMAL ACCUMULATE  — each digit key does  value = value*10 + digit,
;       building a 16-bit value in the pair (0x6E:0x6D) = (high:low).
;   (B) COMMIT              — MOV @R1,0x6D at 0x0D9F writes the accumulated low
;       byte into the axis slot @R1 (= 0x50 + axis), where R1 = R4 + 0x4F.
;
; The numeric-entry keys reach the accumulate step at 0x0D65; the accumulator
; low byte is 0x6D, high byte 0x6E. `MUL AB` with B=#0x0A is the *10.
;
; Verified in ucSim (typing 1,2,8):
;   0x6D: 0x00 --(1)--> 0x01 --(2)--> 0x0C(=12) --(8)--> 0x80(=128)
; and the commit with R4=2 (axis 1) / 0x6D=0x80 writes slot 0x51 = 0x80.
; So "POSITION, select axis 1, type 1 2 8, ENT" sets axis 1 to 128, whereas
; kh_jog (+/-) only steps the same slot by +/-1 per press.               [SIM]
;------------------------------------------------------------------------------
        ; org 0x0D65
; pos_digit:                          ; reached with A = the pressed digit (0..9)
        ; mov     R6,A                ; FE        R6 = this digit
        ; mov     A,ARG_ACC_LO        ; 0x6D (E5 6D)  A = current accumulator low byte
        ; mov     B,#0x0A             ; 75 F0 0A  B = 10
        ; mul     AB                  ; A4        A = low*10 (B = carry-out)
        ; jb      EDIT_MODE_B3,pd_add ; 0x29.3 (bit 0x4B) (20 4B 09) two-digit mode?
        ; --- (single-byte path) store low*10 (+digit handled by caller) -------
        ; (0x0D6F..0x0D74 set/clear flags then fall to the store below)
        ; mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  accumulator low = value*10
        ; ret                         ; 22
; pd_add:                             ; 0x0D78
        ; add     A,R6                ; 2E        A = value*10 + digit
        ; mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  store new accumulator low
        ; clr     A                   ; E4
        ; addc    A,B                 ; 35 F0     propagate the *10 carry...
        ; mov     R6,A                ; FE
        ; mov     A,ARG_ACC_HI        ; 0x6E (E5 6E)  ...into the high byte:
        ; mov     B,#0x0A             ; 75 F0 0A
        ; mul     AB                  ; A4        high = high*10 + carry
        ; 0x0D86.. store high:
        ; mov     ARG_ACC_HI,A        ; 0x6E (F5 6E)  accumulator high byte
        ; (continues into the mode/command dispatch at 0x0D8B)

;------------------------------------------------------------------------------
; COMMIT the accumulated value to the selected axis slot                 [BYTE][SIM]
;   R1 = R4 + 0x4F  (R4 = axis+2 numbering, so axis 1 -> R1 = 0x51)
;   @R1 = 0x6D      (write the accumulated low byte into the axis position)
;------------------------------------------------------------------------------
        .org    0x0C00
;
;==============================================================================
; kbd_scan (0x0C00) — strobe each of the 5 matrix rows via 8255 Port B, read
;   the column groups on P1 (top 3 bits), debounce, and return the key index
;   in R6 (0 = none). key index = row+1 + (group-1)*8.
;==============================================================================
        jbc 0x01, L_0C64                    ; 10 01 61  0C00
        mov SFR_DPH, #DEV_8255_PB                     ; 75 83 51  0C03
        mov R6, #0x00                       ; 7E 00  0C06
        mov A, 0x47                         ; E5 47  0C08
        anl A, #0x0F                        ; 54 0F  0C0A
L_0C0C:
        movx @DPTR, A                       ; F0  0C0C
        mov KBD_STROBE, A                         ; F5 46  0C0D
        mov A, SFR_P1                         ; E5 90  0C0F
        anl A, #0xE0                        ; 54 E0  0C11
        jz L_0C2F                           ; 60 1A  0C13
        jb 0xE5, L_0C1C                     ; 20 E5 04  0C15
        swap A                              ; C4  0C18
        rl A                                ; 23  0C19
        sjmp L_0C20                         ; 80 04  0C1A
L_0C1C:
        anl A, #0xC0                        ; 54 C0  0C1C
        jnz L_0C4E                          ; 70 2E  0C1E
L_0C20:
        xch A, R6                           ; CE  0C20
        jnz L_0C4E                          ; 70 2B  0C21
        mov A, 0x46                         ; E5 46  0C23
        swap A                              ; C4  0C25
        anl A, #0x07                        ; 54 07  0C26
        inc A                               ; 04  0C28
        add A, R6                           ; 2E  0C29
        mov R6, A                           ; FE  0C2A
        add A, #0xE7                        ; 24 E7  0C2B
        jc L_0C4E                           ; 40 1F  0C2D
L_0C2F:
        mov A, 0x46                         ; E5 46  0C2F
        add A, #0x10                        ; 24 10  0C31
        jnb 0xE7, L_0C0C                    ; 30 E7 D6  0C33
        mov A, 0x47                         ; E5 47  0C36
        movx @DPTR, A                       ; F0  0C38
        mov A, R6                           ; EE  0C39
        xch A, 0x56                         ; C5 56  0C3A
        cjne A, 0x56, L_0C56                ; B5 56 17  0C3C
        jz L_0C5D                           ; 60 1C  0C3F
        jnb 0x06, L_0C5F                    ; 30 06 1B  0C41
        jnb 0x05, L_0C61                    ; 30 05 1A  0C44
        djnz 0x57, L_0C5F                   ; D5 57 15  0C47
        mov 0x57, #0x03                     ; 75 57 03  0C4A
        ret                                 ; 22  0C4D
L_0C4E:
        mov 0x56, #0xFF                     ; 75 56 FF  0C4E
        mov A, 0x47                         ; E5 47  0C51
        movx @DPTR, A                       ; F0  0C53
        sjmp L_0C5F                         ; 80 09  0C54
L_0C56:
        clr 0x05                            ; C2 05  0C56
        mov 0x57, #0x23                     ; 75 57 23  0C58
        sjmp L_0C5F                         ; 80 02  0C5B
L_0C5D:
        setb 0x06                           ; D2 06  0C5D
L_0C5F:
        clr A                               ; E4  0C5F
        ret                                 ; 22  0C60
L_0C61:
        clr 0x06                            ; C2 06  0C61
        ret                                 ; 22  0C63
L_0C64:
        mov A, #0x19                        ; 74 19  0C64
        mov R6, A                           ; FE  0C66
        mov 0x56, A                         ; F5 56  0C67
        clr 0x06                            ; C2 06  0C69
        ret                                 ; 22  0C6B
; --- 0x0C6C..0x0C7F : 0xFF-count 20 0xFF EPROM padding (objcopy gap-fill) ---
;
;==============================================================================
; kbd_handle (0x0C80) — process a captured key: axis-select, mode dispatch,
;   numeric entry, jog, program keys. Entered from main loop when kbd_scan
;   returns nonzero in A.
;==============================================================================
        .org    0x0C80
        dec A                               ; 14  0C80
        cjne A, #0x0E, L_0C8D               ; B4 0E 09  0C81
L_0C84:
        clr A                               ; E4  0C84
        mov 0x6D, A                         ; F5 6D  0C85
        mov EDIT_STATE, A                         ; F5 2A  0C87
        orl LED_LATCH, #0xF8                     ; 43 47 F8  0C89
        ret                                 ; 22  0C8C
L_0C8D:
        jb 0x57, L_0CEA                     ; 20 57 5A  0C8D
        jb 0x56, L_0CB1                     ; 20 56 1E  0C90
        setb 0x57                           ; D2 57  0C93
        cjne A, #0x0A, L_0CA1               ; B4 0A 09  0C95
        mov R3, #0x20                       ; 7B 20  0C98
        mov EDIT_MODE, #0x20                     ; 75 29 20  0C9A
        anl LED_LATCH, #0xF7                     ; 53 47 F7  0C9D
        ret                                 ; 22  0CA0
L_0CA1:
        jnc L_0CB2                          ; 50 0F  0CA1
L_0CA3:
        dec A                               ; 14  0CA3
        cjne A, #0x06, L_0CA7               ; B4 06 00  0CA4
L_0CA7:
        jnc L_0D23                          ; 50 7A  0CA7
        setb 0x55                           ; D2 55  0CA9
        add A, #0x50                        ; 24 50  0CAB
        mov R1, A                           ; F9  0CAD
        mov EDIT_MODE, #0x40                     ; 75 29 40  0CAE
L_0CB1:
        ret                                 ; 22  0CB1
L_0CB2:
        inc A                               ; 04  0CB2
        jnb 0xE4, L_0D23                    ; 30 E4 6D  0CB3
        add A, R6                           ; 2E  0CB6
        add A, R6                           ; 2E  0CB7
        subb A, #0x28                       ; 94 28  0CB8
        mov EDIT_MODE, A                         ; F5 29  0CBA
        add A, #0x02                        ; 24 02  0CBC
        mov R3, A                           ; FB  0CBE
        inc A                               ; 04  0CBF
;--- MOVC DATA: LED segment / display lookup (3 reads from inline table) ---
        movc A, @A + PC                     ; 83  0CC0
        xch A, R3                           ; CB  0CC1
        movc A, @A + PC                     ; 83  0CC2
        xch A, 0x29                         ; C5 29  0CC3
        movc A, @A + PC                     ; 83  0CC5
        anl LED_LATCH, #0x0F                     ; 53 47 0F  0CC6
        orl LED_LATCH, A                         ; 42 47  0CC9
        ret                                 ; 22  0CCB
        mov 0xA0, R0                        ; 88 A0  0CCC
        movx @DPTR, A                       ; F0  0CCE
        mov 0xA0, R4                        ; 8C A0  0CCF
        movx @DPTR, A                       ; F0  0CD1
        lcall 0x8910                        ; 12 89 10  0CD2
        inc R7                              ; 0F  0CD5
        add A, R3                           ; 2B  0CD6
        jb 0x19, L_0CF2                     ; 20 19 18  0CD7
        jnb 0x1F, L_0CED                    ; 30 1F 10  0CDA
        jc 0x0D13                           ; 40 34  0CDD
        lcall 0x5030                        ; 12 50 30  0CDF
        inc R2                              ; 0A  0CE2
        jz 0x0C65                           ; 60 80  0CE3
        anl C, /0x70                        ; B0 70  0CE5
        div AB                              ; 84  0CE7
        anl C, /0xF0                        ; B0 F0  0CE8
L_0CEA:
        cjne A, #0x0A, L_0D10               ; B4 0A 23  0CEA
L_0CED:
        jnb 0x4F, L_0D23                    ; 30 4F 33  0CED
        clr 0x51                            ; C2 51  0CF0
L_0CF2:
        mov A, R3                           ; EB  0CF2
        xrl A, #0x02                        ; 64 02  0CF3
        mov R3, A                           ; FB  0CF5
        anl LED_LATCH, #0xF7                     ; 53 47 F7  0CF6
        jnb 0x52, L_0D03                    ; 30 52 07  0CF9
        mov 0x6C, 0x6D                      ; 85 6D 6C  0CFC
        mov EDIT_MODE, #0x10                     ; 75 29 10  0CFF
        ret                                 ; 22  0D02
L_0D03:
        mov EDIT_MODE, #0x30                     ; 75 29 30  0D03
        cjne A, #0x10, L_0D0F               ; B4 10 06  0D06
        mov EDIT_MODE, #0x08                     ; 75 29 08  0D09
        mov LED_LATCH, 0x1F                      ; 85 1F 47  0D0C
L_0D0F:
        ret                                 ; 22  0D0F
L_0D10:
        jnc L_0D8E                          ; 50 7C  0D10
        jb 0x55, L_0CA3                     ; 20 55 8E  0D12
        jb 0x51, L_0D65                     ; 20 51 4D  0D15
        setb 0x52                           ; D2 52  0D18
        mov 0x6E, #0x00                     ; 75 6E 00  0D1A
        jb 0x4C, L_0D42                     ; 20 4C 22  0D1D
        jbc 0x4B, L_0D2A                    ; 10 4B 07  0D20
L_0D23:
        mov EDIT_STATE, #0x40                     ; 75 2A 40  0D23
        anl LED_LATCH, #0x0F                     ; 53 47 0F  0D26
        ret                                 ; 22  0D29
L_0D2A:
        jz L_0D23                           ; 60 F7  0D2A
        cjne A, #0x09, L_0D2F               ; B4 09 00  0D2C
L_0D2F:
        jnc L_0D23                          ; 50 F2  0D2F
        mov R4, A                           ; FC  0D31
        cjne R3, #0x10, L_0D3B              ; BB 10 06  0D32
        clr 0x52                            ; C2 52  0D35
        mov EDIT_MODE, #0x48                     ; 75 29 48  0D37
        ret                                 ; 22  0D3A
L_0D3B:
        acall 0x0FC4                        ; F1 C4  0D3B
        cpl A                               ; F4  0D3D
        mov 0x6D, A                         ; F5 6D  0D3E
        sjmp L_0D4D                         ; 80 0B  0D40
L_0D42:
        mov 0x6D, A                         ; F5 6D  0D42
        jnz L_0D4B                          ; 70 05  0D44
        anl 0x29, #0xE7                     ; 53 29 E7  0D46
        sjmp L_0D4D                         ; 80 02  0D49
L_0D4B:
        setb 0x51                           ; D2 51  0D4B
L_0D4D:
        jb 0x48, L_0D56                     ; 20 48 06  0D4D
        jb 0x49, L_0D5D                     ; 20 49 0A  0D50
        setb 0x4D                           ; D2 4D  0D53
        ret                                 ; 22  0D55
L_0D56:
        jb 0x49, L_0D61                     ; 20 49 08  0D56
        mov EDIT_MODE, #0x40                     ; 75 29 40  0D59
        ret                                 ; 22  0D5C
L_0D5D:
        orl 0x29, #0xA0                     ; 43 29 A0  0D5D
        ret                                 ; 22  0D60
L_0D61:
        mov EDIT_MODE, #0x80                     ; 75 29 80  0D61
        ret                                 ; 22  0D64
;
;==============================================================================
; pos_digit (0x0D65) — POS direct entry: decimal accumulate into 0x6D:0x6E.
;   value = value*10 + digit (MUL AB with B=#0x0A).
;==============================================================================
L_0D65:
        mov R6, A                           ; FE  0D65
        mov A, 0x6D                         ; E5 6D  0D66
        mov 0xF0, #0x0A                     ; 75 F0 0A  0D68
        mul AB                              ; A4  0D6B
        jb 0x4B, L_0D78                     ; 20 4B 09  0D6C
        jb 0xD2, L_0D23                     ; 20 D2 B1  0D6F
        add A, R6                           ; 2E  0D72
        jc L_0D23                           ; 40 AE  0D73
        mov 0x6D, A                         ; F5 6D  0D75
        ret                                 ; 22  0D77
L_0D78:
        add A, R6                           ; 2E  0D78
        mov 0x6D, A                         ; F5 6D  0D79
        clr A                               ; E4  0D7B
        addc A, 0xF0                        ; 35 F0  0D7C
        mov R6, A                           ; FE  0D7E
        mov A, 0x6E                         ; E5 6E  0D7F
        mov 0xF0, #0x0A                     ; 75 F0 0A  0D81
        mul AB                              ; A4  0D84
        jb 0xD2, L_0D23                     ; 20 D2 9B  0D85
        add A, R6                           ; 2E  0D88
        jc L_0D23                           ; 40 98  0D89
        mov 0x6E, A                         ; F5 6E  0D8B
        ret                                 ; 22  0D8D
L_0D8E:
        cjne A, #0x0D, L_0DF4               ; B4 0D 63  0D8E
        jnb 0x4D, L_0D23                    ; 30 4D 8F  0D91
        mov A, R3                           ; EB  0D94
        jb 0xE7, L_0DF2                     ; 20 E7 5A  0D95
        cjne A, #0x0D, L_0DA5               ; B4 0D 0A  0D98
;
;--- pos_commit (0x0D9B): R1 = R4+0x4F -> MOV @R1,0x6D at 0x0D9F ---
        mov A, R4                           ; EC  0D9B
        add A, #0x4F                        ; 24 4F  0D9C
        mov R1, A                           ; F9  0D9E
        mov @R1, 0x6D                       ; A7 6D  0D9F
        acall 0x0E38                        ; D1 38  0DA1
        ajmp 0x0C84                         ; 81 84  0DA3
L_0DA5:
        mov 0x82, 0x66                      ; 85 66 82  0DA5
        mov 0x83, 0x67                      ; 85 67 83  0DA8
        movx @DPTR, A                       ; F0  0DAB
        inc DPTR                            ; A3  0DAC
        mov R1, #0x6C                       ; 79 6C  0DAD
        mov R6, #0x01                       ; 7E 01  0DAF
        jb 0xE5, L_0DBD                     ; 20 E5 09  0DB1
        jb 0xE4, L_0DCD                     ; 20 E4 16  0DB4
        mov R1, #0x50                       ; 79 50  0DB7
        mov R6, #0x06                       ; 7E 06  0DB9
        sjmp L_0DDB                         ; 80 1E  0DBB
L_0DBD:
        jb 0xE1, L_0DC4                     ; 20 E1 04  0DBD
        mov A, 0x6D                         ; E5 6D  0DC0
        sjmp L_0DDC                         ; 80 18  0DC2
L_0DC4:
        inc R6                              ; 0E  0DC4
        jb 0xE2, L_0DDA                     ; 20 E2 12  0DC5
        mov A, 0x6D                         ; E5 6D  0DC8
        dec R1                              ; 19  0DCA
        sjmp L_0DDC                         ; 80 0F  0DCB
L_0DCD:
        cjne A, #0x10, L_0DD6               ; B4 10 06  0DCD
        mov A, 0x47                         ; E5 47  0DD0
        mov 0x1F, A                         ; F5 1F  0DD2
        sjmp L_0DDC                         ; 80 06  0DD4
L_0DD6:
        inc R1                              ; 09  0DD6
        cjne A, #0x19, L_0DDB               ; B4 19 01  0DD7
L_0DDA:
        inc R6                              ; 0E  0DDA
L_0DDB:
        mov A, @R1                          ; E7  0DDB
L_0DDC:
        movx @DPTR, A                       ; F0  0DDC
        inc R1                              ; 09  0DDD
        inc DPTR                            ; A3  0DDE
        djnz R6, L_0DDB                     ; DE FA  0DDF
L_0DE1:
        clr A                               ; E4  0DE1
        movx @DPTR, A                       ; F0  0DE2
        inc DPTR                            ; A3  0DE3
        mov A, 0x82                         ; E5 82  0DE4
        anl A, #0x07                        ; 54 07  0DE6
        jnz L_0DE1                          ; 70 F7  0DE8
        mov 0x66, 0x82                      ; 85 82 66  0DEA
        mov 0x67, 0x83                      ; 85 83 67  0DED
        ajmp 0x0C84                         ; 81 84  0DF0
L_0DF2:
        ajmp 0x0EC0                         ; C1 C0  0DF2
L_0DF4:
        jnc L_0E41                          ; 50 4B  0DF4
        jnb 0x4E, L_0E41                    ; 30 4E 48  0DF6
        jb 0x55, L_0E26                     ; 20 55 2A  0DF9
        jb 0x54, L_0E43                     ; 20 54 44  0DFC
        jb 0x53, L_0E20                     ; 20 53 1E  0DFF
        cjne R3, #0x10, L_0E15              ; BB 10 10  0E02
        setb 0x4D                           ; D2 4D  0E05
        mov C, 0xE0                         ; A2 E0  0E07
        mov A, R4                           ; EC  0E09
        acall 0x0FC4                        ; F1 C4  0E0A
        jc L_0E12                           ; 40 04  0E0C
        cpl A                               ; F4  0E0E
        anl LED_LATCH, A                         ; 52 47  0E0F
        ret                                 ; 22  0E11
L_0E12:
        orl LED_LATCH, A                         ; 42 47  0E12
        ret                                 ; 22  0E14
L_0E15:
        mov EDIT_MODE, #0x20                     ; 75 29 20  0E15
        jnb 0xE0, L_0E1F                    ; 30 E0 04  0E18
        dec R3                              ; 1B  0E1B
        xrl 0x6D, #0xFF                     ; 63 6D FF  0E1C
L_0E1F:
        ret                                 ; 22  0E1F
L_0E20:
        jb 0xE0, L_0E1F                     ; 20 E0 FC  0E20
        setb 0x44                           ; D2 44  0E23
        ret                                 ; 22  0E25
;
;==============================================================================
; kh_jog (0x0E26) — axis jog: increment/decrement axis position by 1, clamp
;   0x00..0xFF, then arm motion. +key = inc, -key = dec.
;==============================================================================
L_0E26:
        orl 0x20, #0x60                     ; 43 20 60  0E26
        jb 0xE0, L_0E33                     ; 20 E0 07  0E29
        cjne @R1, #0xFF, L_0E30             ; B7 FF 01  0E2C
        ret                                 ; 22  0E2F
L_0E30:
        inc @R1                             ; 07  0E30
        sjmp L_0E38                         ; 80 05  0E31
L_0E33:
        mov A, @R1                          ; E7  0E33
        jnz L_0E37                          ; 70 01  0E34
        ret                                 ; 22  0E36
L_0E37:
        dec @R1                             ; 17  0E37
L_0E38:
        mov 0x21, #0x00                     ; 75 21 00  0E38
        setb 0x2F                           ; D2 2F  0E3B
        mov 0x19, #0x64                     ; 75 19 64  0E3D
        ret                                 ; 22  0E40
L_0E41:
        ajmp 0x0D23                         ; A1 23  0E41
L_0E43:
        jnb 0x41, L_0E41                    ; 30 41 FB  0E43
        jb 0xE0, L_0E58                     ; 20 E0 0F  0E46
        jb 0x50, L_0EB5                     ; 20 50 69  0E49
        mov A, 0x66                         ; E5 66  0E4C
        add A, #0x08                        ; 24 08  0E4E
        mov 0x66, A                         ; F5 66  0E50
        jnc L_0E6D                          ; 50 19  0E52
        inc 0x67                            ; 05 67  0E54
        sjmp L_0E6D                         ; 80 15  0E56
L_0E58:
        mov A, 0x66                         ; E5 66  0E58
        add A, #0xF8                        ; 24 F8  0E5A
        mov 0x66, A                         ; F5 66  0E5C
        jc L_0E6B                           ; 40 0B  0E5E
        mov A, 0x67                         ; E5 67  0E60
        cjne A, 0x3F, L_0E69                ; B5 3F 04  0E62
        mov 0x66, #0x00                     ; 75 66 00  0E65
        ret                                 ; 22  0E68
L_0E69:
        dec 0x67                            ; 15 67  0E69
L_0E6B:
        clr 0x50                            ; C2 50  0E6B
L_0E6D:
        mov 0x82, 0x66                      ; 85 66 82  0E6D
        mov 0x83, 0x67                      ; 85 67 83  0E70
        movx A, @DPTR                       ; E0  0E73
        jb 0xE7, L_0EBA                     ; 20 E7 43  0E74
        jnb 0xE6, L_0E81                    ; 30 E6 07  0E77
        jnb 0xE5, L_0EB6                    ; 30 E5 39  0E7A
        mov LED_LATCH, #0x27                     ; 75 47 27  0E7D
        ret                                 ; 22  0E80
L_0E81:
        jb 0xE5, L_0E9D                     ; 20 E5 19  0E81
        cjne A, #0x1F, L_0E8B               ; B4 1F 04  0E84
        mov LED_LATCH, #0x4F                     ; 75 47 4F  0E87
        ret                                 ; 22  0E8A
L_0E8B:
        jnb 0xE4, L_0E99                    ; 30 E4 0B  0E8B
        jb 0xE3, L_0E95                     ; 20 E3 04  0E8E
        mov LED_LATCH, #0x1F                     ; 75 47 1F  0E91
        ret                                 ; 22  0E94
L_0E95:
        mov LED_LATCH, #0x3F                     ; 75 47 3F  0E95
        ret                                 ; 22  0E98
L_0E99:
        mov LED_LATCH, #0x2F                     ; 75 47 2F  0E99
        ret                                 ; 22  0E9C
L_0E9D:
        jb 0xE4, L_0EA4                     ; 20 E4 04  0E9D
        mov LED_LATCH, #0xF7                     ; 75 47 F7  0EA0
        ret                                 ; 22  0EA3
L_0EA4:
        jb 0xE2, L_0EAC                     ; 20 E2 05  0EA4
        mov LED_LATCH, #0x6F                     ; 75 47 6F  0EA7
        sjmp L_0EAF                         ; 80 03  0EAA
L_0EAC:
        mov LED_LATCH, #0x5F                     ; 75 47 5F  0EAC
L_0EAF:
        jnb 0xE1, L_0EB5                    ; 30 E1 03  0EAF
        anl LED_LATCH, #0xF7                     ; 53 47 F7  0EB2
L_0EB5:
        ret                                 ; 22  0EB5
L_0EB6:
        mov LED_LATCH, #0x47                     ; 75 47 47  0EB6
        ret                                 ; 22  0EB9
L_0EBA:
        mov LED_LATCH, #0x0F                     ; 75 47 0F  0EBA
        setb 0x50                           ; D2 50  0EBD
        ret                                 ; 22  0EBF
L_0EC0:
        jb 0xE3, L_0F0C                     ; 20 E3 49  0EC0
        jb 0xE2, L_0EED                     ; 20 E2 27  0EC3
        jnb 0x41, L_0F07                    ; 30 41 3E  0EC6
        mov 0x26, #0x00                     ; 75 26 00  0EC9
        jb 0x52, L_0ED4                     ; 20 52 05  0ECC
        jb 0x42, L_0EE1                     ; 20 42 0F  0ECF
        sjmp L_0F07                         ; 80 33  0ED2
L_0ED4:
        acall 0x0FCE                        ; F1 CE  0ED4
        acall 0x0803                        ; 11 03  0ED6
        jnb 0x41, L_0F07                    ; 30 41 2C  0ED8
        setb 0x42                           ; D2 42  0EDB
        mov 0x1F, #0xFF                     ; 75 1F FF  0EDD
        mov A, R3                           ; EB  0EE0
L_0EE1:
        jb 0xE1, L_0EE7                     ; 20 E1 03  0EE1
        setb 0x43                           ; D2 43  0EE4
        ret                                 ; 22  0EE6
L_0EE7:
        setb 0x53                           ; D2 53  0EE7
        mov EDIT_MODE, #0x40                     ; 75 29 40  0EE9
        ret                                 ; 22  0EEC
L_0EED:
        anl 0x28, #0x07                     ; 53 28 07  0EED
        mov 0x26, #0x00                     ; 75 26 00  0EF0
        jnb 0x52, L_0EF9                    ; 30 52 03  0EF3
        acall 0x0FCE                        ; F1 CE  0EF6
        mov A, R3                           ; EB  0EF8
L_0EF9:
        jb 0xE1, L_0F00                     ; 20 E1 04  0EF9
        clr 0x42                            ; C2 42  0EFC
        ajmp 0x0C84                         ; 81 84  0EFE
L_0F00:
        setb 0x54                           ; D2 54  0F00
        mov EDIT_MODE, #0x40                     ; 75 29 40  0F02
        ajmp 0x0E6D                         ; C1 6D  0F05
L_0F07:
        anl 0x28, #0x03                     ; 53 28 03  0F07
L_0F0A:
        ajmp 0x0D23                         ; A1 23  0F0A
L_0F0C:
        jnb 0xE1, L_0F39                    ; 30 E1 2A  0F0C
        mov 0x82, 0x66                      ; 85 66 82  0F0F
        mov 0x83, 0x67                      ; 85 67 83  0F12
        jb 0xE2, L_0F1E                     ; 20 E2 06  0F15
        mov A, #0x40                        ; 74 40  0F18
        movx @DPTR, A                       ; F0  0F1A
        inc DPTR                            ; A3  0F1B
        ajmp 0x0DE1                         ; A1 E1  0F1C
L_0F1E:
        mov A, #0x83                        ; 74 83  0F1E
        movx @DPTR, A                       ; F0  0F20
        mov 0x82, #0xFE                     ; 75 82 FE  0F21
        mov 0x83, 0x3E                      ; 85 3E 83  0F24
        mov A, 0x66                         ; E5 66  0F27
        movx @DPTR, A                       ; F0  0F29
        inc DPTR                            ; A3  0F2A
        mov A, 0x67                         ; E5 67  0F2B
        clr C                               ; C3  0F2D
        subb A, 0x3F                        ; 95 3F  0F2E
        movx @DPTR, A                       ; F0  0F30
        lcall 0x0803                        ; 12 08 03  0F31
        jnb 0x41, L_0F0A                    ; 30 41 D3  0F34
        ajmp 0x0C84                         ; 81 84  0F37
L_0F39:
        jb 0xE2, L_0F7A                     ; 20 E2 3E  0F39
        jnb 0x41, L_0F07                    ; 30 41 C8  0F3C
        mov A, 0x66                         ; E5 66  0F3F
        mov R4, A                           ; FC  0F41
        add A, #0x08                        ; 24 08  0F42
        mov R2, A                           ; FA  0F44
        mov A, 0x67                         ; E5 67  0F45
        mov R5, A                           ; FD  0F47
        addc A, #0x00                       ; 34 00  0F48
        mov R3, A                           ; FB  0F4A
        mov A, R5                           ; ED  0F4B
        subb A, 0x77                        ; 95 77  0F4C
        jc L_0F55                           ; 40 05  0F4E
        mov A, R4                           ; EC  0F50
        subb A, 0x76                        ; 95 76  0F51
        jnc L_0F0A                          ; 50 B5  0F53
L_0F55:
        mov 0x82, R2                        ; 8A 82  0F55
        mov 0x83, R3                        ; 8B 83  0F57
        movx A, @DPTR                       ; E0  0F59
        mov 0x82, R4                        ; 8C 82  0F5A
        mov 0x83, R5                        ; 8D 83  0F5C
        movx @DPTR, A                       ; F0  0F5E
        inc R4                              ; 0C  0F5F
        mov A, R4                           ; EC  0F60
        jnz L_0F64                          ; 70 01  0F61
        inc R5                              ; 0D  0F63
L_0F64:
        inc R2                              ; 0A  0F64
        mov A, R2                           ; EA  0F65
        jnz L_0F69                          ; 70 01  0F66
        inc R3                              ; 0B  0F68
L_0F69:
        cjne A, 0x76, L_0F55                ; B5 76 E9  0F69
        mov A, R3                           ; EB  0F6C
        cjne A, 0x77, L_0F55                ; B5 77 E5  0F6D
        inc DPTR                            ; A3  0F70
        mov A, #0x83                        ; 74 83  0F71
        movx @DPTR, A                       ; F0  0F73
        mov 0x76, R4                        ; 8C 76  0F74
        mov 0x77, R5                        ; 8D 77  0F76
        sjmp L_0FA8                         ; 80 2E  0F78
L_0F7A:
        mov A, 0x76                         ; E5 76  0F7A
        mov R2, A                           ; FA  0F7C
        add A, #0x08                        ; 24 08  0F7D
        mov R4, A                           ; FC  0F7F
        mov 0x76, A                         ; F5 76  0F80
        mov A, 0x77                         ; E5 77  0F82
        mov R3, A                           ; FB  0F84
        addc A, #0x00                       ; 34 00  0F85
        mov R5, A                           ; FD  0F87
        mov 0x77, A                         ; F5 77  0F88
L_0F8A:
        mov 0x82, R2                        ; 8A 82  0F8A
        mov 0x83, R3                        ; 8B 83  0F8C
        movx A, @DPTR                       ; E0  0F8E
        mov 0x82, R4                        ; 8C 82  0F8F
        mov 0x83, R5                        ; 8D 83  0F91
        movx @DPTR, A                       ; F0  0F93
        mov A, R4                           ; EC  0F94
        dec R4                              ; 1C  0F95
        jnz L_0F99                          ; 70 01  0F96
        dec R5                              ; 1D  0F98
L_0F99:
        mov A, R2                           ; EA  0F99
        cjne A, 0x66, L_0FBE                ; B5 66 21  0F9A
        mov A, R3                           ; EB  0F9D
        cjne A, 0x67, L_0FBD                ; B5 67 1C  0F9E
        mov 0x82, R2                        ; 8A 82  0FA1
        mov 0x83, R3                        ; 8B 83  0FA3
        mov A, #0x20                        ; 74 20  0FA5
        movx @DPTR, A                       ; F0  0FA7
L_0FA8:
        mov 0x82, #0xFE                     ; 75 82 FE  0FA8
        mov 0x83, 0x3E                      ; 85 3E 83  0FAB
        mov A, 0x76                         ; E5 76  0FAE
        movx @DPTR, A                       ; F0  0FB0
        inc DPTR                            ; A3  0FB1
        mov A, 0x77                         ; E5 77  0FB2
        clr C                               ; C3  0FB4
        subb A, 0x3F                        ; 95 3F  0FB5
        movx @DPTR, A                       ; F0  0FB7
        lcall 0x0803                        ; 12 08 03  0FB8
        ajmp 0x0C84                         ; 81 84  0FBB
L_0FBD:
        mov A, R2                           ; EA  0FBD
L_0FBE:
        dec R2                              ; 1A  0FBE
        jnz L_0F8A                          ; 70 C9  0FBF
        dec R3                              ; 1B  0FC1
        sjmp L_0F8A                         ; 80 C6  0FC2
L_0FC4:
        movc A, @A + PC                     ; 83  0FC4
;--- reads bit_table at 0x0FC5 (see tables.asm) ---
