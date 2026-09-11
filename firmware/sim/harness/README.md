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

## Verified: XRAM is the peripheral window

The board's memory-mapped peripherals live in the 8031 external data space
(`MOVX @DPTR`), selected by DPH (see `../../src/main.annotated.asm` and
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
