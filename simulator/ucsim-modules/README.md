# ROB3 — ucSim hardware modules

**Compile-time ucSim peripherals** (`cl_hw` subclasses) that attach ROB3 board
hardware to the simulated 8031, so the real firmware talks to modelled devices
instead of relying on hand-injected debugger state.

Each module lives in its own subfolder with its own README:

| Module | Class | Folder | What it does |
| :----- | :---- | :----- | :----------- |
| Teachbox | `cl_teachbox` | [`teachbox/`](teachbox/) | Models the 5x5 key matrix (input on P1 + the 8255 Port B row strobe) so `kbd_scan` reads pressed keys. |
| ADC | `cl_adc` | [`adc/`](adc/) | Models the ADC0808/0809; serves per-channel feedback and **asserts EOC → INT1**, letting the ROM **free-run past the init gate** from a plain `reset; run`. |

Build instructions (shared) are below; module-specific behaviour, commands, and
verification are in each subfolder's README.

## Building a custom `ucsim_51` with these modules

Requires the ucSim source (this project was developed against Daniel Drotos'
ucSim **0.9.9**, e.g. a checkout at `~/github/danieldrotos/ucsim`).

1. Copy the module sources into the 8051 sim source tree:
   ```bash
   cp teachbox/teachbox.cc teachbox/teachboxcl.h  <ucsim>/src/sims/s51.src/
   cp adc/adc.cc           adc/adccl.h            <ucsim>/src/sims/s51.src/
   ```
2. Add the objects to the build — in `src/sims/s51.src/objs.mk`, append
   `teachbox.o adc.o` to the `OBJECTS` list.
3. Register the hw — in `src/sims/s51.src/uc51.cc`:
   - add the includes near the other hw includes:
     ```cpp
     #include "teachboxcl.h"
     #include "adccl.h"
     ```
   - at the end of `cl_51core::mk_hw_elements()` (after the interrupt hw):
     ```cpp
     { class cl_hw *tb  = new cl_teachbox(this); add_hw(tb);  tb->init();  }
     { class cl_hw *adc = new cl_adc(this);      add_hw(adc); adc->init(); }
     ```
   (Add only the module(s) you want; each is independent.)
4. Configure and build:
   ```bash
   cd <ucsim> && ./configure && make -C src/sims/s51.src
   ```
   Produces `src/sims/s51.src/ucsim_51`.

## Running (gotchas that apply to every module)

- **Filename must not contain `@`.** ucSim parses `name@memory` as a
  file-into-memory spec, so `M2764A@DIP28.HEX` makes it try to load into a
  bogus memory space and **segfaults** (null console in `cl_uc::read_file`).
  Use an `@`-free copy — the Makefile copies to `build/rob3.hex` for you.
  (This was the real cause of the "no output / crash", NOT curses.)
- **Curses is a non-issue.** A curses-linked build and a no-curses build behave
  the same for scripted stdin once the `@` filename is fixed.
- **Opt-in tests.** The module tests (`make sim-teachbox-module`, `make sim-adc`)
  need this custom `ucsim_51`. Point them at it with
  `UCSIM_51=/path/to/ucsim_51` (or put it first on `PATH`); they **skip**
  cleanly if it isn't found, so a stock-`s51` `make test` still passes.

## How reads/writes dispatch (for maintainers)

`cl_memory_cell::read()` calls **every** registered hw operator in order and
returns the **last** one's value; `add_hw` appends, so the hw registered *last*
wins. Both modules are added after the core `cl_port`/XRAM handlers, so their
`read()` returns are authoritative on the cells they register.
