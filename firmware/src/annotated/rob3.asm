;==============================================================================
; ROB3 FIRMWARE — TOP ASSEMBLY UNIT  (rob3.asm)
;==============================================================================
;
; Source ROM image : firmware/bin/M2764A@DIP28.BIN  (8 KB, M2764A EPROM)
; CPU              : Intel 8031 / MCS-51, XTAL = 11.0592 MHz
;
; GOAL — ONE EXECUTABLE, 1:1 WITH THE ROM
;   This file is the single assembly root. It pulls in the symbolic equates
;   (inc/*.inc) and then every code region, in ascending address order, so that
;   `sdas8051 rob3.asm` -> `sdld` -> `objcopy` produces an 8192-byte image that
;   is byte-identical to the original EPROM. The Makefile in this directory
;   does that build and `cmp`s the result against firmware/bin/M2764A@DIP28.BIN.
;
;   Each region file owns its own `.org <addr>` (true ROM offset) and holds the
;   annotated instructions for that region. The unused 0xFF EPROM padding
;   between regions (and after the last code byte, up to 0x1FFF) is emitted by
;   this file so the linked image has no gaps.
;
; STATUS (reorg pass)
;   The region files were split out of the earlier *.annotated.asm listings and
;   carry the full annotations, but they are NOT YET byte-complete: some bodies
;   still contain narrative gaps (e.g. the init baud-measure inner loop, the
;   main-loop motion servicing) and pseudo-targets. So this top unit does not
;   yet assemble to a full 1:1 image. Converting each region to exact,
;   assembling opcodes — gated region-by-region by the Makefile's per-region
;   `cmp` against the ROM slice — is the follow-up to this reorganization.
;
; PROVENANCE: [BYTE]=ROM bytes, [SIM]=ucSim-verified, [HW]=hardware-doc,
;             [INFER]=hypothesis. See each region file for per-line tags.
;==============================================================================

        .area   CODE (ABS)

;------------------------------------------------------------------------------
; Symbolic equates. Included ONCE here; the region files rely on these symbols
; and do not re-include them. One include per subsystem (mirrors the .asm
; regions); system.inc holds the authoritative IRAM map + shared flag bits.
;------------------------------------------------------------------------------
        .include "inc/sfr.inc"          ; 8051 SFRs + bit addresses (architecture)
        .include "inc/devices.inc"      ; MOVX device windows (8255 / ADC / SRAM)
        .include "inc/system.inc"       ; IRAM map + shared flags (0x20/0x23/0x28)
        .include "inc/servo.inc"        ; per-axis arrays + servo masks  (ext1_servo.asm)
        .include "inc/teachbox.inc"     ; keypad / editor state          (teachbox.asm)
        .include "inc/serial.inc"       ; RS-232 workspace + constants   (rs232.asm)
        .include "inc/program.inc"      ; interpreter workspace + opcodes (program.asm)

;------------------------------------------------------------------------------
; Code regions, in ascending ROM-address order. Each file `.org`s at its true
; entry; the FF-padding fill between regions keeps the image byte-perfect.
;
;   region file        ROM range        subsystem
;   -----------        ---------        ---------
;   vectors.asm        0x0000..0x0037   reset + IRQ vector table (+ serial LJMP)
;   ext0_estop.asm     0x0040..0x0071   EXT0 EMERGENCY-OFF ISR
;   timer0_tick.asm    0x0080..0x009D   TIMER0 system-tick ISR
;   ext1_servo.asm     0x00C0..0x0202   EXT1 axis-servo ISR (+ MOVC tables)
;   rs232.asm          0x0203..0x0587   serial: tables, UART ISR (0x0300),
;                                       dispatch (0x03A9), class handlers,
;                                       TX helper (0x0541)
;   init.asm           0x0600..0x074C   reset initialization sequence
;   main.asm           0x074D..0x07F1   main loop (flag poll: teachbox/serial/prog)
;   program.asm        0x0800..0x0A41   prog init (0x0800) + interpreter
;   teachbox.asm       0x0C00..0x0FC4   keypad scanner + editor + POS entry + jog
;   tables.asm         0x0FC5..0x0FDD   shared bit/const lookup table(s)
;------------------------------------------------------------------------------
        .include "vectors.asm"
        .include "ext0_estop.asm"
        .include "timer0_tick.asm"
        .include "ext1_servo.asm"
        .include "rs232.asm"
        .include "init.asm"
        .include "main.asm"
        .include "program.asm"
        .include "teachbox.asm"
        .include "tables.asm"

; End of rob3.asm
