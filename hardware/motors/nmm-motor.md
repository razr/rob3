# NMM (Nihon Mini Motor) gearmotor with integrated pot feedback

A miniature **Nihon Mini Motor Co., Ltd. (NMM)** DC gearmotor assembly that
integrates a micro DC motor, a step-down gearbox, and an absolute
potentiometric feedback wafer in one modular unit — i.e. a self-contained
closed-loop micro-servo. Units like this were originally made for optical
mechanisms (autofocus / zoom / iris) in vintage cameras (e.g. Minolta) and LCD
projectors, and appear here as a surplus electro-mechanical assembly.

> **Provenance:** the physical description below is from inspection of the part
> [HW]. On ROB3 the NMM units drive the three distal joints — **axes 4, 5 and
> the gripper** (firmware axes 3, 4, 5); the three proximal joints (axes 1–3)
> use Bühler motors. See [`README.md`](README.md).

## Assembly

| Part | Description |
| :--- | :---------- |
| **DC brushed motor** | Small silver metal canister; a low-power coreless / micro-brushed DC motor. Typically runs ~**3–6 V DC**. |
| **Integrated gearbox** | Under the (red) frame layer; steps the high motor RPM down to high output torque relative to its tiny footprint. |
| **Feedback potentiometer** | The brown phenolic PCB substrate is a trace-printed pot wafer. The final reduction gear rotates a wiper along the printed track, giving integrated position feedback (absolute over the wiper's travel). |
| **Output drive pulley** | Silver-toothed shaft protruding from the black base; the mechanical output, meant to mesh with a miniature timing belt or gear train. |

## Pinout — 5 wires, two isolated groups

```
        Motor canister (back-cap solder pads)      Pot wafer (brown PCB, 3 joints)
        +------------------------------+           +---------------------------+
        |   M+        M-               |           |  1        2        3       |
        +---|---------|----------------+           +--|--------|--------|-------+
            |         |                               |        |        |
         motor     motor                            Vref+    WIPER    Vref-
         drive     drive                            (VCC)   (analog)  (GND)
        (polarity = direction)                              out
```

### Motor drive (2 wires)
- Land on the solder pads of the motor canister's back-cap.
- **Reversing the voltage polarity reverses the spin direction** — the two
  inputs an H-bridge (L293 on ROB3) would drive.

### Potentiometer feedback (3 wires)
- Land on the three joints of the brown pot PCB.
- **Outer pin 1 / outer pin 3:** reference rails (e.g. **VCC/5 V** and **GND**).
  Which outer pin is VCC vs GND sets the direction the wiper voltage rises.
- **Center pin 2 (wiper):** analog output whose voltage tracks the output-pulley
  angle, for an MCU/ADC to read absolute position.

## How it maps to the ROB3 drive/feedback path

This part is functionally the same servo topology the ROB3 controller expects,
just in a miniature integrated package:

- **Drive:** the 2 motor wires are an H-bridge load → an **L293** channel
  (8255 Port A/C direction bits). See [`../board/L293.md`](../board/L293.md) and
  [`../board/8255.md`](../board/8255.md). Enable is tied to VCC on ROB3; speed
  is by firmware pulse timing, not hardware PWM.
- **Feedback:** the wiper (pin 2) is an analog absolute-position signal → the
  **ADC0808/0809**; its end-of-conversion drives the 8031 INT1 servo ISR. See
  [`../board/adc.md`](../board/adc.md) and
  [`../../docs/axis_state_machine.md`](../../docs/axis_state_machine.md).

This is the same wiper-to-ADC scheme documented for the
[`VP12 5 kΩ potentiometer`](VP12-5kΩ-potentiometer.md); calibrate each NMM
axis's wiper range (axes 4/5/gripper) to the ROB3 8-bit scale the same way (see
[`test.md`](test.md)).

## Open items [INFER]

- Exact part/model number and the pot's resistance/taper (VP12 is a separate
  5 kΩ part; the NMM's integrated wafer value is not yet measured).
- The exact connector pins for axes 4/5/gripper (motor pair + wiper).
- Motor voltage/current draw under load vs. the ROB3 6 V Bühler motors.

## References

- Nihon Mini Motor Co., Ltd. — miniature DC gearmotors (manufacturer background).
- ROB3 feedback chain: [`../board/adc.md`](../board/adc.md),
  [`../board/8031.md`](../board/8031.md).
