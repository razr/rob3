# ROB3 ADC0808/0809 — ucSim hardware module (`cl_adc`)

The single change that lets the real ROM **free-run from `reset; run`**.

For build/registration steps and the shared gotchas, see the
[parent README](../README.md).

## Files

| File | Purpose |
| :--- | :------ |
| `adc.cc`  | The `cl_adc` peripheral implementation. |
| `adccl.h` | Its class declaration. |

## Why it exists

Stock ucSim models the MCS-51 core only, with no ADC. The ROB3 firmware depends
on the external ADC that reads the six axis-feedback pots:

- **Init blocks at `0x0680`** (`JB/JNB 0x22.0`) waiting for the axis-servo ISR,
  which only runs when the ADC asserts **EOC → INT1**.
- The **servo ISR** (`EXT1`, `0x00C0`) reads a feedback byte via `MOVX` from the
  ADC window and cycles the six channels round-robin.

With no ADC, the ROM stalls forever — which is why `make sim-run` had to
hand-inject IRAM `0x22` to fake the EOC. `cl_adc` replaces that scaffolding with
a real device.

## What it models

| Behaviour | Detail | Provenance |
| :-------- | :----- | :--------- |
| Channel select + START | `write` to XRAM `0x5800` latches `channel = val & 7` and arms an EOC countdown | [BYTE] round-robin tail `0x0278` writes next channel to the ADC window |
| Feedback read | `read` of XRAM `0x5800`/`0x5900` returns `feedback[channel]` | [SIM] servo ISR `0x00D5`: `MOV DPH,#0x59 / MOVX A,@DPTR` reads `0x5900` |
| EOC → INT1 | on countdown expiry, sets **TCON.IE1 (0x08)**; the core's external-#1 it-source vectors to `0x0013 → 0x00C0` when EA+EX1 are set | [HW] ADC EOC wired to 8031 INT1 (pin 13) |
| Closed loop (opt-in) | integrates the selected axis' pot from the L293 motor bits on `0x5000`/`0x5200` | [INFER] exact per-axis bit map — coarse, clearly labelled |

The EOC→INT1 assertion is the crux: it is the *natural* trigger the firmware is
written around (one conversion per channel select, one servo-ISR invocation per
EOC, six axes cycled), so nothing has to be hand-injected.

## Commands

```
set hardware adc <ch> <value>   # force feedback[ch] = value (0..255)
set hardware adc <0|1>          # disable/enable the L293->arm integrator
set hardware adc                # (no args) print state
```

## Verified (all in `../../tests/sim_adc.sh`)

With `cl_adc` compiled in, and only forcing `P3.0=0` for the fixed-baud path (a
serial-line condition, not an ADC one):

- **Free-run reaches the main loop `0x074D`** from `reset; run` with **no**
  hand-injected ADC/INT1 stimulus.
- The **axis-servo ISR (`0x00C0`) fires** on its own from a natural EOC→INT1.
- A **seeded feedback value flows through** the servo ISR's `MOVX A,@DPTR` read
  (`set hardware adc <ch> 0x5A` → ACC = `0x5A` right after `0x00D8`).

Run it (opt-in; needs the custom `ucsim_51`):

```bash
cd simulator
make sim-adc UCSIM_51=~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51
```

or drive it directly:

```bash
cp ../firmware/hex/M2764A@DIP28.HEX build/rob3.hex
printf 'reset\nset mem sfr 0xb0 0x00\nbreak 0x074d\nrun 3000000\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M build/rob3.hex   # -> Stop at 0x00074d
```

## Limitation

The **closed-loop integrator** (`set hardware adc 1`) uses an `[INFER]` L293
bit-to-direction map and a coarse ±1 step — enough to demonstrate the loop
closing, **not** to certify servo dynamics. A faithful arm needs the servo
accel/decel algorithm reverse-engineered first (see `../../harness/README.md`).
Open-loop feedback (seeding channels) and the EOC→INT1 trigger — the parts that
unblock free-run — are solid.
