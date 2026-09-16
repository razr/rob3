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
