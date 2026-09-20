"""Unit tests for the joint<->count calibration (no ROS needed)."""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from rob3_driver.calibration import Calibration  # noqa: E402


def test_six_axes_and_names():
    c = Calibration()
    assert len(c.joint_names) == 6
    assert c.joint_names[0] == "base"
    assert c.joint_names[5] == "gripper"
    assert c.is_prismatic(5) and not c.is_prismatic(0)


def test_endpoints_map_to_count_bounds():
    c = Calibration()
    # base: +80 deg -> count 0, -80 deg -> count 255 (per DEFAULT_CAL direction)
    assert c.joint_to_count(0, math.radians(80.0)) == 0
    assert c.joint_to_count(0, math.radians(-80.0)) == 255


def test_midpoint_roundtrip():
    c = Calibration()
    # count 128 -> some joint value -> back to ~128
    for axis in range(6):
        val = c.count_to_joint(axis, 128)
        back = c.joint_to_count(axis, val)
        assert abs(back - 128) <= 1


def test_clamp_out_of_range():
    c = Calibration()
    # way past a limit clamps into 0..255
    huge = c.joint_to_count(0, math.radians(1000.0))
    assert 0 <= huge <= 255


def test_gripper_metres():
    c = Calibration()
    assert c.joint_to_count(5, 0.0) == 0
    assert c.joint_to_count(5, 0.060) == 255
    assert abs(c.count_to_joint(5, 255) - 0.060) < 1e-6
