# Session: ROB3 — Teachbox sim speedup, the P3 emergency-off gates, a loopback module, and a ucSim bug

**Date:** 2026-09-14
**Task:** Started as "how do I start the teachbox CLI" and "connect to ucSim to
see where the firmware is", then snowballed into: (1) fixing why the
firmware-in-the-loop CLI was ~20 s/key, (2) diagnosing why pressing keys in the
sim does *nothing* — the EMERGENCY-OFF trap — (3) building a `loopback` cl_hw
module to clear it, (4) cracking the keypad debounce, (5) landing a black-box
axis-select test, (6) capturing it all in the skills, and (7) filing a genuine
ucSim bug with a repro + patch.

Working method: verify against ROM/simulator/source before asserting; keep the
[BYTE]/[SIM]/[HW]/[INFER] provenance; commit small and honestly. Notably,
**three of my initial "ucSim bug" claims did not survive source verification** —
only one was real.

## Commits (this session, on `main`, not pushed)

1. `03cce34` fix: `run N` -> `step N` for bounded ucSim advance in the teachbox CLI
2. `60a4a3c` docs: annotate the INT0 EMERGENCY-OFF handler (0x0040)
3. `7c7da45` feat(sim): `loopback` cl_hw module + main-loop gate annotation
4. `d68e06b` docs: characterize GATE 4 keypad debounce (release-then-hold)
5. `a07b591` test(sim): black-box axis-select + verified (row,group)->index map
6. `12a1b02` docs(skills): fold findings into rob3-firmware-sim / rob3-firmware-map
7. `f4edeb0` docs(issues): ucSim bug 001 — pipelined command discarded on resUSER

## 1. CLI speed: `run N` doesn't bound — use `step N`  [SIM]

The interactive harness did `press; run_cycles(8000); release` per key, and each
key blocked ~20 s. Root cause (verified in `core/cmd.src/cmd_exec.cc`):
`run [start [stop]]` takes **addresses**, always calls `sim->start(con,0)`, and
in this build free-runs until interrupted — the numeric arg is a *start address*
(`run 8000` -> `PC=0x1F40`), not a cycle budget. `step N` is the bounded
primitive (~4.5 ms for 8000, reason `(109) resSTEP`), reliable even mid-ISR.

- `engine.run_cycles` now issues `step N`. Also batched `push_pots` (6 ADC
  writes in one pty write — safe, no run/step between them).
- Measured: jog/POS sequences ~20 000 ms -> ~30 ms.

Two companion ucSim rules learned the hard way and documented:
- **Never pipeline a command after a run/step in one write** (see issue 001).
- **Bit reads (`JB`/`JNB`) go through the `bits` space**, not the SFR byte cell.

## 2. Why the sim teachbox is silent — three P3 gates  [BYTE][SIM][HW]

Pressing keys changed no IRAM. A PC trace from the main loop went
`0x074D -> 0x0003 -> 0x0040` and looped in `0x0047..0x0054`. Findings:

- **0x0003 (INT0) -> LJMP 0x0040 is the EMERGENCY-OFF handler**, NOT the
  "motor pulse ISR" the docs claimed. INT0 = **P3.2**, wired via **MM74C04N #1**
  to the DB25-pin-4 active-LOW emergency line (`hardware/board/MM74C04N.md`,
  `hardware/teachbox/README.md`, `connectors/db25.md`). It is enabled
  (`IE=0x17`) and **level-triggered** (`TCON.IT0=0`); the handler cuts both
  motor 8255 ports then spins at `0x0054: JNB P3.2, 0x0052` until P3.2 is HIGH.
  Byte-exact (0x0040..0x0071) annotated as `emergency_off` in
  `main.annotated.asm`.
- ucSim's undriven P3.2 reads LOW -> permanent emergency-off -> the main-loop
  teachbox poll (`tb_poll`, 0x07C4) is never reached.
- **GATE 3:** even past emergency-off, `0x07AB: JB P3.4, 0x07C4` gates the poll
  on **P3.4 (T0)** being HIGH — also MM74C04N #1-conditioned.
- The user's intuition was right: the board needs the **RS-232 shorting
  connector** installed; MM74C04N #1 conditions P3.2, P3.4, and P3.0 (baud).

## 3. The `loopback` cl_hw module  [SIM]

`simulator/ucsim-modules/loopback/` — models "RS-232 shorting connector
present": holds **P3.2 and P3.4 HIGH** (leaves P3.0 for the fixed-baud strap).

The hard-won detail: a read-only cell operator is **not** enough to stop the
level-triggered INT0. The interrupt controller (`interrupt.cc`) tracks
`bit_INT0 = (port_pins & port_value)` from `EV_PORT_CHANGED` events and its
`tick()` re-asserts IE0 while `bit_INT0==0`. So the module, on each `tick()`,
writes the P3 latch bits HIGH **through `cell->write()`** (fires the port-change
event) — not `cell->set()`. It also registers the `bits`-space cells 0xB2/0xB4
so `JB`/`JNB` see them HIGH.

Verified: with the module built into `ucsim_51`, a plain `reset; run` leaves
emergency-off and reaches `tb_poll`; existing `sim-teachbox-module` still passes.

## 4. GATE 4 — keypad debounce accept protocol  [SIM]

Scanner runs but no key dispatched. The accept path (`0x0C41`) is gated by
`JNB 0x20.6`, and `0x20.6` is set only by the `key_release` path. So dispatch
requires **RELEASE (sets 0x20.6) -> PRESS + HOLD** the same index across ~3 scan
passes (~24k stepped instr). Holding from reset with no prior release never
dispatches. Documented in both annotated `.asm` files.

## 5. Key map + black-box axis-select test  [SIM]

- Swept (row,group)->index: **index = row+1 + (group-1)*8**.
- **Axis-select = index 0x02..0x07** (group 1, rows 1..6) -> axis 0..5, each
  setting mode `0x29=0x40` (POSITION) — matches the kbd_handle annotation.
- New opt-in test `simulator/tests/test_teachbox_axis_select.py` +
  `make sim-teachbox-axis`: drives the REAL scanner+handler (no hand-seeded
  state) and asserts all six axis keys reach POSITION mode. Skips cleanly
  without the custom `ucsim_51`; added to the aggregate `test`.
- **Not done:** full `POS a . n ENT` value entry+commit (`pos_digit` 0x0D65 /
  `pos_commit` 0x0D9F) — depends on editor state (0x29.3, 0x2A.x, 0x6E:0x6D)
  held across a multi-key sequence that the per-key release cadence disrupts.
  Left as the explicit follow-up.

## 6. Skills updated

- `rob3-firmware-sim`: run-vs-step gotcha, no-pipeline rule, bits-space read
  fact; the loopback module + the P3 gates; the index map + debounce protocol;
  the interactive `engine.py` harness; new Makefile targets; expanded triage.
- `rob3-firmware-map`: corrected the 0x0003->0x0040 vector label to EMERGENCY-OFF;
  resolved the P3.2/P3.4 "open questions"; added the keypad index/debounce facts.

## 7. ucSim bug filed — `issues/`

Created `issues/` with reproducible reports. **Verified each claim against the
ucSim source before filing**, which pruned the list:

- **Issue 001 (real):** a command pipelined after `run`/`step` is consumed as
  the resUSER interrupt and **discarded unexecuted** (`proc_input` early-out in
  `newcmd.cc` + the drain in `sim.cc` ~L258). `repro.py` (ROM-free) reproduces
  on a pristine 0.9.9 build and reports fixed on the patched build;
  `fix-proc_input-execute-interrupting-command.patch` makes the frozen branch
  interpret a non-empty interrupting command (bare ENTER still just stops).
  No regression (ENTER-stops-run preserved; `sim-teachbox-module` passes).
- **Not bugs (documented in issues/README.md):** `run N` takes an address not a
  cycle count (footgun, by design); the `@`-filename segfault is already guarded
  in this checkout; the level-INT0 pin-sampling behaviour is a modeling
  limitation, handled by the loopback module.

## Verification summary

- Golden byte-match (`make verify`) green throughout (asm edits were comments).
- `sim-teachbox-module` green (loopback compiled in — no regression).
- `sim-teachbox-axis` (new) green with the custom `ucsim_51`; skips without it.
- Issue 001 repro: reproduces on pristine build, fixed on patched; ROB3
  `ucsim_51` retains the fix.

## Caveats / open items

- **Full POS numeric entry** (value + commit) is the main open RE task; the
  editor state machine across a multi-key sequence needs mapping.
- **L293 direction map still [INFER]** (unchanged) — servo accel/decel RE.
- The `loopback` module changes must be re-copied into the ucSim source tree if
  that checkout is rebuilt clean (same additive-install caveat as teachbox/adc);
  registration steps are in `simulator/ucsim-modules/README.md`.
- Commits are local on `main`; **not pushed** this session.
