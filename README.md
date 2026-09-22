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

- **Assembling 1:1 annotated disassembly** — the entire 8 KB ROM reassembled
  from 10 annotated `.asm` region files + 7 `inc/*.inc` equate files, with
  output **byte-identical** to the original EPROM
  (SHA-256 `1e94419d…`). Every instruction carries the raw bytes and a
  provenance tag; `system.inc` is the authoritative IRAM/flag-bit map.
- **Two-layer verification** — a *golden byte-match* (`make verify`: whole-image
  `cmp` against the ROM) plus *behavioral ucSim tests* (the real ROM run in
  `s51` with runtime state asserted). Driven by `simulator/Makefile`
  (`make test`). All 10 regions pass standalone (`make status`).
- **Reverse-engineered host serial protocol** — the RS-232 binary command set
  confirmed against the ROM (hidden digital-input-read commands found), the
  startup handshake (0x15/0xF1 reply semantics), and the stored-program
  interpreter + a "hello world" program, all `[SIM]`-verified.
- **Python ROS 2 driver** (`ros2/rob3_driver/`) — UR-driver-style package with
  a ROS-independent protocol codec, serial+TCP transports, calibration, and a
  driver node (JointState / FollowJointTrajectory / Trigger services). 25
  pytest tests pass; driver bytes verified against the ROM dispatch in ucSim.
- **Hardware reference docs** for every board IC, plus compiled **ucSim
  peripheral modules** (`cl_hw`: teachbox, adc, loopback, rxd) for
  closer-to-real simulation — including a pin-level auto-baud driver.
- **Arduino bench bring-up rigs** that recreate the teachbox and a single robot
  axis to confirm hardware claims independently of the 8031.
- **Domain skills & steering** under `.kiro/` capturing the MCS-51 / ucSim /
  Arduino know-how and ROB3-specific maps.

> **C conversion is not started.** The original project charter
> ([`ROB3_FIRMWARE_REENGINEERING.md`](ROB3_FIRMWARE_REENGINEERING.md)) targets a
> C rewrite with SDCC; the current reality is annotated assembly + verification
> + documentation. The `mcs51-c-programming` skill and the charter capture the
> intended approach for when that work begins.

## Progress

Chronological milestones. Each links to the dated session log with full detail,
corrections, and provenance. Read the table for the overview; read a session log
only when you need the specifics.

| Date | Milestone | Detail |
| :--- | :-------- | :----- |
| 2026-07-14 | **Initial firmware analysis** — 5 subsystems, IRAM map, axis limits, IC complement identified from `main.asm` | [log](sessions/2026-07-14_firmware_analysis.md) |
| 2026-09-03 | **Init sequence annotated** + byte-verified (assemble-and-diff, 140 bytes, 0 mismatches); vector table corrected; serial ISR located at 0x0300 | [log](sessions/2026-09-03_annotate_init_sequence.md) |
| 2026-09-11 | **Hardware docs fixed** (74HC373, ADC0808, 74LS138 decode), **Arduino bring-ups** (teachbox + motors), **teachbox annotation** (kbd_scan/axis-select/jog), first **ucSim cl_hw module** (teachbox) | [log](sessions/2026-09-11_hardware_docs_arduino_teachbox_ucsim.md) |
| 2026-09-12 | **POS-digit direct entry** verified (decimal accumulate → axis slot); **simulator restructured** to top-level `simulator/`; **cl_adc** (EOC→INT1 free-run); **plant/bridge architecture** settled; **Teachbox GUI + CLI** | [log](sessions/2026-09-12_simulator_restructure_adc_plant_gui.md), [log](sessions/2026-09-12_teachbox_pos_digit_entry.md) |
| 2026-09-13 | **CLI UX**: configurable ROM, readline history, **ucSim console socket** (`-z <port>` + `nc` attach) | [log](sessions/2026-09-13_teachbox_cli_ux_console_socket.md) |
| 2026-09-14 | **Teachbox sim unblocked**: `run N`→`step N` (20 s→30 ms); **EMERGENCY-OFF** (P3.2) + **P3.4 poll gate** diagnosed; **loopback cl_hw module**; **keypad debounce** (release-then-hold); **ucSim bugs** filed (#001 pipelined-cmd, #002 @-filename segfault — submitted+closed upstream) | [log](sessions/2026-09-14_teachbox_sim_gates_loopback_ucsim_bug.md), [log](sessions/2026-09-14_ucsim_issue_002_at_filename_issues_relocate.md) |
| 2026-09-14 | **ucSim plugin SDK** made installable (`make install`); ROB3 modules converted to **loadable `.so` plugins** (`loadhw`) | [log](sessions/2026-09-14_ucsim_plugin_sdk_install_rob3_loadable_modules.md) |
| 2026-09-14 | **EXT1 axis servo** annotated; axis limits/calibration investigated (no per-axis clamp in ROM) | [log](sessions/2026-09-14_ext1_axis_limits_calibration_analysis.md) |
| 2026-09-16 | **Symbolic equates** (`rob3.inc`) applied to annotated files; EXT1 extracted to own file; **RS-232 shorting connector** traced (pin-4 pull-up hypothesis) | [log](sessions/2026-09-16_annotated_asm_symbolic_equates_header.md), [log](sessions/2026-09-16_ext1_axis_servo_extract_annotate_calibration.md), [log](sessions/2026-09-16_rs232_shorting_connector_trace_loopback_docs.md) |
| 2026-09-20 | **RS-232 UART annotated** + protocol `[SIM]`-proven; **rxd cl_hw pin-driver** built (auto-baud end-to-end); fixed-baud path has no serial (ES never set); 115200 out of auto-baud range | [log](sessions/2026-09-20_rs232_annotation_protocol_sim_rxd_driver.md) |
| 2026-09-20 | **Full command set confirmed** vs ROM; **hidden commands** found (digital-input read 0x50–0x57); 0xFx replies are ACK/status not errors; **stored-program interpreter** annotated + **"hello world" program** runs | [log](sessions/2026-09-20_command_set_hidden_cmds_program_interpreter_hello_world.md) |
| 2026-09-20 | **Python ROS 2 driver** (UR-style): protocol codec, serial+TCP transports, calibration, driver node, URDF; 25 pytest tests; driver bytes verified against ROM in ucSim | [log](sessions/2026-09-20_ros2_driver_rs232.md) |
| 2026-09-22 | **Annotated source tree redesigned**: 10 region `.asm` + 7 `inc/*.inc` + `rob3.asm` top unit; old `.a51`/`gen_init.py` removed; **whole 8 KB image assembles 1:1** with the ROM (disasm51 + `d51_to_sdas.py` converter) | [log](sessions/2026-09-22_annotated_dir_redesign_assembling_1to1.md) |
| 2026-09-22 | **All 10 regions annotated** — section banners, symbolic operands, MOVC data tables marked, 0xFF padding collapsed; all regions pass standalone verify | [log](sessions/2026-09-22_annotate_all_regions_per_instruction.md) |

## Repository layout

```
rob3/
├── README.md                         # this file
├── ROB3_FIRMWARE_REENGINEERING.md    # project charter: goals, scope, success criteria
├── LICENSE
├── firmware/                         # the firmware itself (ROM + disassembly + annotations)
│   ├── bin/ hex/                      #   ROM image (binary + Intel HEX)
│   ├── src/                           #   raw disasm (main.asm) + annotated/ (assembling 1:1: rob3.asm + *.asm + inc/*.inc + Makefile)
│   ├── INSTALL.md                     #   toolchain prerequisites
├── simulator/                        # behavioral-test rig (drives ../firmware)
│   ├── Makefile                       #   sim-* targets; verify delegates to firmware/src/annotated
│   ├── BUILD.md                       #   build/test guide
│   ├── tests/                          #   ucSim behavioral tests
│   ├── harness/                        #   Python batch driver + Teachbox GUI/CLI + plant
│   ├── ucsim-modules/                  #   compiled cl_hw peripherals (teachbox/ adc/ loopback/ rxd/)
├── ros2/rob3_driver/                 # Python ROS 2 driver (UR-style, RS-232)
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
