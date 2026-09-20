"""Per-axis calibration: map a joint value (radians, or metres for the gripper)
to/from the firmware's 8-bit position count (0..255), and back.

The ROB3 firmware is unit-agnostic: it stores/compares raw 0..255 counts (the
pot's ratiometric ADC reading). The mapping from a physical joint angle to a
count is a per-axis, measured, linear relationship that lives OUTSIDE the
firmware. Joint ranges are from the project README / hardware docs:

  axis 0  base rotation   q1  +80° .. -80°
  axis 1  shoulder        q2  +70° .. -30°
  axis 2  elbow           q3    0° .. -100°
  axis 3  wrist pitch     q4  +100° .. -100°
  axis 4  wrist roll      q5  +100° .. -100°
  axis 5  gripper             0 .. 60 mm   (linear stroke)

PROVENANCE / ACCURACY
  These ranges are [HW-doc]. The exact count-at-each-limit is a per-unit bench
  measurement; where bench data exists (hardware/motors/test.md, AXIS_CAL) it
  should be substituted here. The default `count = round(lerp(min,max))` mapping
  below is a reasonable, clearly-linear placeholder — VERIFY on the real robot
  before trusting absolute positioning. Direction (which limit is count 0 vs
  255) is likewise per-unit and marked to-verify.

⚠️ SAFETY: the firmware validates only 0..255 and the axis number; it does NOT
enforce a per-axis soft limit (see hardware/motors/test.md safety note). This
module clamps the *count* to [count_min, count_max] per axis so a joint command
cannot drive an axis past its usable window into a hard stop.
"""
from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass(frozen=True)
class AxisCal:
    name: str
    # physical value (rad for revolute, m for the prismatic gripper) at the two
    # count endpoints:
    value_at_0: float      # joint value when count == count_lo
    value_at_255: float    # joint value when count == count_hi
    count_lo: int = 0
    count_hi: int = 255
    prismatic: bool = False  # gripper (metres) vs revolute (radians)


def _rad(deg: float) -> float:
    return deg * math.pi / 180.0


# Default per-axis calibration [HW-doc ranges; endpoint counts = PLACEHOLDER,
# verify on the bench]. Direction assumed count 0 -> first listed limit.
DEFAULT_CAL = (
    AxisCal("base",        _rad(+80.0), _rad(-80.0)),                  # axis 0
    AxisCal("shoulder",    _rad(+70.0), _rad(-30.0)),                  # axis 1
    AxisCal("elbow",       _rad(0.0),   _rad(-100.0)),                 # axis 2
    AxisCal("wrist_pitch", _rad(+100.0), _rad(-100.0)),               # axis 3
    AxisCal("wrist_roll",  _rad(+100.0), _rad(-100.0)),               # axis 4
    AxisCal("gripper",     0.0,          0.060, prismatic=True),       # axis 5 (m)
)


class Calibration:
    """Convert between joint values and 0..255 counts for all six axes."""

    def __init__(self, cal=DEFAULT_CAL):
        if len(cal) != 6:
            raise ValueError("need calibration for 6 axes")
        self.cal = tuple(cal)

    def joint_to_count(self, axis: int, value: float) -> int:
        """Map a joint value to a clamped 0..255 count."""
        c = self.cal[axis]
        span = (c.value_at_255 - c.value_at_0)
        if span == 0:
            frac = 0.0
        else:
            frac = (value - c.value_at_0) / span
        count = c.count_lo + frac * (c.count_hi - c.count_lo)
        count = int(round(count))
        # clamp to the axis's usable window (firmware does NOT soft-limit)
        lo, hi = sorted((c.count_lo, c.count_hi))
        return max(lo, min(hi, count))

    def count_to_joint(self, axis: int, count: int) -> float:
        """Map a 0..255 count back to a joint value."""
        c = self.cal[axis]
        denom = (c.count_hi - c.count_lo)
        frac = 0.0 if denom == 0 else (count - c.count_lo) / denom
        return c.value_at_0 + frac * (c.value_at_255 - c.value_at_0)

    def joints_to_counts(self, values):
        return [self.joint_to_count(i, v) for i, v in enumerate(values)]

    def counts_to_joints(self, counts):
        return [self.count_to_joint(i, c) for i, c in enumerate(counts)]

    @property
    def joint_names(self):
        return [c.name for c in self.cal]

    def is_prismatic(self, axis: int) -> bool:
        return self.cal[axis].prismatic
