# Session: ROB3 — RS-232 shorting connector traced, loopback module clarified

**Date:** 2026-09-16
**Task:** Started as "why didn't my Delock RS-232/422/485 loopback plug unblock
the teachbox?" and turned into: (1) tracing what the ROB3 "9-pin shorting
connector" actually is electrically, (2) writing a proper, provenance-tagged
description of it with a build-the-plug TODO, (3) auditing and correcting the
ucSim `loopback` module's implementation vs. its documentation, and (4) pinning
down the in-tree ucSim SDK location in the build docs.

Working method: verify against ROM/board docs before asserting; keep the
[BYTE]/[SIM]/[HW]/[INFER] provenance. Notably, **my first electrical reading was
wrong** (I claimed P3.4 idles HIGH with pin 4 open → "no plug needed"); the
user's bench result (a 2↔3 loopback does *not* work) plus the full DB9 trace
forced a correction, now recorded as an explicit open question rather than a
guess.

## Commits (this session, on `main`, not pushed)

_(filled in by the commit that accompanies this log)_

## 1. Why the Delock plug failed  [HW-doc][HW-bench]

The ROB3 teachbox only runs when two Port-3 gates are the right level:

- **P3.4 / T0 (poll enable)** — the ROM does `jb 0B0h.4, jump_07C4`
  (**JB P3.4, tb_poll**) at 0x07AB (`firmware/src/main.asm`): the keypad scanner
  is called **only when P3.4 = HIGH**. [BYTE]
- **P3.2 / INT0 (EMERGENCY-OFF)** — active LOW, must be HIGH or the ROM spins in
  the 0x0040 handler forever. Set on the real board by the **DB25 STOP path**,
  not the DB9. [BYTE][HW]

A commercial RS-232 loopback echoes TX↔RX (DB9 2↔3), which only touches
**P3.0/RXD** — not P3.2 or P3.4. The 422/485 differential pairs don't exist on
this DB9 at all. The user confirmed on the bench that a **2↔3** plug does **not**
unblock the teachbox, so "short TX↔RX" is a dead theory.

## 2. Full DB9 pin trace  [HW-doc]

Traced across `rs232.md`, `board/MM74C04N.md`, `board/M34004.md`,
`board/resistor-pullup-array.md`:

| DB9 | Board connection | Strap target? |
| :-- | :--------------- | :------------ |
| 1 | none documented | probe it |
| 2 | MM74C04N #1 IN6 (10k) → P3.0/RXD | serial path |
| 3 | M34004 OUT1 ← robot TXD | driver output |
| 4 | MM74C04N #1 IN4 (10k) → P3.4/T0 poll gate | **the gate of interest** |
| 5 | GND | ground |
| 6/7/8 | none documented | probe them |
| 9 | M34004 ref via 22k — **physically cut** | dead |

Two hard conclusions: **no DB9 pin carries +5V** in any doc (so a passive plug
can't strap pin 4 to VCC), and **pin 9 is cut**.

## 3. The unresolved contradiction (TODO for the bench)  [INFER]

The documented conditioning (100 kΩ *pulldown* on IN4) says pin 4 open → P3.4
already HIGH → no plug needed — which contradicts both the manual AND the bench
result. So a doc assumption is wrong.

**Leading hypothesis:** the IN4 resistor is actually a **pull-UP to +5V** (the
pullup-array doc hints `o-- Vcc`). Then pin 4 open → P3.4 LOW → gate closed →
teachbox blocked (matches symptom), and the real shorting connector is simply
**DB9 pin 4 ↔ pin 5 (GND)**. One measurement decides it (P3.4 at 8031 pin 14,
DB9 pin 4 voltage, and probe pins 1/6/7/8 for +5V). Full write-up +
build-the-plug procedure in the new
`hardware/connectors/rs232-shorting-connector.md`.

## 4. loopback module: audit + doc corrections

The `cl_loopback` plugin is correct and [SIM]-verified **as a simulation aid**:
it forces P3.2/P3.4 HIGH (mask 0x14) so the ROM leaves the emergency-off handler
and reaches `tb_poll`; P3.0 is left alone. It is **not** a wiring-accurate model
of the connector, and (post-trace) P3.2's real source is the DB25 STOP path, not
the DB9.

Corrected the docs to match code + trace (code unchanged):

- `loopbackcl.h` — reframed as a simulation aid that forces the 8031-pin end
  state, doesn't touch P3.0, doesn't reproduce the (unresolved) DB9 strap.
- `loopback/README.md` — replaced the "three gates / P3.0 baud strap" table with
  a 3-column table (P3.2 from DB25 STOP path, P3.4 from DB9 pin 4, P3.0 not
  driven) + sim-aid note + link to the connector doc.

## 5. ucSim SDK location in build docs

The module Makefile defaults `SDK` to the installed `/usr/local/share/ucsim/sdk`,
which isn't present here. The in-tree SDK is at **`~/github/razr/ucsim/sdk`**
(headers already exported). Documented the concrete path and the working command
in `simulator/ucsim-modules/README.md` and `loopback/README.md`:

```bash
make -C simulator/ucsim-modules SDK="$HOME/github/razr/ucsim/sdk" all
```

Verified: builds `loopback.so`, `adc.so`, `teachbox.so` clean (only pre-existing
SDK `-Woverloaded-virtual` warnings). [SIM/build]

## Files changed

- **new** `hardware/connectors/rs232-shorting-connector.md`
- `hardware/connectors/rs232.md` (cross-link + pin-4 discrepancy note)
- `simulator/ucsim-modules/README.md` (SDK location + in-tree build cmd)
- `simulator/ucsim-modules/loopback/README.md` (table fix, sim-aid framing, SDK)
- `simulator/ucsim-modules/loopback/loopback.cc` (comment-only)
- `simulator/ucsim-modules/loopback/loopbackcl.h` (comment-only)

## Open / next

- **Bench measurement** to resolve the pin-4 pull-up-vs-pulldown question, then
  finalize the shorting-connector strap map (likely 4↔5). [INFER → HW]
- Reconcile the `rs232.md` ↔ `MM74C04N.md` ↔ `resistor-pullup-array.md`
  resistor-polarity discrepancy once measured.
