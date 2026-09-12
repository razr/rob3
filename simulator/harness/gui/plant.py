#!/usr/bin/env python3
"""ROB3 plant model — the physics that live OUTSIDE ucSim.

Per simulator/harness/ARCHITECTURE.md, ucSim models only the bus chips (ADC,
8255). The motor + joint + potentiometer dynamics are NOT on the 8031 bus, so
they live here, in the harness. The plant:

  * owns the true physical position of each axis (`pot`, 0..255, the wiper),
  * reads the motor command (direction/enable) the firmware wrote to the 8255
    Port A/C shadows,
  * integrates each axis toward the commanded direction, clamped to range,
  * exposes the pot readings the ADC serves back to the firmware.

DIRECTION MAP CAVEAT ([INFER]): the exact 8255 Port A/C bit -> (axis, dir, en)
mapping is not yet [SIM]-verified (it is entangled with the servo accel/decel
algorithm — see ARCHITECTURE.md "Direction-trace findings"). `decode_l293`
below is a documented, swappable placeholder. The plant's *plumbing* is real;
the direction correctness is provisional until that RE is done.

This module has NO ucSim dependency, so it can be unit-tested and reused behind
a socket bridge to ROS2 / Gazebo / Isaac.
"""
from __future__ import annotations
from dataclasses import dataclass, field


N_AXES = 6

# Per-axis travel is the full 8-bit range on this firmware (0..255). The joint
# angle mapping (README axis table) is a display concern, applied in the GUI.
POT_MIN = 0
POT_MAX = 255


@dataclass
class MotorCommand:
    """Decoded per-axis motor command for one servo cycle."""
    enable: bool = False
    direction: int = 0   # +1 = pot increases, -1 = pot decreases, 0 = hold


@dataclass
class Plant:
    """The physical arm: six pots pushed by six motors."""
    pot: list[int] = field(default_factory=lambda: [128] * N_AXES)
    # step size per servo tick (coarse; exact accel/decel is [INFER])
    step: int = 4

    def decode_l293(self, port_a: int, port_c: int) -> list[MotorCommand]:
        """Decode 8255 Port A (0x5000) / Port C (0x5200) into per-axis commands.

        [INFER] placeholder mapping (see module docstring): axes 0..3 use two
        bits each in Port A, axes 4..5 two bits each in Port C:
            bit(2*i)   = drive-up (pot increases)
            bit(2*i+1) = drive-down (pot decreases)
        Enable = either bit set; direction from which bit. This is intentionally
        simple and clearly labelled — swap it out once the servo/L293 encoding
        is [SIM]-verified.
        """
        cmds: list[MotorCommand] = []
        for axis in range(N_AXES):
            if axis < 4:
                bits, shift = port_a, axis * 2
            else:
                bits, shift = port_c, (axis - 4) * 2
            up = (bits >> shift) & 1
            dn = (bits >> (shift + 1)) & 1
            if up and not dn:
                cmds.append(MotorCommand(True, +1))
            elif dn and not up:
                cmds.append(MotorCommand(True, -1))
            else:
                cmds.append(MotorCommand(False, 0))
        return cmds

    def step_from_ports(self, port_a: int, port_c: int) -> None:
        """Advance all axes one tick given the raw 8255 Port A/C bytes."""
        for axis, cmd in enumerate(self.decode_l293(port_a, port_c)):
            self.step_axis(axis, cmd)

    def step_axis(self, axis: int, cmd: MotorCommand) -> None:
        if not cmd.enable or cmd.direction == 0:
            return
        v = self.pot[axis] + cmd.direction * self.step
        self.pot[axis] = max(POT_MIN, min(POT_MAX, v))

    def move_toward(self, axis: int, target: int) -> bool:
        """Fallback demo mode: nudge a pot toward `target` (no motor bits).

        Used when driving the firmware's real motor output isn't available;
        lets the GUI still show pot convergence. Returns True while moving.
        """
        cur = self.pot[axis]
        if cur == target:
            return False
        d = 1 if target > cur else -1
        step = min(self.step, abs(target - cur))
        self.pot[axis] = cur + d * step
        return self.pot[axis] != target


# ---- self-test ---------------------------------------------------------------
if __name__ == "__main__":
    p = Plant(pot=[100] * N_AXES, step=4)
    # axis 0 drive-up: Port A bit0 set
    p.step_from_ports(port_a=0b00000001, port_c=0)
    assert p.pot[0] == 104, p.pot[0]
    # axis 0 drive-down: Port A bit1 set
    p.step_from_ports(port_a=0b00000010, port_c=0)
    assert p.pot[0] == 100, p.pot[0]
    # axis 5 drive-up: Port C bit2 set (axis 5 -> shift (5-4)*2 = 2)
    p.step_from_ports(port_a=0, port_c=0b00000100)
    assert p.pot[5] == 104, p.pot[5]
    # clamp
    p.pot[1] = 254
    p.step_from_ports(port_a=0b00000100, port_c=0)  # axis 1 up (shift 2)
    assert p.pot[1] == 255, p.pot[1]
    # move_toward
    p.pot[2] = 10
    while p.move_toward(2, 20):
        pass
    assert p.pot[2] == 20, p.pot[2]
    print("plant self-test: OK")
