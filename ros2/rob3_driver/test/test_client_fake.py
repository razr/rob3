"""Test Rob3Client end-to-end against a FAKE transport that emulates the ROB3
controller's replies. Exercises the full client path (handshake, framed
command/reply, position parsing) with NO ROS and NO real serial/simulator.

The fake models the verified reply behaviour:
  * on the 0x20 startup byte -> reply 0x15 (init OK)
  * on an all-axis query (0x4F..) -> keyword + 6 stored counts + ETX
  * on a single-axis query (0x40|a) -> keyword + count[a] + ETX
  * on set-all / set-axis -> update stored counts, reply status 0xF3 + ETX
  * on enable/disable/estop/serial# -> a status/keyword reply
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from rob3_driver import protocol as P  # noqa: E402
from rob3_driver.rob3_interface import Rob3Client  # noqa: E402


class FakeRobot:
    """A byte-level fake of the ROB3 controller for the client to talk to."""

    def __init__(self):
        self.counts = [10, 20, 30, 40, 50, 60]
        self.enabled = False
        self._rx = bytearray()   # bytes the host wrote to us (pending a frame)
        self._tx = bytearray()   # bytes we will hand back to the host

    # -- Transport interface expected by Rob3Client --------------------------
    def open(self):
        pass

    def close(self):
        pass

    def write(self, data: bytes):
        for b in data:
            if b == P.SPACE and not self._rx:
                # startup handshake byte (unframed)
                self._tx.append(P.REPLY_INIT_OK)
                continue
            self._rx.append(b)
            if b == P.ETX:
                self._handle(bytes(self._rx))
                self._rx.clear()

    def read(self, n: int, timeout: float = 1.0) -> bytes:
        out = bytes(self._tx[:n])
        del self._tx[:n]
        return out

    def read_until(self, term: int, timeout: float = 1.0, limit: int = 256) -> bytes:
        # return up to and including the first `term`
        for i, b in enumerate(self._tx):
            if b == term:
                out = bytes(self._tx[: i + 1])
                del self._tx[: i + 1]
                return out
        out = bytes(self._tx)
        self._tx.clear()
        return out

    # -- reply logic (mirrors command.md) ------------------------------------
    def _reply(self, keyword: int, data: bytes = b""):
        self._tx += bytes([keyword]) + data + bytes([P.ETX])

    def _handle(self, frame: bytes):
        header = frame[0]
        body = frame[1:-1]  # strip header + ETX
        axis = header & 0x07
        cls = header & 0xF0          # class bits (ignore ack bit .3 and axis)

        if cls == 0x40:              # position query class (0x40..0x4F)
            if axis == 0x07:
                self._reply(header, bytes(self.counts))             # all-axis query
            else:
                self._reply(header, bytes([self.counts[axis]]))     # single-axis query
        elif cls == 0x00:            # set-position class (0x00..0x0F)
            if axis == 0x07:
                self.counts = list(body[:6])                        # set all
            elif body:
                self.counts[axis] = body[0]                         # set single
            self._reply(P.STATUS_ACK)
        elif header == P.Op.MOTOR_ENABLE:
            self.enabled = True
            self._reply(P.STATUS_ACK)
        elif header == P.Op.MOTOR_DISABLE:
            self.enabled = False
            self._reply(P.STATUS_ACK)
        elif header == P.Op.MOTOR_SHUTDOWN:
            self._reply(P.STATUS_ACK)
        elif header == P.Op.SERIAL_NUMBER:
            self._reply(header, bytes([0x12, 0x34, 0x56]))          # S0,S1,S2
        else:
            self._reply(P.STATUS_ACK)


def test_handshake():
    fake = FakeRobot()
    client = Rob3Client(transport=fake)
    state = client.connect()
    assert state == "init_ok"
    assert client.initialized


def test_read_all_positions():
    fake = FakeRobot()
    fake.counts = [11, 22, 33, 44, 55, 66]
    client = Rob3Client(transport=fake)
    client.connect()
    assert client.read_all_positions() == [11, 22, 33, 44, 55, 66]


def test_read_single_axis():
    fake = FakeRobot()
    fake.counts = [1, 2, 3, 4, 5, 6]
    client = Rob3Client(transport=fake)
    client.connect()
    assert client.read_axis_position(3) == 4


def test_set_all_positions_roundtrip():
    fake = FakeRobot()
    client = Rob3Client(transport=fake)
    client.connect()
    reply = client.set_all_positions([0x80, 0x81, 0x82, 0x83, 0x84, 0x85])
    assert reply.ok and reply.keyword == P.STATUS_ACK
    # the fake stored them; reading back returns the same
    assert client.read_all_positions() == [0x80, 0x81, 0x82, 0x83, 0x84, 0x85]


def test_set_single_axis():
    fake = FakeRobot()
    client = Rob3Client(transport=fake)
    client.connect()
    client.set_axis_position(2, 0x99)
    assert client.read_axis_position(2) == 0x99


def test_motor_control_and_serial():
    fake = FakeRobot()
    client = Rob3Client(transport=fake)
    client.connect()
    assert client.enable_motors().ok and fake.enabled
    assert client.disable_motors().ok and not fake.enabled
    assert client.emergency_stop().ok
    assert client.read_serial_number() == [0x12, 0x34, 0x56]


def test_status_bytes_recognized_not_error():
    # every reply keyword we emit is a defined status/keyword, never an error
    fake = FakeRobot()
    client = Rob3Client(transport=fake)
    client.connect()
    r = client.enable_motors()
    assert P.is_status_byte(r.keyword)
