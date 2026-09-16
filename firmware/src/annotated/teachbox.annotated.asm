;==============================================================================
; ROB3 FIRMWARE — TEACHBOX INTERFACE (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the TEACHBOX keypad/LED code.
;                    Companion to firmware/src/annotated/main.annotated.asm (init) and
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

        .include "rob3.inc"         ; symbolic names for IRAM/flags/SFRs/devices


;==============================================================================
; MAIN-LOOP CALL SITE  (0x07C4)                                          [BYTE]
;------------------------------------------------------------------------------
; The main loop calls the scanner; a nonzero return (a fresh key) dispatches to
; the key handler at 0x0C7F. A zero return means "no new key".
;==============================================================================
        org     0x07C4
tb_poll:
        lcall   kbd_scan            ; 12 0C 00  -> scan the 5x5 matrix (enters 0x0C00)
        jz      tb_poll_done        ; 60 03     A==0 -> no new key, skip
        lcall   kbd_handle          ; 12 0C 80  -> process the captured key (0x0C80)
tb_poll_done:
        setb    IE_EA               ; 0xA8.7 (D2 AF)  EA = 1 (re-enable interrupts)
        ajmp    0x074D              ; E1 4D     back to the main loop


;==============================================================================
; KEYPAD SCANNER  kbd_scan (0x0BFF -> 0x0C6B)                       [BYTE][HW]
;------------------------------------------------------------------------------
; Returns A = key index (0x00..0x18 for the 25 keys) once a NEW, debounced key
; is accepted, else A = 0. Uses R6 as the running key index across the 8 rows
; and 3 column groups. Column reads come from P1 (0x90), NOT an 8255 port.
;==============================================================================
        org     0x0BFF
        ; 0x0BFF: FF  (padding byte, MOV R7,A; the routine is CALLED at 0x0C00)
kbd_scan:                           ; entry = 0x0C00
        jbc     SYS_KBD_EVENT_B,kbd_evt ; 0x20.1 (10 01 61) if kbd-event flag set: clear it
                                    ;           and take the event path (0x0C64)
        mov     SFR_DPH,#DEV_8255_PB ; 0x83=0x51 (75 83 51) DPH -> 8255 Port B (5100H) [HW]
        mov     R6,#0x00            ; 7E 00     R6 = running key index = 0
        mov     A,LED_LATCH         ; 0x47 (E5 47)  A = current LED/row latch value
        anl     A,#0x0F             ; 54 0F     keep low nibble = row strobe seed
row_loop:
        movx    @DPTR,A             ; F0        drive the row strobe via the 8255
        mov     KBD_STROBE,A        ; 0x46 (F5 46)  remember the strobe pattern
        mov     A,SFR_P1            ; 0x90 (E5 90)  read column returns from P1 [HW]
        anl     A,#0xE0             ; 54 E0     keep top 3 bits = the 3 col groups
        jz      no_hit              ; 60 1A     no column low -> nothing in this row
        jb      0xE0.5,grp_hi       ; 20 E5 04  ACC.5 set -> group in the high pair
        swap    A                   ; C4        (re-pack the column bits...)
        rl      A                   ; 23
        sjmp    grp_done            ; 80 04
grp_hi:
        anl     A,#0xC0             ; 54 C0     isolate the upper two group bits
        jnz     kbd_new             ; 70 2E     multiple/other group -> new-key path
grp_done:
        xch     A,R6                ; CE        stage the group bits vs the index
        jnz     kbd_new             ; 70 2B     a real hit -> accept as new key
        mov     A,KBD_STROBE        ; 0x46 (E5 46)  recompute index from strobe...
        swap    A                   ; C4
        anl     A,#0x07             ; 54 07     row number 0..7
        inc     A                   ; 04
        add     A,R6                ; 2E        += accumulated group offset
        mov     R6,A                ; FE        R6 = updated key index
        add     A,#0xE7             ; 24 E7     (index - 0x19): test past 25 keys
        jc      kbd_new             ; 40 1F     wrapped past the last key -> accept
no_hit:
        mov     A,KBD_STROBE        ; 0x46 (E5 46)  advance the row strobe...
        add     A,#0x10             ; 24 10     next matrix row (bit into 0x10 step)
        jnb     0xE0.7,row_loop     ; 30 E7 D6  more rows to scan -> loop
        ; --- scan finished with no new column hit: run the debounce logic ---
        mov     A,LED_LATCH         ; 0x47 (E5 47)  restore the idle LED/row latch
        movx    @DPTR,A             ; F0        ...drive it back out
        mov     A,R6                ; EE        A = key index found this pass
        xch     A,KBD_DEBOUNCE0     ; 0x56 (C5 56)  swap with the previous index
        cjne    A,KBD_DEBOUNCE0,key_changed ; 0x56 (B5 56 17) changed vs last pass?
        jz      key_release         ; 60 1C     both zero -> nothing held (release)
        jnb     SYS_FLAG_B6,ret_zero ; 0x20.6 (30 06 1B) not flagged held -> return 0
        jnb     SYS_FLAG_B5,key_repeat ; 0x20.5 (30 05 1A) auto-repeat pending?
        djnz    KBD_DEBOUNCE1,ret_zero ; 0x57 (D5 57 15) count down repeat timer
        mov     KBD_DEBOUNCE1,#0x03 ; 0x57 (75 57 03)  reload repeat timer
        ret                         ; 22        (A holds the repeating key index)

kbd_new:
        mov     KBD_DEBOUNCE0,#0xFF ; 0x56 (75 56 FF)  mark "previous index" invalid
        mov     A,LED_LATCH         ; 0x47 (E5 47)  restore idle latch...
        movx    @DPTR,A             ; F0
        sjmp    ret_zero            ; 80 09     debounce: report nothing THIS pass

key_changed:
        clr     SYS_FLAG_B5         ; 0x20.5 (C2 05)  clear the auto-repeat-pending flag
        mov     KBD_DEBOUNCE1,#0x23 ; 0x57 (75 57 23)  set initial key-repeat delay (35)
        sjmp    ret_zero            ; 80 02

key_release:
        setb    SYS_FLAG_B6         ; 0x20.6 (D2 06)  mark "no key held" state
key_repeat:
        clr     A                   ; E4        return A = 0 (no new key)
ret_zero:
        ret                         ; 22

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

key_hold_clear:
        clr     SYS_FLAG_B6         ; 0x20.6 (C2 06)
        ret                         ; 22

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
        org     0x0C64
kbd_evt:
        mov     A,#0x19             ; 74 19     A = 0x19 (sentinel index)
        ; 0x0C66 onward overlaps the next label:
        mov     R6,A                ; FE
        mov     KBD_DEBOUNCE0,A     ; 0x56 (F5 56)  previous index = 0x19
        clr     SYS_FLAG_B6         ; 0x20.6 (C2 06)  clear "key held"
        ret                         ; 22


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
        org     0x0C7F
        ; 0x0C7F: FF  (padding byte; the handler is CALLED at 0x0C80)
kbd_handle:                         ; entry = 0x0C80
        dec     A                   ; 14        A = keyindex - 1 (0-base the index)
        cjne    A,#0x0E,kh_not_clr  ; B4 0E 09  was it the CLR key? [INFER: CLR=0x0E]
        clr     A                   ; E4        CLR pressed -> reset entry state:
        mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  clear numeric-arg buffer 0x6D
        mov     EDIT_STATE,A        ; 0x2A (F5 2A)  clear editor flag byte 0x2A
        orl     LED_LATCH,#0xF8     ; 0x47 (43 47 F8)  idle the row/LED strobe bits
        ret                         ; 22

kh_not_clr:
        jb      EDIT_ERR_B7,kh_0cea ; 0x2A.7 (bit 0x57) (20 57 5A) arg-entry busy? [INFER]
        jb      EDIT_ERR_B6,kh_ret  ; 0x2A.6 (bit 0x56) (20 56 1E) already active? [INFER]
        setb    EDIT_ERR_B7         ; 0x2A.7 (bit 0x57) (D2 57)  mark arg-entry busy
        cjne    A,#0x0A,kh_ax_lo    ; B4 0A 09  key index-1 == 0x0A ? [INFER: mode key]
        ; --- (index-1)==0x0A branch: enter a mode with sub-state 0x20 --------
        mov     R3,#0x20            ; 7B 20
        mov     EDIT_MODE,#0x20     ; 0x29 (75 29 20)  mode/sub-state 0x29 = 0x20 [INFER]
        anl     LED_LATCH,#0xF7     ; 0x47 (53 47 F7)
        ret                         ; 22

kh_ax_lo:
        jnc     kh_0cb2             ; 50 0F     index-1 > 0x0A -> higher-key dispatch
        ; ================= AXIS SELECT (POSITION mode) ======================
        ; Here A = keyindex-1 and is in 0x00..0x09. A second DEC gives the axis
        ; number; axes 0..5 are valid. Verified in ucSim:
        ;   key index 2 -> axis 0 -> R1 = 0x50
        ;   key index 3 -> axis 1 -> R1 = 0x51
        ;   key index 7 -> axis 5 -> R1 = 0x55
        ; i.e. axis = keyindex - 2, R1 = 0x50 + axis (pointer to that axis's
        ; current-position slot 0x50..0x55), and mode 0x29 := 0x40.        [BYTE]
        dec     A                   ; 14        A = keyindex - 2 = axis number
        cjne    A,#0x06,$+3         ; B4 06 00  set/clear C for the < 6 test
        jnc     kh_0d23             ; 50 7A     axis >= 6 -> not an axis key
        setb    EDIT_ERR_B5         ; 0x2A.5 (bit 0x55) (D2 55) "axis selected" [INFER]
        add     A,#CURPOS_BASE      ; 0x50 (24 50)  A = axis + 0x50 -> RAM pointer
        mov     R1,A                ; F9        R1 -> current position of this axis
        mov     EDIT_MODE,#0x40     ; 0x29 (75 29 40)  mode 0x29 = 0x40 (POSITION mode) [BYTE]
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
        org     0x0E26
kh_jog:
        orl     SYS_FLAGS,#0x60     ; 0x20 (43 20 60)  set flags 0x20.5+0x20.6 (jog active)
        jb      0xE0.0,kh_jog_dec   ; 20 E0 07  ACC.0 == 1 -> decrement path
        ; --- increment (e.g. the '+' direction) ---
        cjne    @R1,#0xFF,kh_jog_inc ; B7 FF 01 already at max? (0xFF)
        ret                         ; 22        clamp: do not overflow past 0xFF
kh_jog_inc:
        inc     @R1                 ; 07        axis position += 1
        sjmp    kh_jog_move         ; 80 05
kh_jog_dec:
        mov     A,@R1               ; E7        read current position
        jnz     kh_jog_dodec        ; 70 01     nonzero -> ok to decrement
        ret                         ; 22        clamp: do not underflow past 0x00
kh_jog_dodec:
        dec     @R1                 ; 17        axis position -= 1
kh_jog_move:
        mov     AXIS_ACTIVE,#0x00   ; 0x21 (75 21 00)  reset axis-active mask
        setb    0x2F                ; D2 2F     signal "motion requested" (0x2F.? bit)
        mov     0x19,#0x64          ; 75 19 64  arm the axis watchdog (0x19 byte, 0x64 ticks)
        ret                         ; 22        servo ISR (0x00C0) now drives the
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
        org     0x0D65
pos_digit:                          ; reached with A = the pressed digit (0..9)
        mov     R6,A                ; FE        R6 = this digit
        mov     A,ARG_ACC_LO        ; 0x6D (E5 6D)  A = current accumulator low byte
        mov     B,#0x0A             ; 75 F0 0A  B = 10
        mul     AB                  ; A4        A = low*10 (B = carry-out)
        jb      EDIT_MODE_B3,pd_add ; 0x29.3 (bit 0x4B) (20 4B 09) two-digit mode?
        ; --- (single-byte path) store low*10 (+digit handled by caller) -------
        ; (0x0D6F..0x0D74 set/clear flags then fall to the store below)
        mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  accumulator low = value*10
        ret                         ; 22
pd_add:                             ; 0x0D78
        add     A,R6                ; 2E        A = value*10 + digit
        mov     ARG_ACC_LO,A        ; 0x6D (F5 6D)  store new accumulator low
        clr     A                   ; E4
        addc    A,B                 ; 35 F0     propagate the *10 carry...
        mov     R6,A                ; FE
        mov     A,ARG_ACC_HI        ; 0x6E (E5 6E)  ...into the high byte:
        mov     B,#0x0A             ; 75 F0 0A
        mul     AB                  ; A4        high = high*10 + carry
        ; 0x0D86.. store high:
        mov     ARG_ACC_HI,A        ; 0x6E (F5 6E)  accumulator high byte
        ; (continues into the mode/command dispatch at 0x0D8B)

;------------------------------------------------------------------------------
; COMMIT the accumulated value to the selected axis slot                 [BYTE][SIM]
;   R1 = R4 + 0x4F  (R4 = axis+2 numbering, so axis 1 -> R1 = 0x51)
;   @R1 = 0x6D      (write the accumulated low byte into the axis position)
;------------------------------------------------------------------------------
        org     0x0D9B
pos_commit:
        mov     A,R4                ; EC        A = axis selector (R4)
        add     A,#0x4F             ; 24 4F     -> 0x4F + R4  (axis slot base)
        mov     R1,A                ; F9        R1 -> axis position slot (0x50+axis)
        mov     @R1,ARG_ACC_LO      ; 0x6D (A7 6D)  @R1 = accumulated value (COMMIT) [SIM]
        acall   0x0D38              ; D1 38     post-commit housekeeping
        ajmp    0x0884              ; 81 84     back to the editor/dispatch

;------------------------------------------------------------------------------
        ; kh_0cb1 (0x0CB1): RET (a bare exit target of `jb 0x2A.6`).
        ; kh_0cea (0x0CEA): arg-entry-busy branch.
        ; kh_0cb2 (0x0CB2): higher key-index dispatch (command keys).
        ; kh_0d23 (0x0D23): "not an axis key" / fall-through dispatch.
kh_ret:
        ; label alias for 0x0CB1 (RET); real byte at 0x0CB1 = 0x22.

;==============================================================================
; NOTES / OPEN ITEMS
;------------------------------------------------------------------------------
; - kbd_scan (entry 0x0C00) is fully [BYTE]-verified and its hardware behaviour
;   ([HW]) matches hardware/teachbox/board.md: strobe rows via 8255 Port B
;   (DPH=0x51), read the three column groups on P1 (0x90) top bits, with a
;   two-stage debounce using 0x56 (last index) and 0x57 (repeat timer) plus
;   flags 0x20.5/0x20.6. (0x0BFF is a padding byte; callers enter at 0x0C00.)
; - The 25 physical keys map to indices 0x00..0x18; index 0x19 is a sentinel
;   used by the event path (0x0C64).
; - kbd_handle (entry 0x0C80; 0x0C7F is padding): the AXIS-SELECT path is now
;   [BYTE]-verified — key index 2..7 selects axis 0..5, sets R1 = 0x50+axis and
;   mode 0x29 = 0x40 (POSITION), implementing the manual's "numeric key selects
;   the axis" (hardware/teachbox/README.md). Watch the byte-vs-bit gotcha: the
;   `jb/setb 0x55/0x56/0x57` operands are BITS of byte 0x2A, not RAM bytes.
; - kh_jog (0x0E26) is now [BYTE]-verified: +/- increments/decrements the
;   selected axis position slot (@R1 = 0x50+axis) with 0x00/0xFF clamping, then
;   arms the motion subsystem (0x2F set, watchdog 0x19=0x64) so the servo ISR
;   drives the motor — the manual's "a +/- ENT".
; - POS-digit direct entry is now [BYTE][SIM]-verified: numeric keys build a
;   decimal value in (0x6E:0x6D) via value*10+digit (MUL AB by 10 at 0x0D68/
;   0x0D81), and MOV @R1,0x6D at 0x0D9F commits it into the selected axis slot
;   (R1 = 0x4F + R4). Confirmed: typing 1,2,8 gives 0x6D = 128, and the commit
;   writes axis-1 slot 0x51 = 0x80. This is the "type a number" alternative to
;   the +/- jog.
; - Still [INFER] / not annotated: the servo ISR motor drive itself
;   (0x00C0 -> 8255 Port A/C -> L293), and the MARK/GOTO/IF/OUT/TIM/RUN/STOP
;   command handlers.
;==============================================================================
