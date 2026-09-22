"""ROB3 low-level RS-232 wire protocol — pure codec, no ROS/serial dependencies.

Every command here is the Eurobtec ROB3 low-level protocol, reverse-engineered
and verified against the ROM/simulator. References:
  - hardware/host/command.md              (the protocol, ROM-confirmed [SIM])
  - firmware/src/annotated/rs232.asm  (the dispatch)

Frame model (verified):
  * Startup handshake: host sends 0x20 (SPACE) after RESET; robot replies 0x15
    (init OK) or 0xF1 (already initialized). Auto-baud locks on this byte.
  * Each command data record is  <header> [operand bytes...] 0x03 (ETX).
    The firmware enforces the trailing ETX (cjne A,#0x03 at 0x03AE).
  * The robot echoes the command keyword; positioning/control commands reply a
    single status byte, query commands reply keyword + data + ETX.
  * All 0xFx replies are ACK/status bytes, NOT errors (0xF3 default ACK, 0xF4
    system ACK, 0xF6/0xF2 program status, 0xF7 motion-complete). A byte outside
    the defined set is a comms/line error.

Command header bit fields (bit7=0 is the axis/position class; bit7=1 system):
  .7=0 .6=0 .5=0 .4=0 . R a a a   -> set single-axis POSITION (0x00..0x05, R@.3)
  .7=0 .6=0 .5=0 .4=0 . R 1 1 1   -> set all-axis POSITION      (0x07 / 0x0F)
  .7=0 .6=1 .5=0 .4=0 . 0 a a a   -> single-axis POSITION QUERY  (0x40..0x45)
  .7=0 .6=1 .5=0 .4=0 . 0 1 1 1   -> all-axis POSITION QUERY      (0x4F)
  .7=0 .6=1 .5=1 .4=1 . R a a a   -> single-axis POS + SPEED      (0x70..0x75)
  .7=0 .6=1 .5=1 .4=1 . R 1 1 1   -> all-axis POS + SPEED         (0x7F)
  0x60 / 0x61 / 0x62              -> motor disable / enable / shutdown(hold pos)
  0x63                            -> serial-number query

Positions are 8-bit counts (0..255). Axis index a = 0..5 (5 = gripper); a=7
addresses "all axes". R (bit 3) requests an acknowledge after the move.
"""
from __future__ import annotations

from dataclasses import dataclass
from enum import IntEnum

# --- framing constants --------------------------------------------------------
ETX = 0x03          # frame terminator [BYTE: cjne A,#0x03 @0x03AE]
SPACE = 0x20        # startup / auto-baud training byte [BYTE]

# --- startup replies ----------------------------------------------------------
REPLY_INIT_OK = 0x15        # initialization successful (auto-baud lock) [SIM]
REPLY_ALREADY_INIT = 0xF1   # already initialized (idle-timeout) [SIM]

# --- status byte family (all 0xFx are ACK/status, NOT errors) [SIM] ----------
STATUS_ACK = 0xF3           # default command ACK ("command received")
STATUS_SYS_ACK = 0xF4       # system-class ACK (0xF3 + 1)
STATUS_PROG = 0xF6          # program-operation status
STATUS_PROG_STEP = 0xF2     # program single-step status
STATUS_MOTION_DONE = 0xF7   # motion complete (target reached)

STATUS_BYTES = frozenset(
    {REPLY_INIT_OK, REPLY_ALREADY_INIT, STATUS_ACK, STATUS_SYS_ACK,
     STATUS_PROG, STATUS_PROG_STEP, STATUS_MOTION_DONE}
)

NUM_AXES = 6            # axes 0..5 (axis 5 = gripper)
ALL_AXES = 0x07        # axis field value that means "all axes"


class Op(IntEnum):
    """Command header base values (axis field OR'd in for per-axis commands)."""
    SET_POS = 0x00           # + axis ; +0x08 for R(ack); 0x07=all
    QUERY_POS = 0x40         # + axis ; 0x4F = all
    POS_SPEED = 0x70         # + axis ; 0x7F = all (followed by target + time factor)
    MOTOR_DISABLE = 0x60
    MOTOR_ENABLE = 0x61
    MOTOR_SHUTDOWN = 0x62    # software e-stop; current position retained
    SERIAL_NUMBER = 0x63


def _u8(v: int) -> int:
    """Clamp/validate a byte value 0..255."""
    if not (0 <= int(v) <= 255):
        raise ValueError(f"byte out of range 0..255: {v}")
    return int(v)


def _axis(a: int) -> int:
    if not (0 <= int(a) < NUM_AXES):
        raise ValueError(f"axis out of range 0..{NUM_AXES - 1}: {a}")
    return int(a)


def _frame(header: int, operands: bytes = b"") -> bytes:
    """A command record: header + operands + ETX."""
    return bytes([_u8(header)]) + bytes(operands) + bytes([ETX])


# =============================================================================
# Encoders (host -> robot)
# =============================================================================
def startup() -> bytes:
    """The single SPACE (0x20) byte sent after RESET to start comms / auto-baud.
    NOT a framed command (no ETX)."""
    return bytes([SPACE])


def set_axis_position(axis: int, count: int, ack: bool = True) -> bytes:
    """Set one axis's position (0x00..0x05, +0x08 if ack)."""
    header = Op.SET_POS | _axis(axis) | (0x08 if ack else 0x00)
    return _frame(header, bytes([_u8(count)]))


def set_all_positions(counts, ack: bool = True) -> bytes:
    """Set all six axis positions (0x07 / 0x0F). `counts` = 6 bytes."""
    counts = list(counts)
    if len(counts) != NUM_AXES:
        raise ValueError(f"expected {NUM_AXES} counts, got {len(counts)}")
    header = Op.SET_POS | ALL_AXES | (0x08 if ack else 0x00)
    return _frame(header, bytes(_u8(c) for c in counts))


def move_axis(axis: int, count: int, time_factor: int = 0, ack: bool = True) -> bytes:
    """Single-axis position + speed (0x70..0x75). time_factor T: 0=max speed,
    1..7 progressively slower (interval = T x 10 ms)."""
    header = Op.POS_SPEED | _axis(axis) | (0x08 if ack else 0x00)
    return _frame(header, bytes([_u8(count), _u8(time_factor)]))


def move_all(counts, time_factors, ack: bool = True) -> bytes:
    """All-axis position + speed (0x7F): 6 target bytes then 6 time factors."""
    counts = list(counts)
    time_factors = list(time_factors)
    if len(counts) != NUM_AXES or len(time_factors) != NUM_AXES:
        raise ValueError("expected 6 counts and 6 time factors")
    header = Op.POS_SPEED | ALL_AXES | (0x08 if ack else 0x00)
    body = bytes(_u8(c) for c in counts) + bytes(_u8(t) for t in time_factors)
    return _frame(header, body)


def query_axis_position(axis: int) -> bytes:
    """Ask for one axis's current position (0x40..0x45)."""
    return _frame(Op.QUERY_POS | _axis(axis))


def query_all_positions() -> bytes:
    """Ask for all six current positions. The manual documents this as 0x4F
    (0x40|0x07 with bit3 set); the firmware treats any axis field == 7 in the
    query class as 'all axes', so 0x47 works too. We emit the documented 0x4F."""
    return _frame(Op.QUERY_POS | ALL_AXES | 0x08)


def enable_motors() -> bytes:
    return _frame(Op.MOTOR_ENABLE)


def disable_motors() -> bytes:
    return _frame(Op.MOTOR_DISABLE)


def emergency_stop() -> bytes:
    """Software e-stop (0x62): stop motion, retain the current position."""
    return _frame(Op.MOTOR_SHUTDOWN)


def query_serial_number() -> bytes:
    return _frame(Op.SERIAL_NUMBER)


# =============================================================================
# Decoders (robot -> host)
# =============================================================================
@dataclass
class Reply:
    """A parsed reply frame."""
    keyword: int            # the echoed command byte
    data: bytes             # payload bytes between keyword and ETX
    ok: bool                # True if terminated by ETX and keyword is sane
    raw: bytes              # the raw bytes consumed


def is_status_byte(b: int) -> bool:
    """True if b is a defined ACK/status byte (0xFx family) — not an error."""
    return b in STATUS_BYTES


def parse_startup_reply(b: int):
    """Interpret the byte a robot sends after the SPACE handshake."""
    if b == REPLY_INIT_OK:
        return "init_ok"
    if b == REPLY_ALREADY_INIT:
        return "already_initialized"
    if b in STATUS_BYTES:
        return "already_initialized"
    return "error"


def parse_reply(buf: bytes) -> Reply:
    """Parse a keyword+data+ETX reply from `buf`. Returns a Reply; `ok` is False
    if no ETX is present. Extra trailing bytes after the first ETX are ignored."""
    if not buf:
        return Reply(keyword=-1, data=b"", ok=False, raw=b"")
    try:
        etx = buf.index(ETX)
    except ValueError:
        return Reply(keyword=buf[0], data=buf[1:], ok=False, raw=buf)
    frame = buf[: etx + 1]
    return Reply(keyword=frame[0], data=frame[1:-1], ok=True, raw=frame)


def parse_positions(reply: Reply, num: int = NUM_AXES):
    """From an all-axis query reply (keyword + N position bytes + ETX), return
    the list of counts. Raises ValueError on a malformed frame."""
    if not reply.ok:
        raise ValueError("reply not ETX-terminated")
    if len(reply.data) < num:
        raise ValueError(
            f"expected >= {num} position bytes, got {len(reply.data)}"
        )
    return list(reply.data[:num])
