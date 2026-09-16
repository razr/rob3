#!/usr/bin/env python3
"""Reproduce ucSim issue #001: a command pipelined after run/step is discarded.

BUG
  While a `run`/`step` executes, the console is FROZEN. If the next command is
  already available on that console (e.g. written in the same block as the
  run/step), ucSim treats the arriving input as a user interrupt: it stops with
  reason resUSER and calls read_line() on the frozen console — CONSUMING that
  line WITHOUT executing it (core/sim.src/sim.cc, ~L258; the stop path is in
  core/cmd.src/newcmd.cc cl_console_base::proc_input). The pipelined command is
  silently lost.

REPRO (no ROM needed)
  Start a free-running `run`, then — while it is running (console frozen) — send
  an interrupting line:
      echo TEST_MSG
  Correct behaviour: the arriving line stops the run AND is then executed, so
  TEST_MSG prints. Buggy behaviour: the line is drained by read_line() on the
  resUSER stop (sim.cc ~L258) and never executed, so TEST_MSG never appears.
  We then confirm the SAME `echo`, sent again once the sim is stopped, DOES
  print — proving it is the pipelining/interrupt path, not the command, at fault.

  Exit 0 = bug reproduced (pipelined echo lost, separate echo works).
  Exit 1 = not reproduced (either both printed, or neither).

USAGE
  UCSIM_51=/path/to/ucsim_51 python3 repro.py
  (falls back to `s51` on PATH; any 8051 sim build works — no ROM required)
"""
import os
import pty
import re
import select
import shutil
import sys
import time

PROMPT = "$"          # ucSim's default prompt tail; we match on the marker echo
MARK = "TEST_MSG"
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


def find_sim():
    for c in (os.environ.get("UCSIM_51"), shutil.which("ucsim_51"),
              shutil.which("s51")):
        if c and os.path.exists(c) and os.access(c, os.X_OK):
            return c
    return None


def read_for(fd, seconds):
    """Drain the pty for `seconds`, return decoded text."""
    buf = ""
    deadline = time.time() + seconds
    while time.time() < deadline:
        r, _, _ = select.select([fd], [], [], 0.05)
        if not r:
            continue
        try:
            data = os.read(fd, 4096)
        except OSError:
            break
        if not data:
            break
        buf += data.decode("latin-1", "replace")
    return ANSI.sub("", buf)


def main():
    sim = find_sim()
    if not sim:
        print("SKIP: no ucsim_51 / s51 found (set UCSIM_51)")
        return 2

    pid, fd = pty.fork()
    if pid == 0:
        os.execv(sim, [sim, "-t", "51", "-X", "11.0592M"])
        os._exit(127)

    read_for(fd, 1.0)  # consume banner

    # --- Case A: interrupt a FREE-RUNNING sim with a pipelined command ---
    # `run` (no stop addr) free-runs until interrupted, so the console is frozen
    # when our next line arrives — the exact resUSER path. We send `run`, wait a
    # beat so it is genuinely running, then write the echo as the interrupting
    # line.
    #
    # DETECTION: the pty echoes our keystrokes, so the STRING "echo <MARK>"
    # always appears once (input echo). If ucSim actually EXECUTES the echo
    # command, MARK appears a SECOND time (command output) AFTER the
    # "Stop at ...: (105) User stopped" line. So:
    #   - buggy  : MARK count == 1 (only the input echo; command discarded)
    #   - fixed  : MARK count >= 2 (input echo + executed-command output)
    os.write(fd, b"run\n")
    time.sleep(0.4)                       # let it enter the frozen free-run
    os.write(fd, b"echo " + MARK.encode() + b"\n")
    outA = read_for(fd, 2.0)
    # Look only AFTER the stop message for the executed-command output.
    after_stop = outA.split("User stopped", 1)[-1] if "User stopped" in outA else outA
    pipelined_ok = MARK in after_stop

    # --- Case B: send the SAME echo as its own write (sim now stopped) ---
    os.write(fd, b"echo " + MARK.encode() + b"\n")
    outB = read_for(fd, 2.0)
    # after the input echo, the command output line should also contain MARK
    standalone_ok = outB.count(MARK) >= 2 or (
        MARK in outB.split("\n", 1)[-1])

    os.write(fd, b"quit\n")
    time.sleep(0.2)
    try:
        os.close(fd)
    except OSError:
        pass

    print(f"pipelined command (interrupting a run) executed?  {pipelined_ok}")
    print(f"standalone command (its own write) executed?      {standalone_ok}")

    if standalone_ok and not pipelined_ok:
        print("BUG REPRODUCED: the pipelined command was discarded unexecuted.")
        return 0
    if pipelined_ok and standalone_ok:
        print("NOT reproduced: pipelined command executed (bug fixed?).")
        return 1
    print("INCONCLUSIVE: standalone echo also failed; check the sim build.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
