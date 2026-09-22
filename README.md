# ROB3 Firmware Reverse-Engineering

Reverse-engineering and documenting the onboard firmware of the **ROB3**, a
6-axis industrial robot whose controller is built around an **Intel 8031**
(MCS-51) running from an 8 KB **M2764A** EPROM. The goal is to recover and
faithfully document the *original* firmware behavior — verified against the ROM,
a simulator, and the hardware — rather than to redesign the system.

The original controller is a ROM-less 8031 plus an 8255 PPI, a 74LS138 address
decoder, an ADC0808/0809, and L293 H-bridges driving six DC-servo axes with
potentiometric position feedback.

## Status

What exists in this repository today:

- **Annotated disassembly** of the initialization sequence (`0x0600–0x074C`) and
  the teach-pendant keypad scanner (`0x0C00–`), byte-verified against the ROM.
- **Two-layer verification** — a *golden byte-match* (assembled transcription
  `cmp`'d against the ROM) plus *behavioral ucSim tests* (the real ROM run in
  `s51` with runtime state asserted). Driven by `simulator/Makefile` (`make test`).
- **Hardware reference docs** for every board IC, plus a compiled **ucSim
  teach-pendant peripheral** (`cl_hw` module) for closer-to-real simulation.
- **Arduino bench bring-up rigs** that recreate the teachbox and a single robot
  axis to confirm hardware claims independently of the 8031.
- **Domain skills & steering** under `.kiro/` capturing the MCS-51 / ucSim /
  Arduino know-how and ROB3-specific maps.

> **C conversion is not started.** The original project charter
> ([`ROB3_FIRMWARE_REENGINEERING.md`](ROB3_FIRMWARE_REENGINEERING.md)) targets a
> C rewrite with SDCC; the current reality is annotated assembly + verification
> + documentation. The `mcs51-c-programming` skill and the charter capture the
> intended approach for when that work begins.

## Repository layout

```
rob3/
├── README.md                         # this file
├── ROB3_FIRMWARE_REENGINEERING.md    # project charter: goals, scope, success criteria
├── LICENSE
├── firmware/                         # the firmware itself (ROM + disassembly + annotations)
│   ├── bin/ hex/                      #   ROM image (binary + Intel HEX)
│   ├── src/                           #   raw disasm (main.asm) + annotated/ (assembling 1:1 source: *.asm + inc/*.inc)
│   ├── INSTALL.md                     #   toolchain prerequisites
├── simulator/                        # build / verify / simulate rig (drives ../firmware)
│   ├── Makefile                       #   verify / sim-* / gen targets
│   ├── BUILD.md                       #   build/test guide
│   ├── *.a51                           #   byte-exact ROM-region sources (golden DUT)
│   ├── tests/                          #   ucSim behavioral tests
│   ├── harness/                        #   Python batch driver + closed-loop foundation
│   ├── ucsim-modules/                  #   compiled cl_hw peripherals (teachbox/, adc/)
├── hardware/                         # board reverse-engineering
│   ├── board/                         #   per-chip docs (8031, 8255, 74LS138, EPROM, SRAM, ADC, L293, ...)
│   ├── teachbox/  motors/  connectors/#   subsystem docs + Arduino bring-up sketches
├── docs/                             # derived analysis
│   ├── reverse_engineering_notes.md   #   firmware map, ISRs, protocol, function table
│   ├── 8031_sfr_map.md  8255_mapping.md
│   └── axis_state_machine.md
├── sessions/                         # dated work logs
└── .kiro/                            # skills + steering (domain knowledge for agents)
```

## Quickstart

Install the toolchain (SDCC `sdas8051`/`sdld`, ucSim `s51`, binutils, make,
python3) — see [`firmware/INSTALL.md`](firmware/INSTALL.md) for per-OS steps.

```bash
cd simulator
make          # golden byte-match: assembled transcription == ROM slice (prints SHA-256)
make test     # golden byte-match + ucSim behavioral tests
make help     # list all targets (verify / sim-init / sim-run / sim-teachbox / gen)
```

> **ucSim `@`-filename gotcha:** the shipped ROM is `hex/M2764A@DIP28.HEX`, and
> the `@` crashes `s51` (it parses `file@memoryspace`). The Makefile copies the
> image to a shell-safe `simulator/build/rob3.hex` automatically — you never
> need to rename anything by hand.

## Hardware at a glance

| Part | Role |
| :--- | :--- |
| Intel **8031** | ROM-less MCS-51 CPU; boots the external EPROM via `PSEN` |
| **M2764A** EPROM (8 KB) | program store (`0x0000–0x1FFF`) |
| **HM6264** SRAM (8 KB) | data workspace / stack / robot-program storage |
| **8255** PPI | parallel I/O: motor direction/enable (Ports A/C) + digital I/O (Port B) |
| **74LS138** | address decoder → device selects (`DPH` picks the MOVX window) |
| **74HC373** | address latch (AD0–7 off the multiplexed P0 bus) |
| **ADC0808/0809** | 8-ch ADC reading the axis feedback pots; EOC → INT1 |
| **L293** ×3 | H-bridges driving six DC-servo motors |

### Axis / joint reference

| Axis | Joint | Symbol | Range | Resolution |
| :--- | :---- | :----- | :---- | :--------- |
| 0 | Base rotation | q1 | +80° … −80° | 0–255 |
| 1 | Shoulder | q2 | +70° … −30° | 0–255 |
| 2 | Elbow | q3 | 0° … −100° | 0–255 |
| 3 | Wrist pitch | q4 | +100° … −100° | 0–255 |
| 4 | Wrist roll | q5 | +100° … −100° | 0–255 |
| 5 | Gripper | — | 0–60 mm | 0–255 |

Positions are 8-bit. The firmware numbers axes from 0; original robot
documentation numbers them from 1.

## How claims are verified (provenance)

Every firmware statement in the docs and annotations is tagged with how it was
established, and unproven claims are kept separate from verified ones:

- **[BYTE]** — verified from the ROM bytes (byte-exact / golden match)
- **[SIM]** — verified by running the ROM in ucSim and observing state
- **[HW]** — confirmed against a hardware doc or an Arduino bench bring-up
- **[INFER]** — hypothesis, not yet proven (never stated as fact)

## Documentation & skills

- **Charter / full spec:** [`ROB3_FIRMWARE_REENGINEERING.md`](ROB3_FIRMWARE_REENGINEERING.md)
- **Firmware build & tests:** [`simulator/BUILD.md`](simulator/BUILD.md), [`firmware/INSTALL.md`](firmware/INSTALL.md)
- **Analysis docs:** [`docs/`](docs/) — RE notes, SFR/8255 maps, axis state machine
- **Hardware docs:** [`hardware/`](hardware/) — per-chip board reference, teachbox, motors, connectors
- **Agent skills:** [`.kiro/skills/`](.kiro/skills/) — generic (`mcs51-assembly`,
  `mcs51-c-programming`, `mcs51-debugging`, `ucsim`, `arduino-hardware-bringup`)
  and ROB3-specific (`rob3-hardware`, `rob3-firmware-map`, `rob3-firmware-sim`,
  `rob3-arduino-bringup`)

## License

See [`LICENSE`](LICENSE).
