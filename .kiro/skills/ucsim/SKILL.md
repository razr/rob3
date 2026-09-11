---
name: ucsim
description: >
  Using and extending ucSim (s51 / ucsim_51), Daniel Drotos' MCS-51 simulator:
  the command language, scripted/batch and interactive driving, the -I SIF and
  -S UART-socket interfaces, and writing a compile-time cl_hw peripheral module
  (register_cell on SFR/XRAM, read/write/set_cmd, mk_hw_elements registration)
  then building a custom ucsim_51. Use when running, scripting, or adding
  hardware models to an 8051/8031 simulation.
metadata:
  globs: ["**/sim/**", "**/*.cc", "**/*.hh", "**/*cl.h", "**/*.hex"]
---

# ucSim: Using & Extending (s51 / ucsim_51)

> Generic ucSim reference — both *driving* it (scripts, a Python batch harness)
> and *modifying* it (a compiled `cl_hw` peripheral). For the command
> cheat-sheet and debug workflow see `mcs51-debugging`; for the instruction set
> see `mcs51-assembly`. Project-specific memory maps, ROM images, peripheral
> models, and calibration belong in a project skill.

## Part 1 — Using ucSim

### Invocation

```bash
s51 -t 51 -X 11.0592M path/to/rom.hex          # match -X to the target crystal
```

- `-t <cpu>`: CPU type (`51`). `-X <freq>`: crystal (affects timer/baud/timing).
- **`@` in the filename crashes s51** (parsed as `file@memoryspace` → NULL
  console segfault). Always load an `@`-free copy. See `mcs51-debugging`.

### Batch vs interactive (choose deliberately)

- **Batch/scripted** (deterministic, CI-friendly): feed a newline-separated
  command script on stdin, parse the full output once. Cannot make mid-run
  decisions (it can't read state to decide when to stop).
- **Interactive** (stateful, adaptive): a persistent session that reads state
  mid-run and reacts (e.g. inject a port value only on a matching condition).
  Needed when the number of steps depends on runtime state (a scan that exits
  early on a hit). Use `s51 -p <prompt>` to get a reliable per-command sync
  marker.

### Batch harness pattern (Python)

Run `s51` once per "transaction" and parse `dump`/`Stop at` output. State that
must persist across transactions is re-seeded at the top of each script by the
caller (shadow the RAM, re-apply it every tick). Slower but robust.

```python
class UCSimBatch:
    def __init__(self, hex_path, cpu="51", xtal="11.0592M", sim="s51"):
        ...
    def run(self, script, timeout=20.0) -> str:
        # auto-append `quit`, strip ucSim ANSI \x1b[0K sequences, return stdout
        ...
    @staticmethod
    def parse_dump_byte(out, addr) -> int: ...   # first data byte, or -1
    @staticmethod
    def parse_dump_row(out, addr, n) -> list: ...
    @staticmethod
    def parse_stopped_pc(out): ...               # last "Stop at 0x..." -> int

sim = UCSimBatch("rom.hex")
out = sim.run("""reset
set mem xram 0x5900 0x40    ; seed a memory-mapped input
pc 0x00d5
step 3
dump iram 0x58 0x58
""")
val = UCSimBatch.parse_dump_byte(out, 0x58)
```

### XRAM *is* the peripheral window (no interception needed for simple models)

ucSim `s51` exposes writable XRAM at any external-data address, so a
memory-mapped peripheral can often be modelled by just seeding/reading XRAM at
the board's device addresses:

```text
set mem xram 0x5900 0xAB     ; seed a device register
dump xram 0x5900             ; reads back 0xAB
```

So a closed loop is: write a modelled input to the device's XRAM address → let
the firmware's ISR run → read the commanded output bits from another XRAM
address → integrate → repeat. (Whether this suffices depends on how stateful the
firmware's algorithm is — a servo loop that accumulates state across ISR calls
needs the full context, not a single-pass seed.)

### Two other attach interfaces (know their limits)

- **`-I` Simulator Interface (SIF):** `-I if=sfr[0x90],in=FILE,out=FILE`
  *does* intercept port reads, but in older ucSim (e.g. 0.8.5) the `in=` file is
  a coarse byte-stream — it does **not** deliver programmable per-read values
  (the port reads a fixed byte), and there is **no socket** option for `-I`. Not
  suitable for a programmable per-read GPIO device on that build.
- **`-S` UART socket:** `-S ...,port=` exposes the *serial port* over a socket
  (good for an RS232 protocol), but only the UART — not arbitrary pins.

When you need per-read programmable pins, use a stateful interactive session with
breakpoint injection, or — better — a compiled `cl_hw` module (Part 2).

## Part 2 — Extending ucSim (compile-time `cl_hw` peripheral)

When a device needs true per-read/per-write behavior, subclass `cl_hw` and
compile it into a custom `ucsim_51`.

### Obtaining and building ucSim from source

The stock `s51` binary cannot host a custom `cl_hw` module — you need the ucSim
**source tree** to compile one in. Clone Daniel Drotos' repository if you don't
already have it:

```bash
# reuse an existing checkout if present, else clone
UCSIM=~/github/danieldrotos/ucsim
[ -d "$UCSIM" ] || git clone https://github.com/danieldrotos/ucsim "$UCSIM"

cd "$UCSIM"
./configure
make                       # full build; or: make -C src/sims/s51.src
# the 8051 simulator lands at src/sims/s51.src/ucsim_51
```

- A plain build already gives you `ucsim_51` (and `s51`); you only need to
  rebuild after adding a module (below).
- Note two binaries: the packaged **`s51`** (often an older release, e.g. 0.8.5)
  vs. the **`ucsim_51`** you build from source. The `cl_hw` API below tracks the
  source (~0.9.9); check `src/sims/s51.src/hwcl.h` if a signature differs.

### Anatomy of a `cl_hw` peripheral

Header: subclass `cl_hw`, declare state + the overrides.

```cpp
#include "stypes.h"
#include "uccl.h"
#include "hwcl.h"
#include "newcmdcl.h"

class cl_mydev: public cl_hw {
public:
  int some_state;                  // device state
  class cl_memory_cell *cell_p1, *cell_x;
public:
  cl_mydev(class cl_uc *auc);
  virtual int  init(void);
  virtual t_mem read (class cl_memory_cell *cell);
  virtual void  write(class cl_memory_cell *cell, t_mem *val);
  virtual bool  set_cmd(class cl_cmdline *cmdline, class cl_console_base *con);
  virtual void  print_info(class cl_console_base *con);
};
```

Implementation:

1. **Constructor** — name the hw and pick a category:
   ```cpp
   cl_mydev::cl_mydev(class cl_uc *auc)
     : cl_hw(auc, HW_GPIO, 0, "mydev") { /* init state */ }
   ```
2. **`init()`** — grab the address spaces and `register_cell` the cells you want
   to intercept. Registering a cell routes its reads/writes through your
   `read()`/`write()`:
   ```cpp
   class cl_address_space *sfr  = uc->address_space(MEM_SFR_ID);
   class cl_address_space *xram = uc->address_space(MEM_XRAM_ID);
   cell_p1 = register_cell(sfr,  P1);       // P1 = 0x90 (from regs51.h)
   cell_x  = register_cell(xram, 0x5100);   // some XDATA device register
   ```
3. **`read(cell)`** — return the value the CPU should see. Compare `cell` to your
   registered cells to know which is being read:
   ```cpp
   if (cell == cell_p1) {
     t_mem v = cell->get() & 0x1f;          // keep low bits, override the rest
     /* set device-driven bits based on state */
     return v;
   }
   return cell->get();
   ```
4. **`write(cell,val)`** — observe CPU writes, then commit: `cell->set(*val);`
5. **`set_cmd()`** — parse `set hardware <name> ...` args with
   `cmdline->syntax_match(uc, NUMBER NUMBER)`; report via `con->dd_printf`.
6. **`print_info()`** — what `info hardware` shows.

### Registration + build

1. Copy your `.cc`/`cl.h` into `<ucsim>/src/sims/s51.src/`.
2. Add the `.o` to `OBJECTS` in `src/sims/s51.src/objs.mk`.
3. In `src/sims/s51.src/uc51.cc`: `#include "mydevcl.h"`, and at the end of
   `cl_51core::mk_hw_elements()`:
   ```cpp
   { class cl_hw *d = new cl_mydev(this); add_hw(d); d->init(); }
   ```
4. Build:
   ```bash
   cd "$UCSIM" && ./configure && make -C src/sims/s51.src   # -> ucsim_51
   ```
   The `cl_hw` API here matches Daniel Drotos' ucSim ~0.9.9.

### Dispatch semantics (critical for correctness)

`cl_memory_cell::read()` calls **every** registered hw operator in order and
returns the **last** one's value; `add_hw` appends. Register your hw *after* the
built-in `cl_port` for that SFR so your `read()` return wins. This is how you
make a pin idle LOW when the default `cl_port` would idle it HIGH (`port_pins`
masks to `0xFF`).

### Running the custom module

```bash
printf 'set hardware mydev 0 1\nreset\npc 0x0c00\n...\nquit\n' \
  | ucsim_51 -t 51 -X 11.0592M rom.hex
```

### Calibrating a model to the firmware (don't guess)

A model's decode must match what the firmware actually drives. Procedure:
1. Break at the firmware's device-write instruction and read the value it drives
   for each state (e.g. each row of a scan).
2. Map those exact bytes → your model's logical states.
3. Update the model's decode to that mapping, and verify end-to-end against a
   behavioral test.

## Choosing an approach (decision guide)

| Need | Approach |
| :--- | :------- |
| Read/seed a memory-mapped value in XDATA | plain `set mem xram` / `dump xram` (batch) |
| Deterministic assertion in CI | batch script + a `UCSimBatch`-style parser |
| Value depends on mid-run state / early-exit scans | interactive session (`s51 -p`) w/ breakpoint injection |
| True per-read/per-write pin behavior, reusable | compiled `cl_hw` module → `ucsim_51` |
| Serial/RS232 protocol over a socket | `-S ...,port=` UART socket |

## When to use this skill

- Driving `s51` from scripts or a Python batch harness, or interactively.
- Modelling memory-mapped peripherals via XRAM, or deciding it needs a real
  module.
- Writing/registering/building a `cl_hw` peripheral into a custom `ucsim_51`.
- Calibrating a peripheral model to the firmware's actual bus writes.
