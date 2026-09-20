"""High-level ROB3 client: protocol codec + a transport = a usable robot API.

No ROS dependencies — this is the reusable "libur"-equivalent client. The ROS
node wraps it. Thread-safety: guard calls with the provided lock if sharing one
instance across threads (the driver node does).
"""
from __future__ import annotations

import threading
from dataclasses import dataclass, field
from typing import List, Optional

from . import protocol as P
from .transport import Transport


@dataclass
class Rob3Client:
    transport: Transport
    lock: threading.Lock = field(default_factory=threading.Lock)
    _initialized: bool = False

    # -- lifecycle -----------------------------------------------------------
    def connect(self, startup_timeout: float = 2.0) -> str:
        """Open the transport and perform the RESET handshake: send SPACE, read
        the reply (0x15 init-OK / 0xF1 already-init). Returns the state string."""
        self.transport.open()
        return self.reset_handshake(startup_timeout)

    def reset_handshake(self, timeout: float = 2.0) -> str:
        with self.lock:
            self.transport.write(P.startup())
            # the robot floods a startup byte; read one meaningful byte
            reply = self.transport.read(1, timeout=timeout)
            if not reply:
                return "no_reply"
            state = P.parse_startup_reply(reply[0])
            self._initialized = state in ("init_ok", "already_initialized")
            # drain any following duplicate startup bytes
            self.transport.read(64, timeout=0.05)
            return state

    def close(self) -> None:
        self.transport.close()

    @property
    def initialized(self) -> bool:
        return self._initialized

    # -- one framed command + its reply --------------------------------------
    def _command(self, frame: bytes, reply_timeout: float = 1.0) -> P.Reply:
        with self.lock:
            self.transport.write(frame)
            buf = self.transport.read_until(P.ETX, timeout=reply_timeout)
            return P.parse_reply(buf)

    # -- motion --------------------------------------------------------------
    def set_axis_position(self, axis: int, count: int, ack: bool = True) -> P.Reply:
        return self._command(P.set_axis_position(axis, count, ack))

    def set_all_positions(self, counts: List[int], ack: bool = True) -> P.Reply:
        return self._command(P.set_all_positions(counts, ack))

    def move_axis(self, axis: int, count: int, time_factor: int = 0) -> P.Reply:
        return self._command(P.move_axis(axis, count, time_factor))

    def move_all(self, counts: List[int], time_factors: List[int]) -> P.Reply:
        return self._command(P.move_all(counts, time_factors))

    # -- queries -------------------------------------------------------------
    def read_all_positions(self, timeout: float = 1.0) -> Optional[List[int]]:
        reply = self._command(P.query_all_positions(), reply_timeout=timeout)
        try:
            return P.parse_positions(reply)
        except ValueError:
            return None

    def read_axis_position(self, axis: int, timeout: float = 1.0) -> Optional[int]:
        reply = self._command(P.query_axis_position(axis), reply_timeout=timeout)
        if reply.ok and reply.data:
            return reply.data[0]
        return None

    def read_serial_number(self, timeout: float = 1.0):
        reply = self._command(P.query_serial_number(), reply_timeout=timeout)
        if reply.ok:
            return list(reply.data)
        return None

    # -- control -------------------------------------------------------------
    def enable_motors(self) -> P.Reply:
        return self._command(P.enable_motors())

    def disable_motors(self) -> P.Reply:
        return self._command(P.disable_motors())

    def emergency_stop(self) -> P.Reply:
        return self._command(P.emergency_stop())
