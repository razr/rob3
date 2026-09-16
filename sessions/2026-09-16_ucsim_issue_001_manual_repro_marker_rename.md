# Session: ucSim issue #001 — add a manual repro step, rename the marker

**Date:** 2026-09-16
**Task:** Reviewed `simulator/issues/001-pipelined-command-discarded-on-resuser`
after the question "do I really need a Python snippet to verify it?". Answer:
**no** — Python only exists to make the pty + timing (interrupting line must
arrive while the `run` is frozen) deterministic and self-checking for an
upstream report. It can be verified by hand.

## Changes

- **`README.md`** — added a **"Quick manual check (no Python, no ROM)"**
  reproduction before the scripted one: in an interactive `ucsim_51`, type
  `run`, then type `echo TEST_MSG` while it free-runs. Marker missing after the
  `(105) User stopped` line = buggy; marker printed = fixed. Included the
  standalone-echo sanity check and the bare-ENTER caveat. Kept `repro.py` framed
  as the deterministic, self-checking artifact for upstream.
- **Marker rename** `SENTINEL_ABC` → `TEST_MSG` across `README.md` and
  `repro.py` (9 occurrences, incl. the `MARK` constant). The marker is arbitrary;
  the name was the only thing that changed.

## Verified

- `python3 -m py_compile repro.py` — OK after the rename. [build]
- No `SENTINEL_ABC` occurrences remain.

## Notes

The manual method works because the human supplies the timing (type the second
line only after `run` is already going). Over a plain pipe/heredoc all lines
arrive before the console freezes, which is exactly why the script uses a pty +
`sleep` — documented in the README's scripted section.

## Follow-up: explicit expected-vs-actual behavior

Discussion clarified *why* it's a bug (not just a scriptable quirk): a knowing
script sidesteps it, but the input is dropped **silently**, and the code
conflates two intents. Added an **"Expected vs. actual behavior"** table to the
issue README:

- **bare `ENTER`** while a run/step executes → interrupt the run, nothing else
  (correct today).
- **`<cmd>` + `ENTER`** (non-empty) → should interrupt the run **and then
  execute `<cmd>`**, as if entered at the resulting stopped prompt; today it
  interrupts but **discards `<cmd>` unexecuted** (the bug).

The bare-ENTER behavior is fine and should stay; the defect is only the
non-empty case. Also noted the observed env runs uCsim **0.8.5** on PATH (older
than the 0.9.9 source tree the plugins are built against) — a version mismatch
to keep in mind, plugins are ABI-locked to 0.9.9.
