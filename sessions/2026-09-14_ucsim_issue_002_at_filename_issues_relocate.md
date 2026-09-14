# Session: ROB3 — file ucSim bug 002 (@-filename segfault), relocate the issues tree

**Date:** 2026-09-14
**Task:** Commit the pending documentation work: a second, genuine ucSim bug
(the `@`-in-filename segfault) written up and submitted upstream, the local
`issues/` tree moved under `simulator/` to sit next to the sim rig, and the
existing issue-001 write-up polished for public consumption.

Working method: verify against the source before asserting; keep the
[BYTE]/[SIM]/[HW]/[INFER] provenance; commit small and honestly.

## Commit (this session, on `main`, not pushed)

- `9a6b576` docs(issues): file ucSim bug 002 (@-filename segfault); relocate
  `issues/` under `simulator/`

## 1. ucSim bug 002 — segfault on an `@` in the input filename  [SIM]

`s51 file@name.hex` **segfaults** rather than reporting an error. The `@` is
parsed as a `filename@memoryspace` selector, so `FN1@FN2.HEX` is read as file
`FN1` into a memory space named `FN2.HEX`; that space does not exist, and the
error branch in `cl_uc::read_file` (`core/sim.src/uc.cc`) dereferences a **NULL**
`con` (the command-line input-file path loads with `con == NULL`).

- Root cause + minimal fix (guard NULL console, fall back to `stderr`) captured
  in `simulator/issues/002-segfault-on-at-in-filename/README.md`.
- **Submitted upstream as ucSim issue
  [#13](https://github.com/danieldrotos/ucsim/issues/13) and closed.**
- This is the same crash the project already works around by copying
  `firmware/hex/M2764A@DIP28.HEX` to an `@`-free `simulator/build/rob3.hex`.

## 2. Relocate `issues/` -> `simulator/issues/`

The bug reports concern the simulator, so they now live alongside the sim rig.
Git tracked all three files as renames (100% for the patch, ~58–97% for the
prose/repro that also changed).

## 3. Polish issue 001 for publication

- Dropped machine-specific paths (e.g. `~/github/danieldrotos/ucsim`) and
  tightened the prose.
- Made `repro.py` path-agnostic — it now finds the simulator via `$UCSIM_51`
  and `PATH` only, no hardcoded home-dir fallback.
- Reclassified three items in the issues index as **investigated but not a bug**
  (the `run N` address-vs-count footgun, the `@`-filename guard some checkouts
  already carry, and the level-triggered INT0 modeling limitation).

## 4. Cross-links

Referenced issue 002 (and the closed #13) from:
- `simulator/issues/README.md` (index table)
- `.kiro/skills/rob3-firmware-sim/SKILL.md`
- `.kiro/steering/rob3-lessons-learned.md`

## Provenance

- [SIM] The 002 crash and its NULL-`con` root cause are verified against the
  ucSim 0.9.9 source and reproduced; filed and closed upstream as #13.
- Everything else here is documentation movement/polish — no firmware or ROM
  claims changed.

## Next

- Push `main` when ready (several session commits are still local).
- If/when a fresh ucSim is built for CI, confirm whether the tree already
  carries the 002 guard and drop the workaround note accordingly.
