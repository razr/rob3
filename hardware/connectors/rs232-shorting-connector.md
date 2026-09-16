# RS-232 Shorting Connector (9-pin)

The ROB3i manual lists a **"9-pin shorting connector"** as a hardware
requirement, plugged into the **RS-232 (DB9) port** whenever the robot is run
standalone with the Teachbox (`../teachbox/README.md`, "Hardware
Installation"):

> Plug the Teachbox's 25-pin male connector into the I/O port and the 9-pin
> shorting connector into the RS-232 port.

The manual states the *requirement* but **not the wiring**. This document
derives the wiring from the board reverse-engineering and — importantly —
distinguishes what is verified from what is still inferred.

## It is NOT an RS-232 data loopback

A commercial RS-232 loopback plug bridges the **data/handshake** lines
(TX↔RX = DB9 2↔3, and typically DTR↔DSR↔DCD = 4↔6↔1, RTS↔CTS = 7↔8). An
RS-232/422/485 adapter (e.g. the Delock part) additionally loops the
**differential pairs**, which do not exist on this DB9 at all.

Neither of those is what the ROB3 needs. On this board the DB9 pins do **not**
carry a normal PC handshake; they are tapped straight into **MM74C04N #1**
input-conditioning nodes (`../board/MM74C04N.md`,
`../board/resistor-pullup-array.md`). So "shorting connector" here means
*a plug that forces specific conditioning nodes to a defined level*, not a plug
that echoes serial traffic. This is why a generic loopback / 422-485 adapter
does not unblock the Teachbox.

## What the DB9 pins actually connect to  [HW-doc]

From `../board/MM74C04N.md` (MM74C04N #1) and `rs232.md`:

| DB9 pin | Board node | Series R | Node pulldown | Inverter | 8031 pin | Firmware role |
| :------ | :--------- | :------- | :------------ | :------- | :------- | :------------ |
| 2 | IN 6 (pin 13) | 10 kΩ | 100 kΩ → GND | OUT 6 (pin 12) | P3.0 / RXD (pin 10) | serial RX / baud strap |
| 3 | OUT 1 of M34004 | — | — | (TX driver out) | P3.1 / TXD (pin 11) | serial TX (host RX) |
| 4 | IN 4 (pin 9) | 10 kΩ | 100 kΩ → GND | OUT 4 (pin 8) | P3.4 / T0 (pin 14) | teach-poll enable gate |
| 5 | GND | — | — | — | — | ground |

Each conditioning input (pins 2 and 4) has a **100 kΩ pulldown to GND** and a
**10 kΩ series resistor** to the DB9 pin. So:

- **DB9 pin open** → the 100 kΩ pulldown wins → inverter INPUT LOW → inverter
  OUTPUT HIGH → the 8031 pin (P3.0 / P3.4) reads **HIGH**.
- **DB9 pin driven/shorted HIGH** → inverter INPUT HIGH → OUTPUT LOW → the
  8031 pin reads **LOW**.

Note the polarity is **inverting**: shorting these DB9 pins HIGH pulls the
corresponding P3 gate LOW.

## The two firmware gates  [SIM][BYTE]

The firmware only reaches the Teachbox poll (`tb_poll`, 0x07C4) when two Port-3
inputs are the right level (see `../../firmware/src/annotated/main.annotated.asm`
and `../../simulator/ucsim-modules/loopback/README.md`):

1. **P3.2 / INT0 = EMERGENCY-OFF**, active LOW → must be **HIGH** to run.
   This comes from the **DB25 STOP path** (MM74C04N #1 IN 1 ← DB25 pin 4 with a
   +5V pullup), **not** from the DB9. It idles HIGH when STOP is not pressed.
   The RS-232 connector does **not** set this. [HW]
2. **P3.4 / T0 = poll enable**, must be **HIGH** to pass the gate.
   The exact instruction is at 0x07AB in `../../firmware/src/main.asm`:
   `jb 0B0h.4, jump_07C4` — **JB P3.4, tb_poll**. The scanner
   (`LCALL 0x0BFF` = kbd_scan) is called **only when P3.4 = HIGH**; if P3.4 is
   LOW the ROM skips the poll. So **P3.4 must be HIGH**. [BYTE]
   Electrically P3.4 (8031 pin 14) = OUT4 (MM74C04N #1 pin 8) = NOT(IN4),
   IN4 = pin 9 = the DB9-pin-4 node. [HW-doc]

## TRACE RESULT — full DB9 pin inventory  [HW-doc]

Traced across `rs232.md`, `../board/MM74C04N.md`, `../board/M34004.md`,
`../board/resistor-pullup-array.md`:

| DB9 pin | Connection on the ROB3 board | Usable as a strap target? |
| :------ | :--------------------------- | :------------------------ |
| 1 | (no documented connection) | unknown — probe it |
| 2 | MM74C04N #1 IN6 (10k) → P3.0/RXD | yes (serial path) |
| 3 | M34004 OUT1 ← robot TXD | it's a driver OUTPUT |
| 4 | MM74C04N #1 IN4 (10k) → P3.4/T0 poll gate | **yes — the gate of interest** |
| 5 | GND | yes (ground reference) |
| 6 | (no documented connection) | unknown — probe it |
| 7 | (no documented connection) | unknown — probe it |
| 8 | (no documented connection) | unknown — probe it |
| 9 | M34004 ref (pins 3/12) via 22k — **PHYSICALLY CUT** on this board | **no — dead** |

**Two hard conclusions from the trace:**

- **No DB9 pin carries +5V** in any board doc. Therefore a passive plug cannot
  strap DB9 pin 4 to +5V — there is no +5V source pin on this connector. Any
  "short pin 4 to VCC" idea is dead unless a bench probe finds +5V on pin
  1/6/7/8 (undocumented).
- **DB9 pin 9 is cut** — cannot be used as a strap node.

## Bench evidence so far  [HW-bench]

- A commercial **RS-232/422/485 loopback** (Delock) bridging **DB9 2↔3** was
  installed and **did NOT unblock the Teachbox**. So "short TX↔RX" (the
  `rs232.md` pins-2/3/5 theory) is **confirmed insufficient**. The 422/485
  differential pairs are meaningless on this DB9.

## TODO — resolve before building the plug  [INFER]

The trace produced a genuine contradiction that ONE bench measurement settles:

- **The documented conditioning cannot be driven by any documented DB9 short.**
  Per `MM74C04N.md`, IN4 has a 100 kΩ **pulldown** to GND, so DB9 pin 4 open →
  IN4 LOW → P3.4 HIGH → gate already open → no plug needed. That contradicts
  BOTH the manual ("connector required") AND the bench result (Teachbox still
  blocked). One of the doc's assumptions is therefore wrong.

- **Leading hypothesis (buildable, matches all evidence):** the resistor on the
  IN4 node is actually a **pull-UP to +5V**, not a pulldown (note
  `resistor-pullup-array.md` shows these nodes tied `o-- Vcc`). Then:
  - pin 4 open → IN4 HIGH → **P3.4 LOW → gate CLOSED → Teachbox blocked** ✓ (matches symptom)
  - plug shorts **DB9 pin 4 → pin 5 (GND)** → IN4 forced LOW → **P3.4 HIGH → gate OPEN** ✓
  If confirmed, the shorting connector is simply **pin 4 ↔ pin 5**, possibly
  with **2↔3** as well for the serial idle. This uses only documented pins and
  needs no +5V source.

- **Alternative hypotheses still open:**
  1. The connector's real purpose is the **RXD/baud path** on pin 2 (P3.0),
     and P3.4 is asserted by a route not captured in the docs.
  2. There IS an undocumented +5V on DB9 pin 1/6/7/8 and the plug straps pin 4
     to it (pin 4 needs to go HIGH, not LOW).

- **The single measurement that decides it** (RS-232 port empty, powered, just
  after RESET, meter to GND):
  1. 8031 **pin 14 (P3.4)** — HIGH or LOW? (Expect LOW if the gate is closed.)
  2. DB9 **pin 4** — voltage? (Near +5V ⇒ pull-up ⇒ strap pin 4→GND.
     Near 0 V ⇒ pulldown ⇒ the docs' polarity holds and something else is wrong.)
  3. Probe DB9 **pins 1, 6, 7, 8** for any **+5V** (would enable a pin-4→VCC strap).

  Then the plug is one solder bridge:
  - pin 4 reads ~+5V (pull-up) → **bridge DB9 pin 4 ↔ pin 5 (GND)**.
  - a spare pin reads +5V and pin 4 must go HIGH → **bridge pin 4 ↔ that pin**.

- **Doc discrepancy to fix:** `rs232.md` (pins 2/3/5 only) vs `MM74C04N.md`
  (pin 4 used) vs `resistor-pullup-array.md` (nodes to Vcc). Reconcile the
  IN4/IN6 resistor as pull-up vs pulldown once measured — that is the root
  ambiguity behind this whole question.

**Provenance:** DB9→MM74C04N/M34004 wiring, the `JB P3.4` gate, and the
"2↔3 doesn't work" result are **[BYTE]/[HW-doc]/[HW-bench]**; the resulting
strap (pin 4↔5 vs pin 4↔+5V) is **[INFER]** until the measurement above.

## How to verify on the bench

1. With NO connector, meter 8031 **pin 14 (P3.4)** and **pin 12 (P3.2)** vs VCC
   right after RESET. If both are already HIGH, the trace (P3.4 idles HIGH) is
   right and the connector's role is the serial path (option 1 above).
2. Buzz out the genuine ROB3 shorting plug pin-to-pin (which DB9 pins are tied
   together, and to any +5V). That directly yields the correct strap map.
3. Cross-check by driving each candidate strap in ucSim (see the loopback
   module) and confirming the ROM reaches `tb_poll`.

Until step 2 is done, do **not** assume a store-bought loopback (data or
422/485) reproduces the ROB3 shorting connector — the evidence so far says it
does not.
