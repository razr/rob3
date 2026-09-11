---
name: rob3-hardware
description: >
  ROB3 controller board hardware reference for firmware work: the Intel 8031 CPU,
  8255 PPI, 74LS138 address decoder, 74HC373 address latch, M2764A EPROM,
  HM6264 SRAM, ADC0808/0809, L293 H-bridges, and the derived external memory map
  (DPH device windows). Use when writing, annotating, or debugging 8031 firmware
  and you need to know which chip/register an address touches.
metadata:
  origin: ROB3
  globs: ["hardware/**", "firmware/**", "docs/**"]
---

# ROB3 Board Hardware (for firmware/RE)

> Authoritative per-chip docs live in `hardware/board/*.md`; the derived software
> views are in `docs/8031_sfr_map.md` and `docs/8255_mapping.md`. This skill is
> the fast index that connects an address in the code to a physical device.
> Pair it with the generic MCS-51 skills (`mcs51-assembly`,
> `mcs51-c-programming`, `mcs51-debugging`, `ucsim`) and with `rob3-firmware-sim`
> for the ROB3 build/verify/simulate workflow.

## System architecture in one paragraph

An **Intel 8031** (no internal ROM) boots from an external **M2764A 8 KB EPROM**
via `PSEN`, uses an **HM6264 8 KB SRAM** as data workspace, and talks to
peripherals through an **8255 PPI** and an **ADC0808/0809**. `P0` is the
multiplexed low-address/data bus, latched by a **74HC373** on `ALE`; `P2`
carries the high address. A **74LS138** decodes the high address into chip
selects. The firmware is therefore a program of *address writes and decode
events* — the target is the memory map, not the raw opcodes.

```text
8031 ── P0 (AD0-7) ──┬── 74HC373 latch ── A0-A7 ─┐
      ── P2 (A8-15) ─┴───────────────────────────┼─► EPROM / SRAM / 8255 / ADC
      ── ALE ─► latch    PSEN ─► EPROM read       │
      ── RD/WR ─► data cycles   74LS138 ─► chip selects (from A11/A12, A14/A15 gate)
```

## The external memory map (what `DPH` selects)

Firmware selects a device by writing the **high address byte `DPH` (SFR 0x83)**
before `MOVX @DPTR`. The 74LS138 decodes B=A11, C=A12 for the region; A14/A15
gate peripheral space (A14=1,A15=0) vs SRAM (A15=1,A14=0). Resulting windows:

| `DPH`         | XDATA addr   | Device / register                              |
| :------------ | :----------- | :--------------------------------------------- |
| `0x48`        | `0x4800`     | Axis-select latch (write; picks feedback axis) |
| `0x50`        | `0x5000`     | **8255 Port A** — DC-motor dir/enable (axes 0-3), shadow IRAM `0x4E` |
| `0x51`        | `0x5100`     | **8255 Port B** — digital out / teach-pendant, shadow IRAM `0x1F` |
| `0x52`        | `0x5200`     | **8255 Port C** — DC-motor dir/enable (axes 4-5), shadow IRAM `0x4F` |
| `0x53`        | `0x5300`     | **8255 Control** word (write-only)             |
| `0x58`        | `0x5800`     | **ADC** channel-select/START latch (write); bit0=A8=ADD-A channel step |
| `0x59`        | `0x5900`     | **ADC** converted-data read (`0x58` vs `0x59` differ only in A8) |
| `≥ 0x80` (A15)| SRAM window  | HM6264 external RAM workspace/stack            |

> The four 8255 registers are resolved by the **8255's own A0/A1** within the
> selected block, which is why `DPH` `0x50–0x53` cleanly map to A/B/C/Control.
> `DPL` is don't-care for peripheral selection.

## Per-chip quick reference

### Intel 8031 (CPU, 40-pin)
- 8-bit core, 4 banks R0–R7 in IRAM `0x00–0x1F`, 256 B IRAM, 16-bit DPTR.
- Key pins: `P0`=AD0-7, `P2`=A8-15, `ALE`(30), `PSEN`(29), `WR`(16)/`RD`(17),
  `EA`(31, external fetch), `INT0`(12)/`INT1`(13), `T0`(14)/`T1`(15),
  `RXD`(10)/`TXD`(11), `XTAL` 11.0592 MHz.
- **INT1 (pin 13) = ADC end-of-conversion** → axis-feedback ISR.
- Vectors: reset `0x0000`(→`LJMP 0x0600` init), INT0 `0x0003`, T0 `0x000B`,
  INT1 `0x0013`, T1 `0x001B`, serial `0x0023` (falls through to `LJMP 0x0300`).

### 8255 PPI (parallel I/O gateway)
- Three 8-bit ports (A, B, C) + control register.
- ROM init writes Control = `0x80` → Mode 0, **all ports output**.
- Port A/C drive **L293 H-bridges** (DC-motor direction/enable); Port B is
  digital out / teach-pendant / LEDs.
- Access via `DPH=0x50..0x53` + `MOVX` (see map above). Shadows in IRAM
  (`0x4E` PortA, `0x4F` PortC, `0x1F` PortB) mirror hardware state.

### 74LS138 (3-to-8 address decoder)
- Generates active-LOW chip selects. On this board **B=A11, C=A12** are the real
  CPU selects; **input A is tied to its own Y4 output** (self-latch, not a CPU
  line). A14/A15 gate peripheral vs SRAM space.
- Y-region → device: Y2/Y3 = aux/axis-select (`0x48`); Y4/Y5 = 8255
  (`0x50–0x53`); Y6/Y7 = ADC (`0x58/0x59`).
- This chip *defines the memory map* — for any `DPH`, it says which device
  responds.

### 74HC373 (octal transparent latch)
- Latches the low address byte (A0–A7) off the multiplexed `P0` bus on `ALE`,
  so the 8031 can drive address then data on the same pins. Uses the classic
  interleaved 373 pinout (functionally == 74HC573). Transparent when LE high,
  latched when LE low.

### M2764A EPROM (8 KB program store)
- Holds the firmware image; fetched via `PSEN`. Selected by the decode/latch
  path, shares the bus with SRAM but on a different control cycle.
- This is the byte source for the golden tests (`firmware/bin`, `firmware/hex`).

### HM6264 SRAM (8 KB data workspace)
- Volatile runtime RAM: stack, working vars, telemetry, state mirrors. Selected
  by the data-memory cycle (A15 window). Pin 1 (NC on 6264) is wired to A14 for
  JEDEC 62256 upgrade compatibility — harmless on the 6264.

### ADC0808/0809 (8-ch, 8-bit ADC)
- Identified from ringed-out nets + firmware (markings scratched off); ratiometric
  (`VREF+`=+5V) → likely 0809.
- Reads 6 potentiometers (joint position feedback). **EOC → INT1** signals
  data-ready. Firmware: write channel to `DPH=0x58` (latches ADD-A + pulses
  START/`WR`), read result from `DPH=0x59` (`OUTPUT ENABLE`/`RD`). Channel index
  masked `anl A,#07h` (8-channel part); only ADD-A is CPU-driven (ADD-B/C
  strapped). Telemetry stored in IRAM `0x50–0x55` (6 pots).

### L293 H-bridges (motor drivers)
- Dual H-bridge; three populated (#1/#2 on Port A, #3 on Port C); a 4th is
  not-populated. Drive **DC servo motors** (not steppers). Direction/brake truth
  table (per motor pair): `(A7,A6)` = `00`/`11` brake, `01` forward, `10`
  reverse. Enable pins tied to +5V.

### Support logic
- **MM74C04N / 74HC14**: inverters/Schmitt buffers on address/control lines.
- **74LS244**: buffers Port B outputs to the external DB25 connector.
- **M34004, MAX1044, L7805, 1N5400**: analog/clock/power support (not firmware-
  visible).

## Firmware ↔ hardware landmarks (verified)

- Reset `0x0000` → `LJMP 0x0600` init; init blocks at `0x0680` on the ADC/INT1
  gate; completes at `0x074B` into the main loop `0x074D`.
- Init SFR state: `SP=0x31`, `TMOD=0x21`, `SCON=0x50` (Mode1, REN),
  `IE=0x84`(EA+EX1) at the gate → `0x07`/`0x17` later.
- 8255 setup at `~0x0615`: Control `0x80`, Port A/C `0x00`, Port B `0xFF`.
- ADC channel step at `jump_0278`; telemetry block IRAM `0x50–0x55`.
- Keypad scanner entry `0x0C00`, key handler `0x0C80` (both preceded by 0xFF
  padding — confirm from bytes, not labels).

## Open / tentative items (don't state as fact)

- Exact Port A/C bit → axis mapping for the six motors (tentative).
- Port B bit split between teach-pendant LEDs and buffered DB25 outputs.
- 74LS138 enable-side gating (G1/G2A/G2B) only partially ringed out; the
  A11/A12 select decode is confirmed, the A14/A15 gate expression is not fully.

## When to use this skill

- Deciding which chip/register a `DPH`/`MOVX` or address touches.
- Annotating firmware that drives motors (8255/L293) or reads sensors (ADC).
- Building a peripheral model for the simulator (needs the decode + pin behavior).
- Any RE work that must map code to physical robot action.
