#!/usr/bin/env python3
"""Persistent ucSim engine for the ROB3 GUI.

Holds one long-lived `ucsim_51` (or `s51`) process and talks to it line by line,
using a prompt marker (`-p`) to know when a command has finished. This is the
interactive counterpart to harness/ucsim.py's batch driver — the GUI needs to
press a key, run a bit, read state, and repeat, all in one session.

Boundary (see harness/ARCHITECTURE.md):
  * ucSim owns the firmware + bus chips (incl. the compiled `adc` / `teachbox`
    cl_hw modules).
  * The GUI/plant owns the motor->pot physics and pushes pot values in via
    `set hardware adc <ch> <val>`; it reads motor commands from Port A/C.

If the custom `ucsim_51` (with the teachbox+adc modules) is not available the
engine still runs on stock `s51`, minus `set hardware` — the GUI then falls
back to its plant-only demo mode.
"""
from __future__ import annotations
import os
import pty
import re
import select
import shutil
import subprocess
import time

PROMPT = "R0B3>"          # unlikely to collide with normal output
# Strip all CSI escape sequences (colour, clear-to-EOL) that ucSim emits on a tty
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# Verified firmware landmarks (see rob3-firmware-map / annotated asm)
IRAM_TARGET = 0x40        # 0x40+N per-axis target
IRAM_CURPOS = 0x50        # 0x50+N per-axis current position
IRAM_FEEDBK = 0x58        # 0x58+N per-axis feedback (ADC copy)
XRAM_PORT_A = 0x5000      # 8255 Port A (motor bits, axes 0..3)
XRAM_PORT_C = 0x5200      # 8255 Port C (motor bits, axes 4..5)
MAIN_LOOP = 0x074D


def find_ucsim() -> tuple[str, bool]:
    """Return (binary, has_modules). Prefer a ucsim_51 with the cl_hw modules."""
    cand = os.environ.get("UCSIM_51")
    paths = [cand] if cand else []
    paths += [
        shutil.which("ucsim_51"),
        os.path.expanduser("~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51"),
    ]
    for p in paths:
        if p and os.path.exists(p) and os.access(p, os.X_OK):
            return p, _probe_modules(p)
    # fall back to stock s51 (no modules)
    s51 = shutil.which("s51")
    if s51:
        return s51, False
    raise FileNotFoundError("no ucsim_51 or s51 on PATH")


def _probe_modules(binary: str) -> bool:
    hexf = _safe_hex()
    try:
        out = subprocess.run(
            [binary, "-t", "51", "-X", "11.0592M", hexf],
            input="set hardware adc\nquit\n",
            capture_output=True, text=True, timeout=10,
        ).stdout
    except Exception:
        return False
    return "adc[" in out


def default_hex() -> str:
    """The default ROM path (repo firmware/hex/M2764A@DIP28.HEX).

    Overridable by the ROB3_HEX environment variable.
    """
    env = os.environ.get("ROB3_HEX")
    if env:
        return os.path.expanduser(env)
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.normpath(os.path.join(
        here, "..", "..", "..", "firmware", "hex", "M2764A@DIP28.HEX"))


def _safe_hex(src: str | None = None) -> str:
    """Return a shell-safe (@-free) copy of the ROM under simulator/build/.

    `src` is the ROM to load; defaults to default_hex() (which honours the
    ROB3_HEX env var). ucSim mis-parses '@' in a filename, so the ROM is
    always copied to an @-free path before loading.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    build = os.path.normpath(os.path.join(here, "..", "..", "build"))
    os.makedirs(build, exist_ok=True)
    dst = os.path.join(build, "rob3.hex")
    if src is None:
        src = default_hex()
    if os.path.exists(src):
        shutil.copyfile(src, dst)
    return dst


class UCSimEngine:
    def __init__(self, xtal: str = "11.0592M", hex_path: str | None = None,
                 console_port: int | None = None):
        self.binary, self.has_modules = find_ucsim()
        self.hexf = _safe_hex(hex_path)
        self.console_port = console_port
        # ucSim only emits its prompt on a TTY, so drive it through a pty.
        self.pid, self.fd = pty.fork()
        if self.pid == 0:  # child
            argv = [self.binary, "-t", "51", "-X", xtal, "-p", PROMPT]
            if console_port:
                # -z: command console on localhost:<port> AND on stdio, so the
                # CLI can still boot the ROM over its pty while a separate
                # terminal attaches with `nc localhost <port>`.
                # -b: black & white (no ANSI colour) so the nc stream is clean.
                argv += ["-b", "-z", str(console_port)]
            argv.append(self.hexf)
            os.execv(self.binary, argv)
            os._exit(127)  # unreachable
        self._wait_prompt(timeout=5.0)   # consume banner up to first prompt

    # -- low-level I/O (pty) --------------------------------------------------
    def _read_until_prompt(self, timeout: float) -> str:
        buf = ""
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([self.fd], [], [], 0.2)
            if not r:
                continue
            try:
                data = os.read(self.fd, 4096)
            except OSError:
                break
            if not data:
                break
            buf += data.decode("latin-1", "replace")
            if PROMPT in buf:
                break
        buf = ANSI.sub("", buf).replace("\r", "")
        # drop the trailing prompt token and the echoed command line
        return buf.split(PROMPT)[0]

    def _wait_prompt(self, timeout: float) -> str:
        return self._read_until_prompt(timeout)

    def cmd(self, line: str, timeout: float = 5.0) -> str:
        """Send one command, return output up to the next prompt."""
        if line:
            os.write(self.fd, (line + "\n").encode("latin-1"))
        out = self._read_until_prompt(timeout)
        # strip the echoed command itself from the head of the output
        if line and out.lstrip().startswith(line):
            out = out.lstrip()[len(line):]
        return out

    # -- firmware control -----------------------------------------------------
    def reset(self, fixed_baud: bool = True) -> None:
        self.cmd("reset")
        if fixed_baud:
            self.cmd("set mem sfr 0xb0 0x00")   # P3.0=0 -> fixed-baud path

    def run_cycles(self, n: int) -> None:
        self.cmd("run %d" % n, timeout=20.0)

    def run_to(self, addr: int, cycles: int = 3_000_000) -> bool:
        self.cmd("break 0x%04x" % addr)
        out = self.cmd("run %d" % cycles, timeout=30.0)
        self.cmd("clear 0x%04x" % addr)
        return ("stop at 0x%06x" % addr) in out.lower() \
            or ("stop at 0x%04x" % addr) in out.lower()

    # -- teachbox / adc (need the modules) ------------------------------------
    def press(self, row: int, group: int) -> None:
        if self.has_modules:
            self.cmd(f"set hardware teachbox {row} {group}")

    def release(self) -> None:
        if self.has_modules:
            self.cmd("set hardware teachbox 0")

    def push_pot(self, ch: int, value: int) -> None:
        if self.has_modules:
            self.cmd(f"set hardware adc {ch} 0x%02x" % (value & 0xFF))

    # -- state readback -------------------------------------------------------
    def _dump_byte(self, space: str, addr: int) -> int:
        out = self.cmd("dump %s 0x%04x 0x%04x" % (space, addr, addr))
        m = re.search(r"0x0*%x\b[^\n]*?\s([0-9a-fA-F]{2})\b" % addr, out, re.I)
        return int(m.group(1), 16) if m else -1

    def read_positions(self) -> list[int]:
        out = self.cmd("dump iram 0x50 0x55")
        return self._row6(out, 0x50)

    def read_targets(self) -> list[int]:
        out = self.cmd("dump iram 0x40 0x45")
        return self._row6(out, 0x40)

    def read_ports(self) -> tuple[int, int]:
        pa = self._dump_byte("xram", XRAM_PORT_A)
        pc = self._dump_byte("xram", XRAM_PORT_C)
        return pa, pc

    @staticmethod
    def _row6(out: str, addr: int) -> list[int]:
        m = re.search(r"0x%02x\b([^\n]*)" % (addr & 0xff), out, re.I)
        if not m:
            return [-1] * 6
        hexes = re.findall(r"\b([0-9a-fA-F]{2})\b", m.group(1))
        vals = [int(h, 16) for h in hexes[:6]]
        return (vals + [-1] * 6)[:6]

    def set_iram(self, addr: int, value: int) -> None:
        self.cmd("set mem iram 0x%02x 0x%02x" % (addr, value & 0xFF))

    def close(self) -> None:
        try:
            os.write(self.fd, b"quit\n")
            time.sleep(0.2)
        except OSError:
            pass
        try:
            os.close(self.fd)
        except OSError:
            pass
        try:
            os.waitpid(self.pid, os.WNOHANG)
        except OSError:
            pass


# ---- smoke test --------------------------------------------------------------
if __name__ == "__main__":
    eng = UCSimEngine()
    print(f"binary={eng.binary}  modules={eng.has_modules}")
    eng.reset()
    reached = eng.run_to(MAIN_LOOP)
    print("reached main loop:", reached)
    print("targets  :", ["0x%02x" % v for v in eng.read_targets()])
    print("positions:", ["0x%02x" % v for v in eng.read_positions()])
    print("ports A/C:", ["0x%02x" % v for v in eng.read_ports()])
    eng.close()
