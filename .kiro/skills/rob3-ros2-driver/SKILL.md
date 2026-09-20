---
name: rob3-ros2-driver
description: >
  ROB3-specific ROS 2 driver (Python) that speaks the reverse-engineered ROB3
  low-level protocol to the 8031 controller over RS-232, structured like the
  Universal Robots ROS 2 driver: a ROS-independent protocol codec + transport +
  calibration core, a Rob3Client, and a driver node (JointState / trajectory
  action / dashboard services), plus URDF/launch/config. Covers the package
  layout, the codec<->command.md mapping, the serial-vs-ucSim-socket transports,
  the joint<->count calibration, and how to test the driver bytes against the
  real ROM in ucSim. Use when building, running, or extending the ROB3 ROS 2
  driver.
metadata:
  origin: ROB3
  globs: ["ros2/rob3_driver/**"]
---

# ROB3 ROS 2 driver (RS-232)

> Package: `ros2/rob3_driver/` (ament_python). Talks the ROB3 low-level protocol
> — reverse-engineered and [SIM]-verified in `hardware/host/command.md` and
> `firmware/src/annotated/rs232_serial.annotated.asm` — over RS-232 to the 8031,
> or over ucSim's `-S` UART socket for development. Modelled on the UR ROS 2
> driver but in Python. For the protocol itself see the `rob3-firmware-map` /
> `rob3-firmware-sim` skills.

## Layered structure (ROS-independent core first)

| File | Role | ROS deps? |
| :--- | :--- | :-------- |
| `rob3_driver/protocol.py` | pure wire-protocol **codec** (encode commands, parse replies, classify 0xFx status) | no |
| `rob3_driver/transport.py` | `SerialTransport` (pyserial) + `TcpTransport` (ucSim `-S`), one tiny interface | no |
| `rob3_driver/calibration.py` | per-axis joint(rad/m) ↔ 0..255 count mapping, with clamping | no |
| `rob3_driver/rob3_interface.py` | `Rob3Client` = codec + transport (connect/handshake/move/query/control) | no |
| `rob3_driver/rob3_driver_node.py` | ROS 2 node: `/joint_states`, `FollowJointTrajectory` action, `Trigger` services | yes (rclpy, control_msgs, sensor_msgs, std_srvs) |
| `urdf/rob3.urdf.xacro`, `launch/rob3.launch.py`, `config/` | description + bringup | launch/xacro |

Keep new protocol/transport logic in the ROS-independent layer so it stays
unit-testable without a ROS install.

## Codec ↔ command.md (the important mapping)

`protocol.py` encodes exactly the verified command set; frames are
`<header> [operands] 0x03(ETX)`:
- **startup** `0x20` (SPACE) — NOT framed; auto-baud training + reset handshake.
  Reply `0x15`=init-OK, `0xF1`=already-init.
- set position: single `0x00|axis (+0x08 ack)`, all `0x07`/`0x0F` + 6 bytes.
- position query: single `0x40|axis`, **all `0x4F`** (the doc's value; `0x47`
  also works since axis field 7 = all).
- position+speed: single `0x70|axis`, all `0x7F` + 6 targets + 6 time factors.
- control: `0x61` enable, `0x60` disable, `0x62` e-stop (hold pos), `0x63` serial#.
- **All `0xFx` replies are ACK/status, never errors** — `is_status_byte()`
  encodes the set; a byte outside it is a comms error.

## Transports: real HW and simulator

- `transport:=serial device:=/dev/ttyUSB0` — pyserial, 9600 8N1, no flow control
  (the firmware auto-bauds off the first `0x20`).
- `transport:=tcp host:=127.0.0.1 port:=54321` — ucSim `-S port=<n>` socket.
  Caveat: some ucSim builds wrap the socket in telnet/ANSI negotiation on
  connect, and the firmware needs the auto-baud lock + P3.2 driven HIGH first
  (the `rxd` + `adc`/emergency-off setup from `rob3-firmware-sim`) before it
  will answer over the wire. Prefer the ROM-dispatch integration check (below)
  for a deterministic byte-level proof.

## Calibration (verify before trusting)

`calibration.py` maps joints to the 8-bit count the firmware stores. Ranges are
[HW-doc] (base ±80°, shoulder +70/-30°, elbow 0/-100°, wrist pitch/roll ±100°,
gripper 0..60 mm); the **count-at-each-limit and direction are per-unit bench
placeholders** — substitute the measured `AXIS_CAL` from `hardware/motors/`.
The firmware has **no soft limits**, so the codec/driver clamp counts to the
axis window to avoid driving into a hard stop.

## Testing

- Unit (no ROS): `python3 -m pytest ros2/rob3_driver/test/` — codec + calibration
  (18 tests). Add cases here for any new command.
- Driver-vs-ROM: `ros2/rob3_driver/test/test_driver_protocol_vs_rom.sh` feeds the
  driver's encoded frame through the real ROM dispatch (`rx_dispatch` 0x03A9,
  A=ETX, header in R6, payload in 0x60..) in ucSim and asserts the firmware
  effect — the honest tie between the driver bytes and [SIM]-verified behaviour.
  Run with `SAFEHEX=simulator/build/rob3.hex SIM=<s51|ucsim_51>`.
- Node/launch need a ROS 2 env (Humble/Jazzy). `py_compile` is the syntax check
  available without ROS.

## UR-driver parallel (for orientation)

Ethernet→UR box becomes RS-232→8031; the UR hardware interface becomes
`Rob3Client` + node; dashboard services become enable/disable/estop/serial#; the
scaled joint-trajectory controller becomes the `FollowJointTrajectory` action
streaming per-axis position setpoints (the firmware servo closes the loop).

## Gotchas

- **ETX is mandatory** — every command frame ends `0x03` or the firmware drops
  it to the generic-ack path (`cjne A,#0x03` at 0x03AE).
- **bit7=0 = axis/position class, bit7=1 = system/program** (easy to invert).
- The node degrades gracefully if the transport can't open (keeps servers up,
  reconnects on demand) — do not assume a live robot at construction time.
