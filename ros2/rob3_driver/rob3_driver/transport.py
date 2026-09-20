"""Transports for the ROB3 link: a real serial port and a TCP socket.

The ROB3 controller uses RS-232. During development the same bytes can be sent
to the ucSim simulator through its `-S port=<n>` UART socket, so this module
offers two interchangeable transports behind one tiny interface:

    open() / close() / write(bytes) / read(n, timeout) / read_until(term, timeout)

- SerialTransport  : real /dev/ttyUSB0 via pyserial (9600 8N1 by default; the
                     ROB3 firmware auto-bauds off the first 0x20).
- TcpTransport     : localhost:<port> to ucSim's -S serial socket.

No ROS dependencies here so the transport is unit-testable and reusable.
"""
from __future__ import annotations

import socket
import time
from typing import Optional, Protocol


class Transport(Protocol):
    def open(self) -> None: ...
    def close(self) -> None: ...
    def write(self, data: bytes) -> None: ...
    def read(self, n: int, timeout: float = 1.0) -> bytes: ...
    def read_until(self, term: int, timeout: float = 1.0, limit: int = 256) -> bytes: ...


class SerialTransport:
    """Real RS-232 via pyserial. 9600 8N1, no flow control (see
    hardware/host/README.md). pyserial is imported lazily so the package can be
    built/tested without it."""

    def __init__(self, device: str = "/dev/ttyUSB0", baud: int = 9600):
        self.device = device
        self.baud = baud
        self._ser = None

    def open(self) -> None:
        import serial  # lazy import; only needed for real HW

        self._ser = serial.Serial(
            port=self.device,
            baudrate=self.baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=0.0,          # non-blocking; we poll with our own timeouts
            rtscts=False,
            xonxoff=False,
        )

    def close(self) -> None:
        if self._ser is not None:
            self._ser.close()
            self._ser = None

    def write(self, data: bytes) -> None:
        assert self._ser is not None, "transport not open"
        self._ser.write(data)
        self._ser.flush()

    def read(self, n: int, timeout: float = 1.0) -> bytes:
        assert self._ser is not None, "transport not open"
        out = bytearray()
        deadline = time.monotonic() + timeout
        while len(out) < n and time.monotonic() < deadline:
            chunk = self._ser.read(n - len(out))
            if chunk:
                out.extend(chunk)
            else:
                time.sleep(0.002)
        return bytes(out)

    def read_until(self, term: int, timeout: float = 1.0, limit: int = 256) -> bytes:
        assert self._ser is not None, "transport not open"
        out = bytearray()
        deadline = time.monotonic() + timeout
        while len(out) < limit and time.monotonic() < deadline:
            chunk = self._ser.read(1)
            if chunk:
                out.extend(chunk)
                if chunk[0] == term:
                    break
            else:
                time.sleep(0.002)
        return bytes(out)


class TcpTransport:
    """ucSim `-S port=<n>` serial socket (or any TCP byte stream). Note: some
    ucSim builds wrap the socket with a small amount of telnet/ANSI negotiation
    on connect; callers that need pristine bytes should skip the leading
    non-protocol bytes (the driver filters to defined status/ETX frames)."""

    def __init__(self, host: str = "127.0.0.1", port: int = 54321):
        self.host = host
        self.port = port
        self._sock: Optional[socket.socket] = None

    def open(self) -> None:
        self._sock = socket.create_connection((self.host, self.port), timeout=2.0)
        self._sock.setblocking(False)

    def close(self) -> None:
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None

    def write(self, data: bytes) -> None:
        assert self._sock is not None, "transport not open"
        self._sock.sendall(data)

    def _recv_some(self) -> bytes:
        assert self._sock is not None
        try:
            return self._sock.recv(256)
        except (BlockingIOError, InterruptedError):
            return b""

    def read(self, n: int, timeout: float = 1.0) -> bytes:
        out = bytearray()
        deadline = time.monotonic() + timeout
        while len(out) < n and time.monotonic() < deadline:
            chunk = self._recv_some()
            if chunk:
                out.extend(chunk)
            else:
                time.sleep(0.002)
        return bytes(out)

    def read_until(self, term: int, timeout: float = 1.0, limit: int = 256) -> bytes:
        out = bytearray()
        deadline = time.monotonic() + timeout
        while len(out) < limit and time.monotonic() < deadline:
            chunk = self._recv_some()
            if chunk:
                for b in chunk:
                    out.append(b)
                    if b == term:
                        return bytes(out)
            else:
                time.sleep(0.002)
        return bytes(out)


def make_transport(kind: str, **kw) -> Transport:
    """Factory: kind in {'serial', 'tcp'}."""
    kind = kind.lower()
    if kind == "serial":
        return SerialTransport(device=kw.get("device", "/dev/ttyUSB0"),
                               baud=int(kw.get("baud", 9600)))
    if kind == "tcp":
        return TcpTransport(host=kw.get("host", "127.0.0.1"),
                            port=int(kw.get("port", 54321)))
    raise ValueError(f"unknown transport kind: {kind!r}")
