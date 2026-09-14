# A command pipelined after `run`/`step` is discarded unexecuted

**Component:** command console (`core/cmd.src/newcmd.cc`, `core/sim.src/sim.cc`)
**Version:** ucSim 0.9.9 (`s51` / `ucsim_51`)
**Severity:** medium — silent command loss when scripting the simulator

## Summary

While a `run`/`step` executes, the command console is **frozen**. If another
command arrives on that console *while it is frozen* (e.g. a script pipes the
next command in the same write), ucSim treats the arriving input as the
"press a key to interrupt the run" signal and **drops the command**:

- `cl_console_base::proc_input` (newcmd.cc) reads the line, sees the console is
  frozen, calls `sim->stop(resUSER)`, unfreezes, and returns **without
  interpreting the line it just read**.
- `cl_sim::stop` (sim.cc, ~L258) additionally drains input on a `resUSER` stop:
  ```c
  if (reason == resUSER && cmd->frozen() && cmd->frozen()->input_avail())
      cmd->frozen()->read_line();          // consumed, never executed
  ```

Net effect: the command that interrupted the run is **silently swallowed**. A
harness that writes `"<run/step>\n<next command>\n"` in one go loses
`<next command>`, and any downstream read for its output hangs until timeout.

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
`echo SENTINEL_ABC` as the interrupting line. It distinguishes the `echo`
**command output** from the pty's **input echo** by checking for the marker only
*after* the `User stopped` line.

- **Buggy:** the marker does NOT appear after the stop (command discarded).
- **Fixed:** the marker appears (the interrupting command executed).

Observed on an unpatched 0.9.9 build:
```
pipelined command (interrupting a run) executed?  False
standalone command (its own write) executed?      True
BUG REPRODUCED: the pipelined command was discarded unexecuted.
```

## Suggested fix

`fix-proc_input-execute-interrupting-command.patch` (against
`src/core/cmd.src/newcmd.cc`): in the frozen branch, after stopping the sim,
**fall through and interpret the command** when the line is non-empty; keep the
old behaviour (just stop) for a bare ENTER / EOF.

```bash
git apply /path/to/fix-proc_input-execute-interrupting-command.patch
make -C src/core/cmd.src && make -C src/sims/s51.src
```

After the patch:
```
pipelined command (interrupting a run) executed?  True
standalone command (its own write) executed?      True
NOT reproduced: pipelined command executed (bug fixed?).
```

Bare ENTER still stops a running sim (empty-line path unchanged).

## Notes / possible upstream refinement

The `resUSER` input-drain in `sim.cc` (~L258) is a second, related consumer.
With this patch the interrupting line is handled in `proc_input`, so the sim.cc
drain generally sees an empty buffer; a tidier fix might remove the sim.cc drain
entirely and let `proc_input` own all console input. Kept minimal here to avoid
changing the stop path for other front-ends (GUI/SIF).
