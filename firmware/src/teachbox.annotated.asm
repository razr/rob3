;==============================================================================
; ROB3 FIRMWARE — TEACHBOX INTERFACE (annotated disassembly)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
; This file        : Human-annotated listing of the TEACHBOX keypad/LED code.
;                    Companion to firmware/src/main.annotated.asm (init) and
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
        setb    0xA8.7              ; D2 AF     EA = 1 (re-enable interrupts)
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
        jbc     0x20.1,kbd_evt      ; 10 01 61  if kbd-event flag set: clear it
                                    ;           and take the event path (0x0C64)
        mov     0x83,#0x51          ; 75 83 51  DPH=0x51 -> 8255 Port B (5100H) [HW]
        mov     R6,#0x00            ; 7E 00     R6 = running key index = 0
        mov     A,0x47              ; E5 47     A = current LED/row latch value
        anl     A,#0x0F             ; 54 0F     keep low nibble = row strobe seed
row_loop:
        movx    @DPTR,A             ; F0        drive the row strobe via the 8255
        mov     0x46,A              ; F5 46     remember the strobe pattern
        mov     A,0x90              ; E5 90     read column returns from P1 [HW]
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
        mov     A,0x46              ; E5 46     recompute index from strobe...
        swap    A                   ; C4
        anl     A,#0x07             ; 54 07     row number 0..7
        inc     A                   ; 04
        add     A,R6                ; 2E        += accumulated group offset
        mov     R6,A                ; FE        R6 = updated key index
        add     A,#0xE7             ; 24 E7     (index - 0x19): test past 25 keys
        jc      kbd_new             ; 40 1F     wrapped past the last key -> accept
no_hit:
        mov     A,0x46              ; E5 46     advance the row strobe...
        add     A,#0x10             ; 24 10     next matrix row (bit into 0x10 step)
        jnb     0xE0.7,row_loop     ; 30 E7 D6  more rows to scan -> loop
        ; --- scan finished with no new column hit: run the debounce logic ---
        mov     A,0x47              ; E5 47     restore the idle LED/row latch
        movx    @DPTR,A             ; F0        ...drive it back out
        mov     A,R6                ; EE        A = key index found this pass
        xch     A,0x56              ; C5 56     swap with the previous index (0x56)
        cjne    A,0x56,key_changed  ; B5 56 17  changed vs last pass? -> key_changed
        jz      key_release         ; 60 1C     both zero -> nothing held (release)
        jnb     0x20.6,ret_zero     ; 30 06 1B  not flagged held -> return 0
        jnb     0x20.5,key_repeat   ; 30 05 1A  auto-repeat pending? -> key_repeat
        djnz    0x57,ret_zero       ; D5 57 15  count down repeat timer -> return 0
        mov     0x57,#0x03          ; 75 57 03  reload repeat timer
        ret                         ; 22        (A holds the repeating key index)

kbd_new:
        mov     0x56,#0xFF          ; 75 56 FF  mark "previous index" invalid
        mov     A,0x47              ; E5 47     restore idle latch...
        movx    @DPTR,A             ; F0
        sjmp    ret_zero            ; 80 09     debounce: report nothing THIS pass

key_changed:
        clr     0x20.5              ; C2 05     clear the auto-repeat-pending flag
        mov     0x57,#0x23          ; 75 57 23  set initial key-repeat delay (35)
        sjmp    ret_zero            ; 80 02

key_release:
        setb    0x20.6              ; D2 06     mark "no key held" state
key_repeat:
        clr     A                   ; E4        return A = 0 (no new key)
ret_zero:
        ret                         ; 22

key_hold_clear:
        clr     0x20.6              ; C2 06
        ret                         ; 22

;------------------------------------------------------------------------------
; kbd_evt (0x0C64): keyboard-event branch taken when 0x20.1 was set. Loads a
; fixed index 0x19 (=25, one past the 25 keys 0..24), resets debounce state.
;------------------------------------------------------------------------------
        org     0x0C64
kbd_evt:
        mov     A,#0x19             ; 74 19     A = 0x19 (sentinel index)
        ; 0x0C66 onward overlaps the next label:
        mov     R6,A                ; FE
        mov     0x56,A              ; F5 56     previous index = 0x19
        clr     0x20.6              ; C2 06     clear "key held"
        ret                         ; 22


;==============================================================================
; KEY HANDLER  kbd_handle (0x0C7F ...)                              [BYTE][INFER]
;------------------------------------------------------------------------------
; Entered from tb_poll with A = the key index returned by kbd_scan. This is the
; large Teachbox command/editor dispatcher (modes: INPUT / POSITION / RUN /
; STEP / DISPLAY / BREAK, per hardware/teachbox/README.md). Only the prologue is
; annotated with certainty here; the per-key routines below it are extensive and
; are flagged [INFER] pending a dedicated pass.
;==============================================================================
        org     0x0C7F
        ; 0x0C7F: FF  (padding byte; the handler is CALLED at 0x0C80)
kbd_handle:                         ; entry = 0x0C80
        dec     A                   ; 14        index-1 (0-base the key index)
        cjne    A,#0x0E,kh_not_clr  ; B4 0E 09  index 0x0E (CLR) ? [INFER label]
        clr     A                   ; E4        -> reset entry state:
        mov     0x6D,A              ; F5 6D       clear command/arg buffer 0x6D
        mov     0x2A,A              ; F5 2A       clear editor-flags 0x2A
        orl     0x47,#0xF8          ; 43 47 F8    force the row/LED strobe bits high
        ret                         ; 22
kh_not_clr:
        jb      0x57,kh_0cea        ; 20 57 5A  [INFER] debounce/repeat gate
        jb      0x56,kh_0cb1        ; 20 56 1E  [INFER]
        setb    0x57                ; D2 57
        cjne    A,#0x0A,kh_0ca1     ; B4 0A 09  key 0x0A ? [INFER: mode key]
        mov     R3,#0x20            ; 7B 20
        mov     0x29,#0x20          ; 75 29 20  set editor mode/sub-state 0x29
        anl     0x47,#0xF7          ; 53 47 F7
        ret                         ; 22
kh_0ca1:
        jnc     kh_0cb2             ; 50 0F
        dec     A                   ; 14
        cjne    A,#0x06,$+3         ; B4 06 00  compare against 6 (axis count?)
        jnc     kh_0d23             ; 50 7A     index >= 7 -> other handler
        setb    0x55                ; D2 55     [INFER] select/gripper-ish flag
        add     A,#0x50             ; 24 50     A = index + 0x50 -> RAM pointer
        mov     R1,A                ; F9        R1 -> 0x50.. (axis current-pos)
        mov     0x29,#0x40          ; 75 29 40  editor sub-state 0x40
        ; ... handler continues (POSITION-mode axis select, digit entry, the
        ;     MARK/GOTO/IF/OUT/TIM/POS instruction compilers, RUN/STOP, and the
        ;     NVRAM program writer at DPH=3Eh/5800H). NOT yet annotated in this
        ;     pass — see docs/ and hardware/teachbox/board.md for the overview,
        ;     and treat the [INFER] labels above as provisional. [INFER]

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
; - kbd_handle (entry 0x0C80; 0x0C7F is padding) is only annotated at the
;   prologue. It first does DEC A (0-basing the index) then dispatches. The
;   concrete key indices (which index is RUN/STOP/POS/…) should be pinned by
;   tracing the dispatch tables and cross-referencing the key layout in
;   hardware/teachbox/board.md; several labels above are [INFER].
;==============================================================================
