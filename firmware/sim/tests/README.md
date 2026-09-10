# firmware/sim/tests

Behavioral tests for the ROB3 firmware **initialization sequence**. Each script
runs the **real ROM** (`../../hex/M2764A@DIP28.HEX`) in the ucSim `s51`
simulator and asserts that runtime behavior matches
`../../src/main.annotated.asm`.

These complement the *golden byte-match* test (`make verify`), which proves the
transcription equals the ROM. These prove the ROM *behaves* as annotated.

## Running

Normally via the Makefile one level up (it prepares a shell-safe HEX copy and
sets the environment):

```bash
cd firmware
make sim-init     # runs tests/sim_init.sh
make sim-run      # runs tests/sim_run.sh
make test         # golden + both behavioral tests
```

Standalone (must provide the env vars the scripts expect):

```bash
cd firmware
cp hex/M2764A@DIP28.HEX sim/build/rob3.hex
SAFEHEX=sim/build/rob3.hex SIM=s51 SIMFLAGS="-t 51 -X 11.0592M" \
  sim/tests/sim_init.sh
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

## Scope

These tests cover the **init region only** (`0x0600`–`0x074C`). The main loop,
ISRs, serial protocol, and motion interpreter are not exercised here. See
`../../BUILD.md` for the overall build/verify pipeline and `../README.md` for
the directory layout.
