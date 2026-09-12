# simulator/tests

Behavioral tests for the annotated ROB3 firmware regions. Each script runs the
**real ROM** (`../../firmware/hex/M2764A@DIP28.HEX`) in the ucSim `s51`
simulator and asserts that runtime behavior matches the annotated listings
(`../../firmware/src/annotated/main.annotated.asm`,
`../../firmware/src/annotated/teachbox.annotated.asm`).

These complement the *golden byte-match* tests (`make verify`), which prove the
transcriptions equal the ROM. These prove the ROM *behaves* as annotated.

## Running

Normally via the Makefile one level up (it prepares a shell-safe HEX copy and
sets the environment):

```bash
cd simulator
make sim-init      # runs tests/sim_init.sh     (init sequence)
make sim-run       # runs tests/sim_run.sh       (init past the ADC/INT1 gate)
make sim-teachbox  # runs tests/sim_teachbox.sh  (keypad scanner decode, P1 injection)
make sim-teachbox-module  # runs tests/sim_teachbox_module.sh (compiled teachbox cl_hw; opt-in)
make sim-adc       # runs tests/sim_adc.sh (compiled adc cl_hw: free-run past the ADC/INT1 gate; opt-in)
make test          # golden (init+teachbox) + all behavioral tests
```

> `sim-teachbox-module` exercises the **compiled** ucSim teachbox peripheral
> (`../ucsim-modules/teachbox/`) with `set hardware teachbox <row> <group>` instead of
> injecting P1. It needs the custom `ucsim_51` (point at it with
> `UCSIM_51=/path/to/ucsim_51`, or it auto-probes PATH and the default source
> build dir) and **skips** cleanly if that binary isn't present, so a stock-s51
> `make test` still passes.

Standalone (must provide the env vars the scripts expect):

```bash
cd simulator
cp ../firmware/hex/M2764A@DIP28.HEX build/rob3.hex
SAFEHEX=build/rob3.hex SIM=s51 SIMFLAGS="-t 51 -X 11.0592M" \
  tests/sim_init.sh
```

### Environment / knobs

| Var | Default | Meaning |
| :-- | :------ | :------ |
| `SAFEHEX` | (required) | Path to a shell-safe Intel HEX of the ROM. |
| `SIM` | `s51` | ucSim 8051 simulator binary. |
| `SIMFLAGS` | `-t 51 -X 11.0592M` | CPU type and XTAL (11.0592 MHz). |

Each script prints `PASS`/`FAIL` per assertion, dumps the full simulator log on
any failure, and exits non-zero if any assertion fails.

---

## `sim_init.sh` — the hardware-gated stall

**Premise.** Run the ROM from reset and let it free-run (bounded to 400 000
instruction steps). The init deliberately **blocks at `0x0680`**
(`JB 0x22.0, $`). Bit `0x22.0` is cleared only by the EXT1 axis-servo ISR,
which fires on the ADC end-of-conversion (`EOC → INT1`, 8031 pin 13). ucSim
models no ADC, so the pulse never arrives and the wait spins forever — a
bounded run therefore **ends at `0x0680`**. This stall is the *correct,
expected* hardware-dependent behavior, not a hang bug.

**No stimuli injected.** This test observes the unmodified firmware.

**Assertions**

| # | Check | Why |
| :- | :---- | :-- |
| 1 | Simulator stops at `0x000680` | init reaches and holds the ADC/INT1 gate |
| 2 | `SP = 0x31` | stack pointer set in init step (6) |
| 3 | `IE = 0x84` | EA + EX1 enabled in step (9) (axis-servo interrupt) |
| 4 | IRAM `0x22 = 0x01` | axis rotation mask bit0 set — the reason it waits |
| 5 | IRAM `0x47 = 0xFF` | output shadow latch preset in step (6) |

**Simulator commands used**

```
reset ; pc 0x0600 ; step 400000
dump iram 0x20 0x2f ; dump iram 0x47 0x47
dump sfr 0x81 0x81  ; dump sfr 0xa8 0xa8
```

---

## `sim_run.sh` — completing init past the gates

**Premise.** Exercise the *rest* of init by supplying the two external stimuli
that the absent hardware would provide, then confirm init runs to completion.

**Injected stimuli (test scaffolding, not silicon claims)**

1. **ADC EOC / INT1 gate at `0x0680`/`0x0683`.** The axis-servo ISR would
   toggle bit `0x22.0`. Emulated by: break at `0x0680`, `set mem iram 0x22 0x00`
   then `step` (passes the `JB`), `set mem iram 0x22 0x01` then `step` (passes
   the following `JNB`).
2. **Serial baud branch at `0x06A7`.** `JB P3.0` chooses baud auto-detect vs
   fixed baud. We `set mem sfr 0xb0 0x00` (force `P3.0 = 0`) so the **fixed**
   path is taken (`MOV IE,#0x07` → `AJMP` init_finish), avoiding the
   auto-detect loop that waits on a live `P3.0` edge.

**Completion marker.** The test breaks at **`0x074B`** (the final `SETB EA`),
not `0x074D`. Reason: `SETB EA` enables interrupts and the CPU immediately
vectors to a pending ISR, so `0x074D` itself is transient in the simulator.
`0x074B` is the deterministic "init finished" point; the main-loop entry
`0x074D` is the very next instruction.

**Assertions**

| # | Check | Why |
| :- | :---- | :-- |
| 1 | Simulator stops at `0x00074B` | init ran to its final instruction |
| 2 | IRAM `0x48..0x4D = 01 01 01 01 01 01` | 6 axis speed entries preset in step (11) |
| 3 | `IE = 0x07` | fixed-baud path (EX0+ET0+EX1), sampled before `SETB EA` |

**Simulator command sequence**

```
reset ; pc 0x0600
break 0x0680 ; run
set mem iram 0x22 0x00 ; step 1
set mem iram 0x22 0x01 ; step 1
clear ; break 0x06a7 ; run
clear ; set mem sfr 0xb0 0x00
break 0x074b ; run
dump iram 0x48 0x55 ; dump sfr 0xa8 0xa8
```

---

## `sim_teachbox.sh` — keypad scanner decode

**Premise.** Run the Teachbox keypad scanner `kbd_scan` (entry `0x0C00`, see
`../../firmware/src/annotated/teachbox.annotated.asm`) and prove it decodes the column-group bits
into the documented key-index bases. The scanner strobes matrix rows via the
8255 (unmodeled here) and reads the three column groups from **P1 (SFR 0x90)**,
top 3 bits.

**Injected stimulus.** For the first strobe row (row 0), set P1 to activate one
column-group bit, then break at `0x0C2A` (`mov R6,A` — the index finaliser for a
hit) and read the computed index in **R6**.

**Assertions**

| # | P1 value | Group | Expected index base (R6) |
| :- | :------- | :---- | :----------------------- |
| 1 | `0x20` (bit 5) | group 1 | `0x00` |
| 2 | `0x40` (bit 6) | group 2 | `0x08` |
| 3 | `0x80` (bit 7) | group 3 | `0x10` |
| 4 | `0x00` (none)  | —       | scanner does NOT reach the hit path `0x0C2A` |

This validates the 3-group × 8-row index mapping (indices `0x00..0x18` for the
25 keys) without needing the full multi-pass debounce, which requires the real
8255 row hardware.

### Axis select (kbd_handle POSITION mode, entry 0x0C80)

Also asserts the manual's "press a numeric key to select the axis" behaviour
(`hardware/teachbox/README.md`). Feeds a key index into `kbd_handle` (0x0C80),
breaks at the axis-select RET (0x0C0B1), and checks the axis pointer + mode:

| # | key index (A) | axis | Expected R1 | Expected 0x29 |
| :- | :------------ | :--- | :---------- | :------------ |
| 5 | `0x02` | 0 | `0x50` | `0x40` (POSITION) |
| 6 | `0x03` | 1 | `0x51` | `0x40` |
| 7 | `0x07` | 5 | `0x55` | `0x40` |

i.e. axis = keyindex − 2, R1 = 0x50 + axis (that axis's current-position slot).
Byte `0x2A` (which holds the bit-addressed gate flags 0x55/0x56/0x57) is cleared
so the axis path is taken.

### Axis jog (kh_jog, entry 0x0E26)

Asserts the manual's "a +/- ENT" — jog the selected axis one step. With R1
pointing at the axis position slot, ACC bit 0 picks direction:

| # | start (0x51) | ACC.0 | direction | expected |
| :- | :----------- | :---- | :-------- | :------- |
| 8  | `0x80` | 0 | + (increment) | `0x81` |
| 9  | `0x80` | 1 | − (decrement) | `0x7F` |
| 10 | `0xFF` | 0 | + at max | `0xFF` (clamped, no overflow) |
| 11 | `0x00` | 1 | − at min | `0x00` (clamped, no underflow) |

After adjusting the position the routine arms the motion subsystem (sets 0x2F,
watchdog 0x19=0x64) so the servo ISR drives the motor toward the new value.

**Simulator command (per case)**

```
reset ; pc 0x0c00
set mem sfr 0x90 <P1> ; set mem iram 0x47 0x00 ; set mem iram 0x20 0x00
break 0x0c2a ; run        # read R6 at the stop (index base)
```

---

## Interpreting failures

- On failure a script prints `FAIL <what was expected>` followed by the full
  ucSim log under `----- sim output -----`. Compare the actual PC / dumped
  values against the tables above.
- **Stops somewhere other than the expected gate** usually means the init flow
  changed (or the ROM/HEX was regenerated incorrectly). Re-check with
  `make verify` first — if the golden byte-match fails, the transcription is
  wrong and these behavioral results are meaningless.
- **`SAFEHEX not set`** — run via `make`, or export the env vars shown above.
- **Wrong `IE`/register values** — confirm `SIMFLAGS` uses `-t 51` and the
  11.0592 MHz XTAL; a different CPU type can change SFR decoding.

## `sim_adc.sh` — free-run past the ADC/INT1 gate (compiled `cl_adc`, opt-in)

**Premise.** With the **`cl_adc`** peripheral compiled into a custom `ucsim_51`
(see `../ucsim-modules/adc/`), the modelled ADC asserts EOC → INT1, so the ROM no
longer stalls at `0x0680`. This test proves the ROM **free-runs from
`reset; run`** — the only injected condition is `P3.0 = 0` (a serial-line
choice for the fixed-baud path, not an ADC one).

**Assertions.**
1. Free-run reaches the main loop `0x074D` (no hand-injected ADC/INT1 stimulus).
2. The axis-servo ISR (`0x00C0`) fires on its own from a natural EOC → INT1.
3. A seeded feedback value flows through the ISR's `MOVX A,@DPTR` read
   (`set hardware adc <ch> 0x5A` → ACC = `0x5A` right after `0x00D8`).

**Opt-in.** Like `sim_teachbox_module.sh`, it needs the custom `ucsim_51`
(`UCSIM_51=/path/to/ucsim_51`, or it probes PATH and the default source-build
dir) and **skips** cleanly if that binary or the `adc` element is absent, so a
stock-`s51` `make test` still passes. Contrast with `sim_run.sh`, which gets the
same end state on *stock* `s51` by hand-injecting the gate — `sim_adc.sh` shows
the real device doing it instead.

## Scope

These tests cover the annotated regions: the **init sequence** (`0x0600`–
`0x074C`) and the **Teachbox keypad scanner** (`0x0C00`–`0x0C6B`). The main
loop, ISRs, serial protocol, motion interpreter, and the rest of the Teachbox
key handler (`0x0C80`+) are not exercised here. See `../BUILD.md` for the
overall build/verify pipeline and `../README.md` for the directory layout.
