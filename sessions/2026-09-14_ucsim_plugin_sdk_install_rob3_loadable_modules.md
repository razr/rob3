# 2026-09-14 — ucSim plugin SDK becomes part of ucSim; ROB3 modules → loadable plugins

## Goal

Make the loadable-hardware-plugin **SDK** a first-class part of ucSim (installed
by `make install`), so any external project can build `cl_hw` `.so` modules
against the *installed* SDK — with no ucSim source checkout on its include path.
Then convert the three ROB3 peripherals (`loopback`, `adc`, `teachbox`) from
compile-in modules to loadable plugins built against that SDK, and delete the
ROB3-local SDK prototype.

Prior state (from the preceding session): the runtime **loader**
(`loadhw`/`insmod` + `-rdynamic`/`-ldl`) was already wired into and committed in
the ucSim checkout (`~/github/razr/ucsim`, branch `feature/loadable-hw-plugins`,
commit `6396c08`). The SDK itself only existed as a prototype inside ROB3
(`simulator/ucsim-plugin-sdk/`) whose `export-sdk.sh` scraped headers out of a
ucSim checkout on demand — i.e. ucSim had no knowledge of the SDK.

## Decisions

1. **SDK lives in the ucSim tree** at `ucsim/sdk/` (top level). [done]
2. **Remove the ROB3 copy** of the SDK; ROB3 becomes a pure consumer. [done]
3. **ROB3 modules find the SDK via install** (option 3): build against the
   installed SDK at `$(prefix)`, not a relative/env path. [done]
4. **Flat header layout** (option 2): the four ucSim header dirs a plugin needs
   (`core/sim.src`, `core/cmd.src`, `core/utils.src`, `sims/s51.src`) have **no
   basename collisions** (verified — 80 headers, 0 dups), so export them into a
   single flat dir and build plugins with **one** `-I`. [done]
5. **Loader validation left as-is** for now (see "Loader trust model" below).

## What was built

### ucSim (`~/github/razr/ucsim`, branch `feature/loadable-hw-plugins`)

New `sdk/`:
- `ucsim_hw_plugin.h` — contract header: `extern "C" ucsim_hw_abi()` +
  `ucsim_hw_create()`, and the `UCSIM_HW_PLUGIN(CLASS)` macro. `UCSIM_HW_ABI 1`.
- `export-headers.sh` — flat-copies the needed core headers (+ contract header)
  into `sdk/include/` (81 headers). Auto-detects the surrounding checkout (`..`).
- `install.sh` — installs flat headers → `$(includedir)/ucsim`, and
  `ucsim-plugin.mk`/`README.md`/`example/` → `$(datadir)/ucsim/sdk`. DESTDIR/
  prefix/includedir/datadir aware.
- `ucsim-plugin.mk` — build fragment; **auto-detects** installed vs in-tree
  layout (checks for the installed contract header next to itself) and emits the
  single `-I`. Exposes `$(UCSIM_PLUGIN_INCLUDES)` and `$(UCSIM_PLUGIN_LINK)`.
- `example/` — `demo_hw.cc` + Makefile (builds in both layouts).
- `core-additions/` — loader provenance preserved: `hwload.cc`, `hwloadcl.h`,
  `WIRING.md` (the applied loader lived only as the built result before).
- `README.md`.

Build/install hook:
- `Makefile.in` — `make install` now also runs `install_sdk` (and a matching
  `uninstall_sdk`); prefix vars added via `@...@`. Regenerated the top
  `Makefile` with `./config.status Makefile`.
- `.gitignore` — new; keeps build artifacts (`*.o/*.a/*.so`, autotools-generated
  `Makefile`/`common.mk`/`ddconfig.h`/lexer+parser, built `ucsim_*`/`s*`,
  `sdk/include/`, `sdk/example/*.so`) out of git.

Commit: `285c0a6b feat(sdk): installable hardware-plugin SDK (make install)`.

### ROB3 (`~/github/razr/rob3`, branch `main`)

- `simulator/ucsim-modules/{loopback,adc,teachbox}/*.cc` — each now
  `#include "ucsim_hw_plugin.h"` and ends with `UCSIM_HW_PLUGIN(cl_*)`; the
  peripheral logic is unchanged. Header/notes updated from "compile-time module"
  to "loadable plugin".
- `simulator/ucsim-modules/Makefile` — new; builds all three `.so`s against the
  installed SDK (`UCSIM_PREFIX ?= /usr/local`, or `SDK=<ucsim>/sdk` in-tree).
- `simulator/ucsim-modules/README.md` — rewritten for the loadable-plugin flow
  (install ucSim SDK → `make` → `loadhw`).
- `simulator/ucsim-modules/loopback/README.md`, `simulator/BUILD.md` — stale
  compile-in/`mk_hw_elements`/`objs.mk` instructions replaced.
- Deleted `simulator/ucsim-plugin-sdk/` (SDK + loader provenance now in ucSim).
- `.gitignore` — ignore `simulator/ucsim-modules/**/*.so`.

Commit: (see ROB3 git log for this session).

## Verification [SIM]

- Flat export → single-`-I` build of `example/demo_hw.cc` works (only benign
  upstream `-Woverloaded-virtual` warnings from ucSim's own headers).
- `loadhw "demo_hw.so"` in the freshly built `ucsim_51`
  (`src/sims/s51.src/ucsim_51`) loads it (`id_string=demohw`) and
  `set hardware demohw ping` reaches its `set_cmd`.
- `make install_sdk DESTDIR=/tmp/sdk-stage` produces the correct tree: 81 flat
  headers in `include/ucsim/`, fragment+example+README in `share/ucsim/sdk/`.
- The example builds against the **staged installed** SDK via the fragment's
  auto-detection (`-I/tmp/sdk-stage/usr/local/include/ucsim`), and in-tree.
- All three ROB3 plugins compile against the installed SDK and each loads into
  `ucsim_51` with the right `id_string` (`loopback`/`adc`/`teachbox`);
  `set hardware <name>` resolves.
- `conf` lists all hw elements incl. loaded plugins: 13 core → 15 after loading
  `adc`+`teachbox` (appended last, shown `on`).

## Notes / gotchas

- **`conf` is the "list all hw" command** (on/off + `id_string[id]`), and it
  includes runtime-loaded plugins. `info hardware <hw>` is per-module detail,
  not a list. Loaded modules appear **last** (add_hw appends → their `read()`
  wins on cells they register).
- **The system `ucsim_51` at `/usr/bin` is an OLD build without the loader** —
  `loadhw` there errors "no hw". The working binary is
  `~/github/razr/ucsim/src/sims/s51.src/ucsim_51`. Run `sudo make install` in
  ucSim to replace the system binary and install the SDK.
- **`loadhw` path must be quoted/absolute** and `@`-free (the usual ucSim
  `file@memspace` parsing).

## Loader trust model (reviewed, left as-is by decision)

`loadhw` validation is structural/version only, NOT a security or ABI-safety
guarantee:
1. `dlopen(RTLD_NOW|RTLD_GLOBAL)` — unresolved core symbols fail up front.
2. `dlsym` both `ucsim_hw_abi` + `ucsim_hw_create` must exist.
3. `ucsim_hw_abi()` must equal the core's `UCSIM_HW_ABI` (a single int gate).
4. factory must return non-NULL. Then `add_hw()` + `init()`.

Not checked: authenticity/trust (it runs arbitrary native code, like `insmod`);
subtle C++ ABI drift (the ABI int is hand-maintained AND duplicated in
`hwload.cc` vs the SDK header — bump both); `id_string` uniqueness at load time
(collision only surfaces later as "no hw" from `set hardware`); `init()` return
value (ignored). Possible future hardening (not done): share the ABI constant
from one header; check id uniqueness before add_hw; honor init() and roll back;
record the dlopen handle for an `unload`/`rmmod`.

## Follow-ups

- `sudo make install` ucSim so the system `ucsim_51` has the loader + SDK.
- Point the ROB3 sim harness/tests at the loader-enabled `ucsim_51` and switch
  the opt-in module tests to `loadhw` the `.so`s instead of expecting compiled-in
  elements.
- Consider upstreaming the loader + SDK to Daniel Drotos' ucSim (independent of
  ROB3); move the `common.mk` edits into the `*.in` inputs (already are) and the
  install hook is in `Makefile.in`.
