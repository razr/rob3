# ROB3 — ucSim hardware modules (loadable plugins)

**Loadable ucSim peripherals** (`cl_hw` subclasses) that attach ROB3 board
hardware to the simulated 8031, so the real firmware talks to modelled devices
instead of relying on hand-injected debugger state.

These are built as external shared objects (`.so`) against the **ucSim plugin
SDK** and loaded at runtime with `loadhw` — they are **no longer compiled into**
`ucsim_51`. The SDK lives in and is installed by the ucSim tree
(`ucsim/sdk/`, `make install`); see that SDK's `README.md`.

> **This checkout's SDK location:** the ucSim source tree is at
> **`~/github/razr/ucsim`**, so the in-tree plugin SDK is
> **`~/github/razr/ucsim/sdk`** (headers under `~/github/razr/ucsim/sdk/include`,
> build fragment `~/github/razr/ucsim/sdk/ucsim-plugin.mk`). It is **not**
> installed to `/usr/local`, so pass `SDK=~/github/razr/ucsim/sdk` when building
> (see "Build these plugins" below).

Each module lives in its own subfolder with its own README:

| Module | Class | Folder | What it does |
| :----- | :---- | :----- | :----------- |
| Teachbox | `cl_teachbox` | [`teachbox/`](teachbox/) | Models the 5x5 key matrix (input on P1 + the 8255 Port B row strobe) so `kbd_scan` reads pressed keys. |
| ADC | `cl_adc` | [`adc/`](adc/) | Models the ADC0808/0809; serves per-channel feedback and **asserts EOC → INT1**, letting the ROM **free-run past the init gate** from a plain `reset; run`. |
| Loopback | `cl_loopback` | [`loopback/`](loopback/) | Models the **RS-232 shorting connector** / MM74C04N #1 conditioning: holds P3.2 (INT0/EMERGENCY-OFF) and P3.4 (T0/poll-gate) HIGH so the ROM leaves the emergency-off handler and reaches the teachbox poll. |
| RXD | `cl_rxd` | [`rxd/`](rxd/) | Drives the **P3.0 (RXD) pin at bit level** (8N1, configurable cycles/bit) so the firmware's software auto-baud measure loop can run. Supplies the pin activity ucSim's byte-level UART omits (see [issue 003](../issues/003-mcs51-uart-does-not-drive-rxd-txd-pins/)). |

Module-specific behaviour, commands, and verification are in each subfolder's
README.

## Prerequisite: install the ucSim SDK (one time)

The loader (`loadhw`/`insmod` + `-rdynamic`/`-ldl`) is compiled into `ucsim_51`,
and the SDK headers are installed, by building/installing ucSim:

```bash
cd <ucsim>            # e.g. ~/github/razr/ucsim
./configure --prefix=/usr/local
make
sudo make install     # installs ucsim_51 AND the plugin SDK
```

This puts the flat SDK headers at `/usr/local/include/ucsim` and the build
fragment at `/usr/local/share/ucsim/sdk/ucsim-plugin.mk`.

## Build these plugins

```bash
make                                   # against the /usr/local installed SDK
make UCSIM_PREFIX=/opt/ucsim           # a different install prefix
make SDK=<ucsim>/sdk                   # against an in-tree (non-installed) SDK
                                       #   (run <ucsim>/sdk/export-headers.sh first)
```

**In this checkout** the SDK is not installed to `/usr/local`, so build against
the in-tree SDK at `~/github/razr/ucsim/sdk` (headers are already exported):

```bash
make -C simulator/ucsim-modules SDK="$HOME/github/razr/ucsim/sdk" all
# from inside simulator/ucsim-modules/:  make SDK="$HOME/github/razr/ucsim/sdk"
```

Produces `loopback/loopback.so`, `adc/adc.so`, `teachbox/teachbox.so`.

## Load and use at runtime

```
ucsim_51 -t 51
> loadhw "teachbox/teachbox.so"        # alias: insmod
load hw: .../teachbox.so loaded (id_string=teachbox)
> set hardware teachbox 4 2            # (module-specific args; see subfolder README)
```

Load each module you need. They are independent.

## Running (gotchas that apply to every module)

- **Filename must not contain `@`.** ucSim parses `name@memory` as a
  file-into-memory spec, so `M2764A@DIP28.HEX` makes it try to load into a
  bogus memory space and **segfaults** (null console in `cl_uc::read_file`).
  Use an `@`-free copy — the Makefile copies to `build/rob3.hex` for you.
  (This was the real cause of the "no output / crash", NOT curses.)
- **Curses is a non-issue.** A curses-linked build and a no-curses build behave
  the same for scripted stdin once the `@` filename is fixed.
- **Don't also compile a module in.** `set hardware <name>` needs a unique
  `id_string`; a module both compiled into `ucsim_51` *and* loaded resolves to
  "no hw". These are loadable-only now.
- **C++ ABI lockstep.** A `.so` only works with a `ucsim_51` built from the same
  headers/compiler/`./configure` options. Rebuild the plugins (and re-install
  the SDK) after a ucSim change.

## How reads/writes dispatch (for maintainers)

`cl_memory_cell::read()` calls **every** registered hw operator in order and
returns the **last** one's value. A runtime-loaded plugin is `add_hw`'d after
the core `cl_port`/XRAM handlers, so its `read()` return is authoritative on the
cells it registers — same "last wins" rule as the old compile-in modules. If a
module must intercept the very first fetch, `loadhw` it before `run`/`reset`.
