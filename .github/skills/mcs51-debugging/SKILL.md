---
name: mcs51-debugging
description: >
  Debugging and simulating Intel 8051/8031 firmware with ucSim (s51), including
  loading ROM images, breakpoints, single-stepping, inspecting IRAM/XDATA/SFRs,
  driving port/pin state, and the golden-byte-match + behavioral test workflow.
  Use when running, stepping, or verifying 8051/8031 firmware in simulation.
metadata:
  globs: ["**/*.a51", "**/*.asm", "**/*.hex", "**/sim/**"]
---

# 8051/8031 Debugging with ucSim (s51)

> Generic ucSim debugging reference. For the instruction set see
> `mcs51-assembly`; for scripting/extending ucSim (batch harness, `cl_hw`
> modules) see `ucsim`. Project-specific gotchas, entry points, build targets,
> and expected-state assertions belong in a project skill.

## Two-layer verification model (a robust way to prove firmware)

1. **Golden byte-match**: assemble a byte-exact `.a51` transcription and `cmp`
   it against the ROM slice. Proves *the listing matches the image*. Print the
   matching SHA-256 hashes as evidence.
2. **Behavioral simulation**: run the **real ROM** in `s51` and assert runtime
   state (SFRs, IRAM, XDATA) against the annotation. Proves *the firmware
   behaves as documented*.

Keep both green. If you edit an annotated region, regenerate the `.a51` so the
golden test still matches the ROM bytes.

## Launch the simulator

```bash
# match -X to the target crystal (affects timer/baud math)
s51 -t 51 -X 11.0592M path/to/rom.hex
```

> **Common gotcha — `@` in a filename crashes s51.** ucSim parses a file
> argument as `filename@memoryspace`, so a name like `IMG@BANK.HEX` is read as
> file `IMG` into a non-existent memory space `BANK.HEX`; `cl_uc::read_file`
> then dereferences a NULL console and **segfaults** (symptom: "banner only, no
> output", core dump under a pty — *not* a curses problem). Always load a copy
> with an `@`-free name.

## Interactive command cheat-sheet

```text
reset                    ; reset the CPU
pc 0x0600                ; set the program counter
dc 0x0600 0x074c         ; disassemble a CODE range
di 0x20 0x2f             ; dump IRAM 0x20..0x2f  (also: dump iram ...)
dx 0x5000 0x5003         ; dump XDATA range
dump sfr 0xa8 0xa8       ; dump an SFR (0xA8 = IE)
break 0x0680             ; set a code breakpoint
run                      ; run until breakpoint/stop
step / next              ; single-step (into / over)
set mem iram 0x22 0x01   ; poke an IRAM byte
set mem sfr 0xb0 0x00    ; poke an SFR (e.g. force P3 bits)
timer add ...            ; timing/clock control
state                    ; show CPU state
quit
```

(Exact spellings vary slightly by ucSim version; `help` lists them.)

## Reading the machine while stopped

- **Register banks** are IRAM bytes: bank 0 = `0x00–0x07`, bank 1 = `0x08–0x0F`,
  etc. `di 0x00 0x1f` shows all four banks. The *active* bank is `PSW.RS1:RS0`
  (`dump sfr 0xd0 0xd0`).
- **Bit flags**: resolve to `(byte,bit)` first (see `mcs51-assembly`). To check
  `TR0`, read `TCON` (`dump sfr 0x88 0x88`) bit 4.
- **DPTR** = `DPH:DPL` (`0x83:0x82`); on boards with high-address decode its high
  byte tells you which device the next `MOVX` targets.

## Injecting hardware stimulus (peripherals aren't modeled)

ucSim models the **MCS-51 core only** — no external I/O chips, ADCs, SRAM, or
address decoders. Firmware that waits on hardware will stall in the sim; you
must inject the stimulus, and label it as **test scaffolding, not a claim about
the silicon**.

- **Simulated port pins idle HIGH.** `cl_port` returns `cell->get() & port_pins`
  with `port_pins = 0xFF`, so an undriven port reads `0xFF`. If real hardware
  idles a line LOW (e.g. a matrix column active only when pressed), a naive sim
  will see a phantom active level. A pin model must drive those bits itself.
- **Interrupt-gated waits.** If the ROM blocks waiting on an external interrupt
  (e.g. a data-ready edge), with no peripheral model that stall is *correct*; to
  proceed, toggle the relevant flag/pin as scaffolding.

```text
# example: get past a wait on an external event by forcing a pin/flag
break 0x0680
run
set mem sfr 0xb0 0x00     ; force P3 bits (edge / level the ROM waits on)
step
```

For true per-read/per-write pin behavior, use a stateful interactive session
with breakpoint injection or a compiled `cl_hw` module — see `ucsim`.

## Confirm entry points from ROM bytes, not labels

`0xFF` ROM padding disassembles as `MOV R7,A`, which shifts instruction
boundaries and produces off-by-one labels. When a breakpoint "never hits,"
re-derive the entry address from the bytes with `dc`.

## Reading failures

- **Banner only / core dump** → the `@` filename bug; use an `@`-free copy.
- **Breakpoint never hits** → wrong entry address (padding shift) or the code
  path is gated on un-injected hardware; verify with `dc` and add stimulus.
- **Phantom active input / instant "hit"** → undriven port reading `0xFF`; the
  pin model must drive the idle level.
- **Golden test FAIL after edits** → you changed bytes; regenerate the `.a51`
  and re-annotate the `.asm`, don't hand-edit the generated `.a51`.

## When to use this skill

- Running/stepping an 8051/8031 ROM or new code in ucSim.
- Adding or fixing behavioral sim tests and pin/peripheral models.
- Diagnosing stalls, phantom inputs, or breakpoints that never fire.
- Verifying SFR/IRAM/XDATA state against an annotation.
