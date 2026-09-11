# Motors

Motor and position-feedback hardware for the ROB3i arm. The arm has **6 axes**
(5 revolute joints + gripper), each a **DC servo motor** with **absolute
potentiometric** position feedback.

## Components

| File | Component | Notes |
| :--- | :-------- | :---- |
| [`bueler-motor.md`](bueler-motor.md) | Bühler 6 VDC motor (P/N 31.042.303-1) | Drives axes 1–3 (base/shoulder/elbow). Per-motor noise-suppression (1N4007 diode, cap, GE varistor); 8255 → L293 drive mapping |
| [`VP12-5kΩ-potentiometer.md`](VP12-5kΩ-potentiometer.md) | 5 kΩ VP12 precision feedback potentiometer | Wiper → ADC (see `../board/adc.md`) |
| [`nmm-motor.md`](nmm-motor.md) | NMM (Nihon Mini Motor) gearmotor + integrated pot | Drives axes 4–5 + gripper (wrist pitch/roll/gripper). Miniature closed-loop micro-servo; same H-bridge/wiper→ADC topology |
| [`test.md`](test.md) | Arduino bring-up tests | Per-axis potentiometer calibration tables + motor drive sketches |

## Motor-per-axis assignment

The arm uses **two different motor types**, split by axis: the three larger
proximal joints use **Bühler** motors, and the three smaller distal
joints/gripper use miniature **NMM** gearmotors. Both types are DC servos with
analog potentiometric feedback, driven identically (L293 H-bridge + wiper→ADC).

| Axis (1-based) | Axis (firmware, 0-based) | Joint | Motor |
| :------------: | :----------------------: | :---- | :---- |
| 1 | 0 | Base rotation | **Bühler** 6 VDC |
| 2 | 1 | Shoulder | **Bühler** 6 VDC |
| 3 | 2 | Elbow | **Bühler** 6 VDC |
| 4 | 3 | Wrist pitch | **NMM** gearmotor |
| 5 | 4 | Wrist roll | **NMM** gearmotor |
| — | 5 | Gripper | **NMM** gearmotor |

> Axis numbering: original robot documentation is **1-based**; the firmware is
> **0-based** (see `../../docs/axis_state_machine.md`). The gripper is axis 5 in
> firmware terms.

## Drive & feedback overview

- **Drive:** 3 populated **L293** dual H-bridges (6 motors). 8255 **Port A**
  drives L293 #1/#2 direction inputs; **Port C** drives L293 #3; the L293 enable
  pins are tied to **VCC** (speed is done in firmware by pulse timing, not
  hardware PWM). A 4th L293 footprint exists on the PCB but is **unpopulated**.
  Pin-level wiring: see [`../board/L293.md`](../board/L293.md) and
  [`../board/8255.md`](../board/8255.md).
- **Feedback:** each axis potentiometer wiper feeds the **ADC0808/0809**
  (analog, absolute position). Channel mapping: see
  [`../board/adc.md`](../board/adc.md). The ADC end-of-conversion drives the
  8031 INT1 servo ISR (see [`../board/8031.md`](../board/8031.md)).

## Cross-references

- Firmware view of the 6-axis servo loop: `../../docs/axis_state_machine.md`
- Manual specs (DC servo, potentiometric transducers, ranges):
  `../teachbox/README.md`
