# Issue 001 — a command pipelined after `run`/`step` is discarded unexecuted

**Component:** ucSim command console (`core/cmd.src/newcmd.cc`, `core/sim.src/sim.cc`)
**Verified against:** ucSim 0.9.9 (`~/github/danieldrotos/ucsim`, `s51`/`ucsim_51`)
**Severity:** medium — silent command loss when scripting the simulator

## Summary

While a `run`/`step` executes, ucSim **freezes** the command console. If another
command arrives on that console *while it is frozen* (typical when a driver
writes the next command in the same block, or a script pipes commands), ucSim
treats the arriving input as the "press a key to interrupt the run" signal:

- `cl_console_base::proc_input` (newcmd.cc) reads the line, sees the console is
  frozen, calls `sim->stop(resUSER)`, unfreezes, and **returns without
  interpreting the line it just read** — the command is dropped.
- `cl_sim::stop` (sim.cc, ~L258) additionally drains input on a `resUSER` stop:
  ```c
  if (reason == resUSER && cmd->frozen() && cmd->frozen()->input_avail())
      cmd->frozen()->read_line();          // consumed, never executed
  ```

Net effect: the command that interrupted the run is **silently swallowed**. A
harness that writes `"<run/step>\n<next command>\n"` in one go loses
`<next command>`, and a downstream read for that command's output hangs until
timeout.

This bit the ROB3 teachbox harness: batching `set hardware teachbox … / step N /
set hardware teachbox 0` in one write caused the release (and any sentinel) to
be eaten, so state reads waited forever. See the `rob3-firmware-sim` skill
("Never pipeline a command after a run/step in one console write").

## Root cause

`proc_input`'s frozen branch is an early-out: it stops the sim but never runs
the command in `lbuf`. The intent is "a bare ENTER interrupts a run", but the
code makes **no distinction** between an empty line (just interrupt) and a real
command (interrupt *and* run it).

## Reproduction

No ROM required — pure console behaviour:

```bash
UCSIM_51=/path/to/ucsim_51 python3 repro.py
# exit 0 = bug reproduced ; exit 1 = fixed/not reproduced ; exit 2 = no sim found
```

`repro.py` starts a free-running `run`, then (while frozen) sends
`echo SENTINEL_ABC` as the interrupting line. It distinguishes ucSim's `echo`
**command output** from the pty's **input echo** by checking for the marker only
*after* the `User stopped` line.

- **Buggy:** the marker does NOT appear after the stop (command discarded).
- **Fixed:** the marker appears (the interrupting command executed).

Observed on the unpatched 0.9.9 build:
```
pipelined command (interrupting a run) executed?  False
standalone command (its own write) executed?      True
BUG REPRODUCED: the pipelined command was discarded unexecuted.
```

## Fix

`fix-proc_input-execute-interrupting-command.patch` (against
`src/core/cmd.src/newcmd.cc`): in the frozen branch, after stopping the sim,
**fall through and interpret the command** when the line is non-empty; keep the
old behaviour (just stop) for a bare ENTER / EOF.

```bash
cd ~/github/danieldrotos/ucsim
git apply /path/to/fix-proc_input-execute-interrupting-command.patch
make -C src/core/cmd.src && make -C src/sims/s51.src
```

After the patch:
```
pipelined command (interrupting a run) executed?  True
standalone command (its own write) executed?      True
NOT reproduced: pipelined command executed (bug fixed?).
```

### Verified no regression
- **Bare ENTER still stops a running sim** and the console stays responsive
  (empty-line path unchanged).
- ROB3 `make sim-teachbox-module` still passes.

## Notes / possible upstream refinement

The `resUSER` input-drain in `sim.cc` (~L258) is a second, related consumer.
With this patch the interrupting line is handled in `proc_input`, so the sim.cc
drain generally sees an empty buffer; a tidier upstream fix might remove the
sim.cc drain entirely and let `proc_input` own all console input. Kept minimal
here to avoid changing the stop path for other front-ends (GUI/SIF).
