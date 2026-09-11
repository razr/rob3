#!/usr/bin/env python3
"""Batch driver for the ucSim `s51` 8051 simulator.

Rather than hold a fragile interactive session, each "transaction" runs s51 once
on a script of commands and parses the full output. State that must persist
across transactions (RAM contents, PC) is re-applied at the top of each script
by the caller (see rob3_sim.py, which keeps a shadow of the relevant RAM and
re-seeds it every tick). This is slower but deterministic and robust.

Requires the `s51` binary (SDCC ucSim) on PATH.
"""
from __future__ import annotations
import re
import subprocess


class UCSimBatch:
    def __init__(self, hex_path: str, cpu: str = "51", xtal: str = "11.0592M",
                 sim: str = "s51"):
        self.hex_path = hex_path
        self.cpu = cpu
        self.xtal = xtal
        self.sim = sim

    def run(self, script: str, timeout: float = 20.0) -> str:
        """Feed `script` (newline-separated commands) to s51; return clean output."""
        if not script.endswith("\n"):
            script += "\n"
        if "quit" not in script.split("\n")[-3:]:
            script += "quit\n"
        p = subprocess.run(
            [self.sim, "-t", self.cpu, "-X", self.xtal, self.hex_path],
            input=script, capture_output=True, text=True, timeout=timeout,
        )
        # Strip the ucSim ANSI "clear to EOL" sequences.
        return re.sub(r"\x1b\[0K", "", p.stdout)

    # -- parsing helpers ------------------------------------------------------
    @staticmethod
    def parse_dump_byte(out: str, addr: int) -> int:
        """Parse a `dump iram/sfr` line for `addr` -> first data byte."""
        pat = re.compile(r"^0x%02x\b.*?\s([0-9a-fA-F]{2})\s" % addr, re.M | re.I)
        m = pat.search(out)
        return int(m.group(1), 16) if m else -1

    @staticmethod
    def parse_dump_row(out: str, addr: int, n: int) -> list[int]:
        """Parse `n` bytes starting at `addr` from a dump row."""
        m = re.search(r"^0x%02x\b[^\n]*" % addr, out, re.M | re.I)
        if not m:
            return []
        hexes = re.findall(r"\b([0-9a-fA-F]{2})\b", m.group(0))
        # first token is the address's low byte echo; drop leading addr repeats
        # by taking the trailing n data bytes on the row.
        return [int(h, 16) for h in hexes[-n:]] if len(hexes) >= n else \
               [int(h, 16) for h in hexes]

    @staticmethod
    def parse_stopped_pc(out: str):
        m = None
        for m in re.finditer(r"Stop at (0x[0-9a-fA-F]+)", out):
            pass
        return int(m.group(1), 16) if m else None
