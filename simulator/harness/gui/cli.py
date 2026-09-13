#!/usr/bin/env python3
"""ROB3 Teachbox — CLI front-end.

A text version of the Teachbox GUI: type Teachbox keystrokes, watch the six
axes' potentiometer feedback change. Same engine + plant as the GUI (see
gui.py / ARCHITECTURE.md): the keypad drives the real firmware in ucSim (when
the custom ucsim_51 with the cl_hw modules is present), and the motor->pot
physics is modelled by the external plant.

Keystroke language (type a string of these, e.g. "P 1 . 128 E"):
    0-9     numeric keys (axis select in POSITION mode: 2..7 -> axis 0..5;
            also the decimal digits of a POS value)
    .       decimal point separator (the "POS a . n" dot)
    +  -    jog the selected axis up / down one step
    P       POS  (position mode)
    E       ENT  (enter / commit)
    N       NOP
    D       DEL
    C       ERR CLR
    R       RUN
    I       INS
    O       OUT

Meta commands (start with ':'):
    :show            print the six axes
    :axis N          select axis N (0..5) directly
    :target N V      set the plant target for axis N to V (0..255)
    :run             let the plant settle and print
    :help            show this help
    :quit / :q       exit

Run:
    python3 cli.py                                   # plant-only (default)
    UCSIM_51=/path/to/ucsim_51 python3 cli.py --firmware        # firmware, default ROM
    UCSIM_51=/path/to/ucsim_51 python3 cli.py --firmware rom.hex # firmware, custom ROM
    python3 cli.py --script "P 1 . 128 E"            # non-interactive

    NOTE: UCSIM_51 alone does NOTHING without --firmware. The ROM is only run
    in ucSim when --firmware is given; UCSIM_51 just points --firmware at the
    custom ucsim_51 (built with the cl_hw modules). Plain `python3 cli.py`
    (even with UCSIM_51 set) is plant-only — no ROM, no ucSim.

    Bare --firmware loads the default ROM (firmware/hex/M2764A@DIP28.HEX, or
    the ROB3_HEX env var); --firmware <hexfile> loads that ROM instead.
"""
from __future__ import annotations
import argparse
import os
import sys
import time

try:
    import readline  # arrow-key history + line editing for input()
except ImportError:  # not available on some platforms
    readline = None

from plant import Plant, N_AXES
try:
    from engine import UCSimEngine, MAIN_LOOP
    HAVE_ENGINE = True
except Exception:
    HAVE_ENGINE = False

# key char -> (label, row, group)  — mirrors gui.py KEYS (verified mapping)
KEYMAP = {
    "0": ("0", 0, 2), "1": ("1", 1, 2), "2": ("2", 2, 2), "3": ("3", 3, 2),
    "4": ("4", 4, 2), "5": ("5", 5, 2), "6": ("6", 6, 2), "7": ("7", 7, 2),
    "8": ("8", 0, 1), "9": ("9", 1, 1),
    ".": (".", None, None),          # decimal separator: UI-level, no matrix key
    "+": ("UP/RIGHT", 3, 1), "-": ("DOWN/LEFT", 4, 1),
    "P": ("POS", 2, 3), "E": ("ENT", 5, 1), "N": ("NOP", 2, 1),
    "D": ("DEL", 7, 1), "C": ("ERR", 6, 1), "R": ("RUN", 7, 3),
    "I": ("INS", 0, 3), "O": ("OUT", 1, 3),
}

AXES = ["q1 Base", "q2 Shoulder", "q3 Elbow", "q4 Wrist", "q5 Roll", "Gripper"]


class TeachboxCLI:
    def __init__(self, settle_ticks: int = 40, step: int = 6,
                 drive_firmware: bool = False, hex_path: str | None = None,
                 console_port: int | None = None):
        self.plant = Plant(pot=[128] * N_AXES, step=step)
        self.targets = list(self.plant.pot)
        self.selected: int | None = None
        self.pos_mode = False
        self.seen_dot = False
        self.accum = ""                 # digits typed since last axis/POS
        self.settle_ticks = settle_ticks
        self.drive_firmware = drive_firmware
        self.engine = None
        if HAVE_ENGINE and drive_firmware:
            try:
                eng = UCSimEngine(hex_path=hex_path, console_port=console_port)
                if eng.has_modules:
                    eng.reset()
                    eng.run_to(MAIN_LOOP)
                    self.engine = eng
                    print(f"[ucSim up: {eng.binary}  modules — firmware in the loop]")
                    print(f"[ROM: {eng.hexf}]")
                    if console_port:
                        print(f"[console socket: nc localhost {console_port}  "
                              f"(dump / di / break / step ...)]")
                else:
                    eng.close()
                    print("[stock s51 (no cl_hw modules) — plant-only]")
            except Exception as e:
                print(f"[ucSim unavailable: {e} — plant-only]")
                self.engine = None
        elif drive_firmware:
            print("[engine module unavailable — plant-only]")
        else:
            print("[plant-only mode (use --firmware to drive the ROM in ucSim)]")

    # -- keystroke handling ---------------------------------------------------
    def key(self, ch: str) -> None:
        if ch == " ":
            return
        if ch not in KEYMAP:
            print(f"  ? unknown key '{ch}'")
            return
        label, row, group = KEYMAP[ch]

        if ch.isdigit():
            if self.pos_mode and self.seen_dot:
                self.accum += ch                     # building the POS value (after '.')
            elif self.pos_mode and not self.seen_dot:
                # "POS a . n": the digit before '.' is the axis designator
                if 0 <= int(ch) <= 5:
                    self.selected = int(ch)
                    print(f"  POS: select axis {self.selected}")
            elif 0 <= int(ch) <= 5:
                self.selected = int(ch)              # plain axis select (0..5)
                print(f"  select axis {self.selected}")
        elif ch == "P":
            self.pos_mode = True
            self.seen_dot = False
            self.accum = ""
            print("  POS mode")
        elif ch == ".":
            self.seen_dot = True                     # value digits follow
        elif ch in ("+", "-"):
            self._jog(+1 if ch == "+" else -1)
        elif ch == "E":
            self._commit()

        # drive the real firmware scanner if enabled and the module is present
        if self.engine and self.engine.has_modules and group in (1, 2, 3):
            self.engine.press(row, group)
            self.engine.run_cycles(8000)   # small budget: interactive ucSim is slow
            self.engine.release()

    def _jog(self, direction: int) -> None:
        if self.selected is None:
            print("  (no axis selected)")
            return
        self.targets[self.selected] = _clamp(
            self.targets[self.selected] + direction * self.plant.step)
        print(f"  jog axis {self.selected} -> target {self.targets[self.selected]}")
        self.settle()

    def _commit(self) -> None:
        if self.pos_mode and self.selected is not None and self.accum:
            val = _clamp(int(self.accum))
            self.targets[self.selected] = val
            print(f"  POS commit: axis {self.selected} = {val}")
            self.settle()
        self.pos_mode = False
        self.seen_dot = False
        self.accum = ""

    # -- plant + firmware -----------------------------------------------------
    def settle(self) -> None:
        """Run the plant toward targets; push pots into the firmware ADC."""
        for _ in range(self.settle_ticks):
            moving = False
            for a in range(N_AXES):
                if self.plant.move_toward(a, self.targets[a]):
                    moving = True
            if not moving:
                break
        if self.engine and self.engine.has_modules:
            self.engine.push_pots(self.plant.pot)   # one batched pty write

    def show(self) -> None:
        print()
        for a in range(N_AXES):
            print(f"  {a} {AXES[a]:<12} {_bar(self.plant.pot[a])} "
                  f"{self.plant.pot[a]:3d}  (tgt {self.targets[a]:3d})"
                  f"{'  <' if a == self.selected else ''}")
        print()

    # -- meta commands --------------------------------------------------------
    def meta(self, line: str) -> bool:
        parts = line[1:].split()
        if not parts:
            return True
        c = parts[0]
        if c in ("quit", "q"):
            return False
        elif c == "help":
            print(__doc__)
        elif c == "show":
            self.show()
        elif c == "run":
            self.settle(); self.show()
        elif c in ("ucsim", "u"):
            # Raw passthrough to the running ucSim (dump / di / break / step ...).
            raw = line[1:].split(None, 1)
            self._ucsim(raw[1] if len(raw) > 1 else "")
        elif c == "pos":
            self._pos()
        elif c == "axis" and len(parts) == 2 and parts[1].isdigit():
            self.selected = _clamp(int(parts[1]), 0, N_AXES - 1)
            print(f"  select axis {self.selected}")
        elif c == "target" and len(parts) == 3:
            a = int(parts[1]); self.targets[_clamp(a, 0, N_AXES-1)] = _clamp(int(parts[2]))
            self.settle()
        else:
            print("  ? unknown command (:help)")
        return True

    # -- live ucSim access ----------------------------------------------------
    def _ucsim(self, command: str) -> None:
        """Forward a raw command to the running ucSim and print its reply.

        Only works with firmware in the loop (--firmware + a live engine);
        otherwise there is no ucSim to talk to.
        """
        if self.engine is None:
            print("  (no ucSim — start with --firmware and the custom ucsim_51)")
            return
        if not command:
            print("  usage: :ucsim <ucsim-command>   e.g. :ucsim dump iram 0x50 0x55")
            return
        out = self.engine.cmd(command).strip("\n")
        if out:
            print(out)

    def _pos(self) -> None:
        """Show the firmware's own current-position slots (IRAM 0x50..0x55)."""
        if self.engine is None:
            print("  (no ucSim — :pos needs --firmware)")
            return
        fw = self.engine.read_positions()
        tg = self.engine.read_targets()
        print("  firmware IRAM 0x50..0x55 (current) / 0x40..0x45 (target):")
        for a in range(N_AXES):
            cur = fw[a]; tgt = tg[a]
            cs = "??" if cur < 0 else f"{cur:3d}"
            ts = "??" if tgt < 0 else f"{tgt:3d}"
            print(f"    axis {a} {AXES[a]:<12} fw_cur={cs}  fw_tgt={ts}  "
                  f"plant_pot={self.plant.pot[a]:3d}")

    def feed(self, s: str) -> None:
        """Feed a whitespace-free-ish keystroke string (spaces ignored)."""
        for ch in s:
            self.key(ch)
        self.settle()

    def close(self):
        if self.engine:
            self.engine.close()


def _clamp(v: int, lo: int = 0, hi: int = 255) -> int:
    return max(lo, min(hi, v))


def _bar(val: int, width: int = 30) -> str:
    n = int(width * val / 255)
    return "[" + "#" * n + " " * (width - n) + "]"


def _init_history() -> None:
    """Enable up/down-arrow command history for the REPL.

    Importing readline already hooks input() for history + line editing; here we
    also load/save a persistent history file so history survives across runs.
    No-op if readline is unavailable.
    """
    if readline is None:
        return
    histfile = os.path.expanduser("~/.rob3_teachbox_history")
    try:
        readline.read_history_file(histfile)
    except (OSError, FileNotFoundError):
        pass
    readline.set_history_length(1000)
    import atexit
    atexit.register(_save_history, histfile)


def _save_history(histfile: str) -> None:
    if readline is None:
        return
    try:
        readline.write_history_file(histfile)
    except OSError:
        pass


def repl(cli: TeachboxCLI) -> None:
    _init_history()
    hint = "  (↑/↓ = history)" if readline is not None else ""
    print("Teachbox CLI — type keys (0-9 . + - P E N D C R I O), :help, :quit"
          + hint)
    cli.show()
    while True:
        try:
            line = input("tb> ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        if line.startswith(":"):
            if not cli.meta(line):
                break
            continue
        cli.feed(line)
        cli.show()
    cli.close()


def main():
    ap = argparse.ArgumentParser(description="ROB3 Teachbox CLI")
    ap.add_argument("--script", help="run a keystroke string then exit")
    ap.add_argument("--step", type=int, default=6, help="plant step per tick")
    ap.add_argument("--firmware", nargs="?", const="", default=None, metavar="HEXFILE",
                    help="drive the real ROM in ucSim (REQUIRED to run the 8031 "
                         "program; without it the CLI is plant-only). Bare "
                         "--firmware loads the default ROM "
                         "(firmware/hex/M2764A@DIP28.HEX, or the ROB3_HEX env var); "
                         "--firmware <hexfile> loads that ROM instead. Needs the "
                         "custom ucsim_51 (point at it with UCSIM_51=...); slower — "
                         "interactive ucSim over a pty")
    ap.add_argument("--console-port", type=int, default=None, metavar="PORT",
                    help="open the ucSim command console on localhost:PORT so a "
                         "separate terminal can attach with `nc localhost PORT` and "
                         "run dump / di / break / step. Requires --firmware.")
    args = ap.parse_args()
    # --firmware absent -> None; bare --firmware -> "" (default ROM);
    # --firmware PATH -> PATH.
    drive_firmware = args.firmware is not None
    hex_path = args.firmware if args.firmware else None
    if args.console_port and not drive_firmware:
        ap.error("--console-port requires --firmware")
    cli = TeachboxCLI(step=args.step, drive_firmware=drive_firmware,
                      hex_path=hex_path, console_port=args.console_port)
    if args.script:
        cli.feed(args.script)
        cli.show()
        cli.close()
    else:
        repl(cli)


if __name__ == "__main__":
    main()
