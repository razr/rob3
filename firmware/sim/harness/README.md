# firmware/sim/harness

Foundation for a **closed-loop** ROB3 simulation: drive the real ROM in ucSim
while modelling the board peripherals (ADC feedback + L293 motor outputs) so the
firmware's own servo code can move a modelled arm.

Status: **infrastructure + peripheral-model approach verified.** The full
closed-loop runner (`rob3_sim.py`) is not finished yet — it depends on running
the axis-servo ISR in correct context (see "Open work" below).

## Files

| File | Purpose |
| :--- | :------ |
| `ucsim.py` | Batch driver for `s51` — run a command script, parse `dump`/`Stop at` output. |

## Attaching the Teachbox (input device model)

The Teachbox is the DB25 5x5 key matrix. The firmware scans it by strobing one
matrix ROW at a time via the 8255 (the low nibble of the row latch, RAM `0x47`,
written to 8255 Port B / XRAM `0x5100`) and reading the COLUMN returns on
**P1 (SFR `0x90`)**, top 3 bits = the three column groups (group 1 = P1 bit 5,
group 2 = bit 6, group 3 = bit 7). The scanner (`kbd_scan`, 0x0C00) reads P1 at
**0x0C0F (`MOV A,0x90`)**, and the current row is `RAM 0x46 >> 4` (it advances
0x00, 0x10, 0x20, ... — verified).

So "attaching a teachbox" = presenting, at each P1 read, the column-group bit
for the pressed key **iff** the strobed row matches that key's row.

### ucSim attach mechanisms investigated

- **`-I` simulator interface (SIF):** `-I if=sfr[0x90],in=FILE,out=FILE` DOES
  attach an external I/O module to P1 (verified: P1 reads are intercepted).
  BUT in ucSim 0.8.5 the SIF is a coarse byte-stream on a memory space — its
  file `in=` does not deliver programmable per-read values (P1 reads returned
  `0xFF`), and there is **no socket option** for `-I` (only `in=`/`out=` files).
  So a clean per-read programmable teachbox device via `-I` is not supported in
  this build. (The `-S ...,port=` socket exists only for the UART, not `-I`.)
- **Breakpoint-driven device model (the working approach):** break at the P1
  read (0x0C0F), read `0x46` to learn the strobed row, `set mem sfr 0x90` to the
  pressed key's column bits when the row matches, continue. This faithfully
  models the matrix and needs no peripheral file — but it requires a **stateful
  interactive `s51` session** (to adapt to the variable number of P1 reads per
  scan; a scan exits early on a hit). The batch driver cannot do this because it
  cannot read state mid-script to decide when to stop.

### Next build

A robust **interactive** ucSim driver (use `s51 -p <prompt>` for a reliable
per-command sync marker) that holds a persistent session. On top of it, a
`teachbox.py` device model: `press(key)` -> run the scanner with per-row P1
injection -> return the key index -> feed `kbd_handle` -> observe the axis
state (0x50..0x55, mode 0x29). This ties together the verified `kbd_scan`,
axis-select, and `kh_jog` work into a "type keys, watch the axis" demo.

### Update: a real ucSim teachbox HW module now exists

Rather than the breakpoint-injection approach, a genuine compile-time ucSim
peripheral was written — see `../ucsim-module/` (`teachbox.cc`/`teachboxcl.h`
+ README). It builds into a custom `ucsim_51`, registers as `HW_GPIO`, and
responds to `set hardware teachbox <row> <group>`. Remaining work is
calibrating its strobe->row decode to the firmware's 0x5100 values; see that
README's "Open work".

## Verified: XRAM is the peripheral window

The board's memory-mapped peripherals live in the 8031 external data space
(`MOVX @DPTR`), selected by DPH (see `../../src/annotated/main.annotated.asm` and
`hardware/board/74LS138.md`). Crucially, **ucSim `s51` exposes writable XRAM at
those addresses**, so we can model peripherals by seeding/reading XRAM — no
mid-run interception needed:

| Peripheral        | DPH  | XRAM address | Direction (from CPU) |
| :---------------- | :--- | :----------- | :------------------- |
| 8255 Port A       | 0x50 | `0x5000`     | write (motor dir, L293 #1/#2) |
| 8255 Port B       | 0x51 | `0x5100`     | write strobe / read I/O |
| 8255 Port C       | 0x52 | `0x5200`     | write (motor dir, L293 #3) |
| ADC channel sel   | 0x58 | `0x5800`     | write (channel) / read feedback |
| ADC feedback      | 0x59 | `0x5900`     | read (axis position) |

Verified in ucSim:
- `set mem xram 0x5900 0xAB ; dump xram 0x5900` reads back `0xAB`.
- The servo ISR's feedback-store path (0x00D5: `MOV DPH,#0x59 ; MOVX A,@DPTR ;
  MOV @R1,A`) reads XRAM `0x5900` into its per-axis workspace — seeding `0x77`
  there put `0x77` into workspace `0x58`.

So the closed-loop model is:
1. write the modelled arm position to XRAM `0x5800`/`0x5900` (the ADC),
2. let the servo ISR run,
3. read the commanded motor bits from XRAM `0x5000`/`0x5200`,
4. integrate the modelled arm position toward the commanded direction,
5. repeat.

## Servo ISR touchpoints (verified structure)

Axis-servo ISR entry `0x00C0` (EXT1, fired by ADC EOC -> 8031 pin 13):
- `R1 = R0 + 0x10` (per-axis workspace pointer).
- `JB 0x22.7,0x00D5` / `JNB 0x22.6,0x00DC` — bits of byte **0x22** select the
  feedback-store path vs the compare/drive path (byte-vs-bit!).
- **Feedback store (0x00D5):** read ADC (XRAM 0x5900) into workspace.
- **Compare/drive (0x00DC):** accel/decel table lookups (`MOVC`), error compare,
  then the motor-output stage.
- **Motor output stage (0x01A5 / 0x01B4):** selects Port A (DPH=0x50, shadow
  RAM `0x4E`) or Port C (DPH=0x52, shadow RAM `0x4F`), merges a phase/direction
  value via two `MOVC` mask tables, and `MOVX`es it to the 8255 port.

## Open work (before rob3_sim.py is faithful)

The servo ISR must run with the **live context the firmware builds** (bank-1
registers, the round-robin channel state machine at `0x0278`, per-axis workspace
`0x78+`, and the correct entry via a real INT1). Driving it in isolation with
hand-set state produces non-representative paths (observed: an invariant motor
shadow, or execution running off into unrelated code). The next task is a
focused trace of the ISR's compare->drive path in context so the closed loop
reflects real servoing rather than a guessed model.

### Findings from tracing (2026-09) — the ISR is STATEFUL across invocations

Further tracing established the round-robin tail `0x0278`:
- rotates the one-hot axis mask `0x22` left (advances to the next axis),
- computes the next ADC channel `(R0+1) & 7`, writes it to XRAM `0x5800`,
- sets `R0 = channel | 0x48` (the per-axis base pointer for next time),
- `RETI`.

So the ISR is designed to be **invoked once per ADC conversion**, cycling the 6
axes. Critically, when the compare/drive path (`0x00DC`) was forced in isolation
with hand-seeded `0x50` (target) and XRAM `0x5800/0x5900` (feedback), the motor
shadow (`0x4E`) did **not** vary with the target-vs-feedback error and the code
path was identical for opposite errors. Conclusion: the servo **does not derive
direction from a single-pass (target − feedback)** with the RAM I seeded; it
relies on **accumulated per-axis workspace state (`0x78+`) and bank-1 registers**
built up across successive ISR invocations, plus the accel/decel `MOVC` tables.

**Implication:** a faithful closed loop requires either
  (i) replaying many real ISR invocations while preserving the inter-call
      workspace/bank state and feeding XRAM feedback each pass, or
  (ii) fully reverse-engineering the servo's stateful accel/decel algorithm.
Both are substantial. The XRAM peripheral-model plumbing (above) is ready; the
blocker is the servo algorithm itself, which is the most complex routine in the
ROM and needs a dedicated annotation pass before rob3_sim.py can be trustworthy.

## Usage (current)

```python
from ucsim import UCSimBatch
sim = UCSimBatch("../build/rob3.hex")
out = sim.run(\"\"\"reset
set mem xram 0x5900 0x40
pc 0x00d5
step 3
dump iram 0x58 0x58
\"\"\")
```

Requires `s51` (SDCC ucSim) on PATH; see `../../teachbox/arduino/INSTALL.md`
style notes or install `ucsim`.
