"""Unit tests for the ROB3 wire-protocol codec (no ROS/serial needed).

Run standalone:  python3 -m pytest ros2/rob3_driver/test/test_protocol.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from rob3_driver import protocol as P  # noqa: E402


def test_startup_is_single_space():
    assert P.startup() == bytes([0x20])


def test_frames_end_with_etx():
    for f in (P.enable_motors(), P.disable_motors(), P.emergency_stop(),
              P.query_all_positions(), P.set_axis_position(0, 128)):
        assert f[-1] == P.ETX


def test_set_axis_position_encoding():
    # axis 2, count 0x80, with ack -> header 0x00|0x02|0x08 = 0x0A, then 0x80, ETX
    assert P.set_axis_position(2, 0x80, ack=True) == bytes([0x0A, 0x80, 0x03])
    # no ack -> header 0x02
    assert P.set_axis_position(2, 0x80, ack=False) == bytes([0x02, 0x80, 0x03])


def test_set_all_positions_encoding():
    counts = [0x10, 0x20, 0x30, 0x40, 0x50, 0x60]
    f = P.set_all_positions(counts, ack=False)
    # header 0x00|0x07 = 0x07, then 6 counts, then ETX
    assert f == bytes([0x07] + counts + [0x03])
    # with ack -> 0x0F
    assert P.set_all_positions(counts, ack=True)[0] == 0x0F


def test_query_encodings():
    assert P.query_axis_position(1) == bytes([0x41, 0x03])
    assert P.query_all_positions() == bytes([0x4F, 0x03])


def test_move_axis_has_target_and_time_factor():
    # single-axis pos+speed axis0 -> header 0x70|0|0x08 = 0x78, target, T, ETX
    f = P.move_axis(0, 0x90, time_factor=3, ack=True)
    assert f == bytes([0x78, 0x90, 0x03, 0x03])  # note: T=3 then ETX=0x03


def test_move_all_layout():
    counts = [1, 2, 3, 4, 5, 6]
    tf = [0, 1, 2, 3, 4, 5]
    f = P.move_all(counts, tf, ack=False)
    assert f[0] == 0x77
    assert list(f[1:7]) == counts
    assert list(f[7:13]) == tf
    assert f[-1] == P.ETX


def test_control_commands():
    assert P.enable_motors() == bytes([0x61, 0x03])
    assert P.disable_motors() == bytes([0x60, 0x03])
    assert P.emergency_stop() == bytes([0x62, 0x03])
    assert P.query_serial_number() == bytes([0x63, 0x03])


def test_axis_and_byte_range_validation():
    import pytest
    with pytest.raises(ValueError):
        P.set_axis_position(6, 0)      # axis out of range
    with pytest.raises(ValueError):
        P.set_axis_position(0, 256)    # byte out of range


def test_startup_reply_classification():
    assert P.parse_startup_reply(0x15) == "init_ok"
    assert P.parse_startup_reply(0xF1) == "already_initialized"
    assert P.parse_startup_reply(0xF3) == "already_initialized"
    assert P.parse_startup_reply(0x00) == "error"


def test_status_bytes_are_not_errors():
    for b in (0x15, 0xF1, 0xF2, 0xF3, 0xF4, 0xF6, 0xF7):
        assert P.is_status_byte(b)
    assert not P.is_status_byte(0x00)
    assert not P.is_status_byte(0xAB)


def test_parse_reply_and_positions():
    # all-axis query reply: keyword 0x4F + 6 position bytes + ETX
    buf = bytes([0x4F, 11, 22, 33, 44, 55, 66, P.ETX, 0x99])  # trailing byte ignored
    r = P.parse_reply(buf)
    assert r.ok and r.keyword == 0x4F
    assert P.parse_positions(r) == [11, 22, 33, 44, 55, 66]


def test_parse_reply_without_etx_is_not_ok():
    r = P.parse_reply(bytes([0x4F, 1, 2, 99]))   # no ETX (0x03) present
    assert not r.ok
