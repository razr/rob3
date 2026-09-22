# Session: ROB3 — annotate all 10 assembling regions (per-instruction)

**Date:** 2026-09-22 (continues `2026-09-22_annotated_dir_redesign_assembling_1to1.md`,
which reorganized `firmware/src/annotated/` into the assembling 1:1 tree)

**Task:** After the reorg produced 10 assembling regions (4 hand-annotated, 6
raw `d51_to_sdas` bodies), annotate the remaining regions — section banners,
symbolic operands from `inc/*.inc`, marked MOVC data tables, collapsed 0xFF
padding — keeping every region byte-identical to the ROM.

Working method: convert one region at a time; verify each with
`make verify-region REGION=<name>` and the whole image with `make verify`
(SHA-256 match); commit per region. Never claim 1:1 until `cmp` proves it.

## Commits (this session, on `main`)

- `565a180` fully annotate init, main, vectors, tables (symbolic operands)
- `6c9ea7b` annotate ext1_servo body (axis servo ISR)
- `d649aca` annotate program.asm (interpreter) — sections + symbolic operands
- `41f5f4b` annotate teachbox.asm — sections + symbolic + MOVC markers
- `1ac04a9` annotate rs232.asm — sections + symbolic + MOVC markers
- `20bd902` fix: vectors numeric ljmp targets (standalone verify); pad-to in verify-region

## What was annotated

| Region | Result |
| :----- | :----- |
| `vectors.asm` | numeric `ljmp` targets + IC/device-map header; standalone-safe |
| `ext0_estop.asm` | (already done in reorg) fully symbolic |
| `timer0_tick.asm` | (already done in reorg) fully symbolic |
| `ext1_servo.asm` | block banners (phase dispatch / feedback / control / error / lookup / motor drive), symbolic operands, inline MOVC tables emitted as `.db` and marked |
| `rs232.asm` | banners at data tables (0x0203), isr_serial (0x0300), rx_dispatch (0x03A9), cmd_class0 (0x0440), TX helper (0x053B); MOVC 1<<axis table marked; symbolic RX_FLAGS/8255/ADC |
| `init.asm` | full 13-step init annotation, symbolic equates, named labels |
| `main.asm` | named blocks (motion servicing, serial housekeeping, P3 gates, tb_poll) + dout_write helper documented |
| `program.asm` | banners at prog_init (0x0800), motion_exec (0x0900), prog_exec (0x0941), prog_goto (0x0A33); symbolic PROG_PAGE/PROG_END/STATE_FLAGS |
| `teachbox.asm` | banners at kbd_scan/kbd_handle/pos_digit/pos_commit/kh_jog; symbolic LED_LATCH/KBD_STROBE/EDIT_*; MOVC display + bit_table reads marked |
| `tables.asm` | (already done) bit_table + xram_fetch16 |

## Method decisions

- **Data tables: mark, don't extract** (per request). The inline MOVC lookup
  tables are read `MOVC A,@A+PC` (PC-relative), so they must stay adjacent to
  their reader at the true `.org`; extracting them to a separate area would risk
  the offset math. They are delimited with `; --- MOVC DATA: ... ---` banners
  and emitted as `.db` where the linear disassembly mis-decoded them as code.
- **0xFF padding collapsed** via `/tmp/collapse_pad.py`: runs of ≥4 `mov R7, A`
  (0xFF) become a `; --- 0x... padding ---` note + a fresh `.org` at the byte
  after the run; `objcopy --gap-fill=0xFF` reproduces the padding. Removed ~109
  padding lines from `program`, similar from `teachbox`/`rs232`.
- **"Dead data"** (`00 12 22` at 0x0020) is still emitted explicitly (`.db`) —
  non-0xFF bytes must match 1:1 even though nothing executes them.

## Corrections (byte-vs-bit, cross-region)

- `init`: `setb 0x18` is bit **0x23.0**, NOT the SER_TIMEOUT *byte* 0x18
  (byte-vs-bit collision) — annotation fixed.
- `main`: `jnb 0x22` is bit **0x24.2** (RX ready), NOT SYS_BAUD_DET (0x02) —
  wrong symbol, reverted to numeric.
- `ext1_servo`: three `ajmp` to **0x0278** target an address in the rs232
  region (the servo advance/RETI code lives at 0x0278); kept numeric, not a
  local label.
- `vectors`: `ljmp` targets reverted from symbolic labels (init_start,
  emergency_off, timer0_isr — defined in other files) to numeric, so
  `verify-region` works standalone.

## Tooling

- `verify-region` objcopy now uses `--pad-to=$$((org+len))` so regions with
  internal `.org` gaps (e.g. ext1_servo's MOVC data tail) pad correctly for the
  slice `cmp`.
- `make status` now runs `verify-region` for every region (per-region PASS/FAIL).

## Verification

- `make verify` (whole image): **PASS 1:1** — 8192 bytes,
  SHA-256 `1e94419d1c65b6b0110734848e0b7f93b225c52c65e4c68b35e0ce962a24d62f`.
- `make status`: **all 10 regions PASS** standalone.
- `simulator/make test` (golden + behavioral): **ALL TESTS PASSED**.

## Open / next

- **Deeper per-instruction annotation of the inner logic** in the big handlers
  (ext1_servo profile/decel math; rs232 RX/TX state machine branches; program
  interpreter opcode decode) — banners + symbols are in place, but many inner
  lines still carry only the raw byte comment. Upgrade incrementally, gated by
  `make verify-region`.
- Per-opcode program-interpreter operand semantics remain `[INFER]` beyond the
  `[SIM]`-checked cases.
- 6 session commits were local; user has since pushed.
