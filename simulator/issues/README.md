# ucSim issues

Reproducible bug reports for Daniel Drotos' ucSim (`s51` / `ucsim_51`),
discovered while simulating the ROB3 8031 firmware. Each issue folder contains:

- `README.md` — description, root cause (with source references), impact.
- a **reproduction** (script or `.cc` test) that demonstrates the wrong behaviour.
- `*.patch` — a proposed fix against the ucSim source tree, plus a note on how
  the reproduction behaves after applying it.

Verified against the ucSim **0.9.9** checkout used by this project
(`~/github/danieldrotos/ucsim`). Line numbers refer to that tree.

> Scope note: these are genuine ucSim *behaviour* bugs, not the ROB3 "missing
> peripheral" modelling gaps (no 8255/ADC/decoder) — those are handled by the
> `cl_hw` modules under `simulator/ucsim-modules/`.

## Index

| Issue | Title | Status |
| :---- | :---- | :----- |
| [001](001-pipelined-command-discarded-on-resuser/) | Command pipelined after `run`/`step` is discarded unexecuted (resUSER input drain) | **confirmed bug + repro + patch** |
| [002](002-segfault-on-at-in-filename/) | Segfault loading an input file whose name contains `@` | **submitted upstream ([#13](https://github.com/danieldrotos/ucsim/issues/13)) + closed** |

## Investigated but not filed as bugs

These surfaced during the same work but, on checking the source, are **not**
ucSim defects against this tree:

- **`run <N>` "ignores the cycle count".** In fact `run [start [stop]]` takes
  **addresses**, not a cycle count (see `cl_run_cmd::do_work`,
  `core/cmd.src/cmd_exec.cc`, which always calls `sim->start(con, 0)`). So
  `run 8000` sets `PC=0x1F40` and free-runs from there — surprising, but working
  as documented. Use **`step N`** for a bounded advance.
- **Level-triggered INT0 cannot be released by a read-only pin operator.** The
  interrupt controller refreshes `bit_INT0` only on `EV_PORT_CHANGED` events, so
  a `cl_hw` `read()` override does not stop a stuck level interrupt — the pin
  must be driven through the port write path. This is a modeling limitation of
  ucSim's input-pin handling rather than a clear defect; the `loopback` module's
  `tick()` handles it accordingly.

