# ROB3 ROS 2 driver

A ROS 2 driver for the **Eurobtec ROB 3** 6-axis robot, talking to the robot's
Intel 8031 controller over its **RS-232** serial link — structured after the
Universal Robots ROS 2 driver (a serial protocol client + a hardware/driver node
+ URDF/launch/config), but in **Python**.

The wire protocol is the ROB3 low-level protocol, reverse-engineered and
verified against the ROM/simulator (see `../hardware/host/command.md` and
`../firmware/src/annotated/rs232.asm`). The driver speaks the
same bytes to either **real hardware** (`/dev/ttyUSB0`) or the **ucSim
simulator** (via its `-S` UART socket), so it can be developed without the robot.

## Layout

```
ros2/rob3_driver/
├── package.xml
├── setup.py / setup.cfg
├── resource/rob3_driver
├── rob3_driver/
│   ├── protocol.py           # pure ROB3 wire-protocol codec (no ROS deps)
│   ├── transport.py          # serial + TCP-socket transports (real HW / ucSim -S)
│   ├── calibration.py        # joint <-> 0..255 count mapping (per-axis)
│   ├── rob3_interface.py     # protocol + transport = high-level robot client
│   └── rob3_driver_node.py   # ROS 2 node: JointState, trajectory action, services
├── launch/rob3.launch.py
├── config/rob3_controllers.yaml
├── urdf/rob3.urdf.xacro
└── test/                     # pytest unit tests (protocol codec, calibration)
```

## Concept (UR-driver parallel)

| Universal Robots ROS 2 driver | ROB3 ROS 2 driver |
| :---------------------------- | :---------------- |
| Ethernet to the UR control box (RTDE / URScript) | RS-232 to the 8031 controller (ROB3 low-level protocol) |
| `ur_robot_driver` hardware interface | `rob3_interface` client + `rob3_driver_node` |
| Dashboard services (power on/off, e-stop) | services: `enable_motors`, `disable_motors`, `estop`, `read_serial_number` |
| `scaled_joint_trajectory_controller` | `FollowJointTrajectory` action → per-axis position commands |
| `/joint_states` from RTDE | `/joint_states` polled via the all-axis query (`0x4F`) |

## Quickstart (against the simulator)

```bash
# 1) build a ucSim with a serial socket and load the ROB3 ROM (see simulator/)
ucsim_51 -t 51 -X 11.0592M -S port=54321 simulator/build/rob3.hex

# 2) run the driver pointed at that socket
ros2 launch rob3_driver rob3.launch.py transport:=tcp host:=127.0.0.1 port:=54321

# real hardware instead:
ros2 launch rob3_driver rob3.launch.py transport:=serial device:=/dev/ttyUSB0
```

See `rob3_driver/protocol.py` for the exact wire encoding; every command there
is annotated with its ROM provenance.

## Status / scope

- Protocol codec + transports + driver node + URDF/launch/config: implemented.
- Position control (single + all-axis) and readback: implemented per the
  verified protocol.
- Speed/time-factor moves (`0x70`–`0x7F`) and the stored-program upload are
  wired in the codec but the trajectory controller uses simple position
  setpoints by default.
- Joint↔count calibration uses the per-axis bench values from
  `../hardware/motors/` where available; unmeasured axes use a linear placeholder
  clearly marked in `calibration.py`.
