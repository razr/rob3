# Session: ROB3 — RS-232 command set confirmed, hidden commands, program subsystem + interpreter, hello-world program

**Date:** 2026-09-20 (continuation of the same day's RS-232 work; see also
`2026-09-20_rs232_annotation_protocol_sim_rxd_driver.md` for the earlier
annotation / protocol-[SIM] / rxd-driver / end-to-end-serial part)

**Task:** After annotating and simulating the RS-232 UART, verify the documented
host command set against the ROM, hunt for undocumented commands, pin down the
`0xFx` reply semantics, then reverse-engineer and annotate the stored-program
subsystem (shared with the Teachbox) and prove it with a "hello world" program.

Working method throughout: verify against the ROM/simulator before asserting;
keep the [BYTE]/[SIM]/[HW]/[INFER] provenance; commit small and honestly.
Notably, several manual/earlier claims were **corrected** by the ROM (the ETX
dispatch check, the bit7 command-class direction, the `0xF2`/`0xF3` startup
grouping, the SRAM base) — recorded as findings, not hidden.

## Commits (this session, on `main`, not pushed)

- `d44107f` confirm the RS-232 command set against the ROM
- `fe3c4a8` document undocumented/hidden RS-232 commands
- `c89b5a3` verify startup reply bytes 0x15/0xF1/0xF2/0xF3 and WHEN
- `e77987e` clarify the 0xFx replies are ACK/status, not errors
- `10eb5f2` rewrite the startup-reply table with ROM-verified meanings
- `c17adc9` document the stored-program subsystem (shared with the Teachbox)
- `1caff60` document program memory size & interpreter locations
- `b3c314f` annotate the stored-program interpreter
- `937190e` "hello world" stored program — hand-assemble, load, run
- `6e8680b` fold findings into skills / lessons-learned
- (plus the earlier `00b0ed5` RS-232 annotation + rxd driver)

## 1. Command-set confirmation  [SIM]

Drove every documented command header through the real dispatch (`rx_dispatch`
0x03A9) and observed the effect. **Correction:** the `cjne A,#0x03` at 0x03AE is
an **ETX frame-terminator check** — to seed a command you set **A=0x03 (ETX)**
and the **header in R6**, then it reloads the header (`mov A,R6`). My earlier
"header remainder != 3" note was wrong. Confirmed:
- `0x40–0x45/0x4F` position query → header + feedback + ETX
- `0x00–0x07/0x0F` set position → 0x50+
- `0x70–0x77/0x7F` position+speed → target 0x40+ + motion mask 0x2B (0x3F all)
- `0x60/0x61/0x62` motor disable / enable(0x20.0) / shutdown(snapshot fb→pos)
- `0x63` serial number → header + S0..S2 + ETX
- **bit7=0 = axis/position class; bit7=1 = system/program** (manual/skill had
  this inverted — fixed). bit3 = ack `R` → 0x23.1.
Added a "ROM confirmation" table to `hardware/host/command.md` + 6 routing
assertions to `simulator/tests/sim_serial.sh`.

## 2. Hidden / undocumented commands  [SIM]

Swept all 0x00..0xFF through the dispatch:
- **Digital-input read family (genuinely undocumented):** `0x50–0x57`
  (bit4=1 in the 010x class) append aux/digital-input bytes (RAM 0x5E, 0x5F,
  P1) instead of an axis pot — e.g. `0x56` → `[56, 0x5F, P1, ETX]`. Reads the
  DB25 DI lines over serial.
- **Aliases (not new commands):** the control block ignores bits 3:2 so
  `0x64..0x6F` repeat `0x60..0x63`; the ack bit makes `0x08../0x78../0x0F`
  equivalent to their R=0 forms; axis field 6 is invalid.
- **ETX enforced:** a frame is acted on only if it ends with `0x03`.
Documented in command.md; regression assertions added (hidden 0x56, alias 0x65).

## 3. Startup replies + the 0xFx family  [SIM]

- **`0x15`** = init-OK, direct `mov SBUF,#0x15` at 0x0733 when auto-baud locks
  (verified on the wire).
- **`0xF1`** = already-init, main-loop idle-timeout at 0x0793 when a byte is
  received after the UART is up (verified on the wire: `15 F1`).
- **`0xF3`** = default command ACK (dispatch default 0x03AC); the post-init
  `0x20`-as-command reply.
- **`0xF2`** = NOT a startup reply — it is a program single-step status
  (0x0437, system-class chain). The manual's grouping of 0xF2 with "multiple
  init" is inaccurate; rewrote the startup-reply table accordingly.
- **All `0xFx` are ACK/status bytes, not errors** (0xF3 default, 0xF4 system,
  0xF6/0xF2 program, 0xF7 motion-complete). No distinct NAK byte exists; even a
  malformed (non-ETX) frame gets 0xF3. "Any other response = error" means a byte
  outside the defined set.

## 4. Stored-program subsystem  [SIM]/[HW-doc]

**Same programs as the Teachbox** (teachbox/README: keypad OR RS-232 program the
robot; instructions stored in memory). Confirmed:
- **Store:** external HM6264 8 KB SRAM, base page `0x80` (IRAM 0x3E), body page
  `0x81` (0x3F). Battery-backed/nonvolatile.
- **Upload:** the `0x81` block command → block-store mode (0x24.3); bytes stream
  to SRAM via MOVX (verified a byte lands at 0x8100); `0x28.1` = program-loaded.
- **Execute:** the hdr.7=1 system commands manipulate `0x28` (loaded/running/
  motion/conditional) and call the interpreter — the Teachbox RUN/STEP/STOP.
- **Size/layout:** page 0x80 = label table (2-byte entries, ~128 labels, matches
  MARK m=0..118) + header/end-marker at 0x80EE..; pages 0x81..0x9F = program
  body (~7.9 KB). PC = 16-bit 0x66:0x67.

## 5. Program interpreter annotation  [BYTE][SIM]

New `firmware/src/annotated/program_interpreter.annotated.asm`:
- **`prog_prepare` (0x0803)** — label-table preprocessor; records each MARK
  (opcode `0x1F`) as a 2-byte PC; validates header/end sentinel `0x83`.
- **`motion_exec` (0x08FF)** — main-loop gate; advances motion, and on step
  completion (or TIM/IF wait) fetches the next instruction.
- **`prog_exec` (0x0941)** — executor; fetches opcode into `0x27`, decodes with
  the **same bit fields as the RS-232 dispatch**; most instructions are an
  **8-byte slot**.
- **`prog_goto` (0x0A33)** — label→PC resolver (rl A ×2 into the page-0x80 table).
- Opcodes: `0x1F`=MARK, `0x36`=3-byte instr, bit7=END; positioning/store-pos/
  OUT/TIM/IF-GOTO share the command encoding. Per-opcode operand layout beyond
  the [SIM]-checked cases is [INFER].
Verified with `simulator/tests/sim_program.sh` (5 assertions): opcode fetch into
0x27, 8-byte advance (0x8100→0x8108), store-position 0x07→0x50.., end-marker
stops, GOTO label→PC.

## 6. "Hello world" program  [SIM]

`simulator/tests/demo_hello_program.sh` + `make demo-hello-program`:
```
0x8100: 60 80 ...   MOVE axis0 -> 0x80
0x8108: 61 40 ...   MOVE axis1 -> 0x40
0x8110: 80          END
```
Hand-assembled from the verified encoding, loaded into SRAM, and run — per-
instruction (axis targets set, PC advances, END stops) AND **AUTO**: from a
plain `reset; run` to the main loop, the firmware self-executes it via
motion_exec→prog_exec (axis0 target → 0x80, no manual entry).

## 7. Skills / lessons updated

- `rob3-firmware-map`: fixed the inverted bit7 command class; added the verified
  command map / ETX / 0xFx-ACKs / auto-baud-only; upgraded the program-
  interpreter entry (prog_prepare/prog_exec/prog_goto, opcodes, SRAM layout);
  corrected the SRAM base to 0x80.
- `rob3-firmware-sim`: added sim-program, sim-serial-e2e, demo-hello-program.
- `rob3-lessons-learned`: added the `rx_dispatch` A=ETX/header-in-R6 seeding
  trap and the bit7 command-class convention.

## Verification

- `make verify` (golden byte-match) green throughout (asm edits are docs).
- `make test` → ALL TESTS PASSED on stock `s51` and the loader `ucsim_51`.
- New behavioral tests: sim_serial (16 assertions incl. routing/hidden/status),
  sim_program (5), demo_hello_program.
- All `.so` gitignored; whitespace clean; skill YAML valid.

## Open / next

- Per-opcode operand layout of the program instruction set is still [INFER]
  beyond the [SIM]-checked cases (fuller per-instruction sim pass is future work).
- The system-class program upload/download over the wire (0x81 stream +
  0x89..0x8F) is [SIM] for transport but not a full multi-frame end-to-end run.
- **NEXT (requested):** a ROS2 driver for ROB3 over RS-232, structured like the
  UR ROS2 driver (ros2_control hardware interface + serial protocol client +
  URDF/launch/config). Not started.
- Commits remain local on `main`; **not pushed** (11 commits ahead of origin).
