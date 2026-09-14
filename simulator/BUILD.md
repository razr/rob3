# BUILD

How to assemble, verify, and test the ROB3 firmware **initialization sequence**
(reset → main-loop entry, ROM `0x0600`–`0x074C`).

This build/verify/simulate rig lives in the top-level `simulator/` directory and
reads the ROM image and annotated sources from `../firmware/`. For toolchain
prerequisites see [`../firmware/INSTALL.md`](../firmware/INSTALL.md).

## TL;DR

```bash
cd simulator
make            # assemble the init and prove it byte-matches the real ROM
make test       # golden byte-match + simulator behavioral tests
```

## What this build does

The annotated disassembly (`../firmware/src/annotated/main.annotated.asm`)
documents the init code at the instruction level. To prove that documentation is
faithful — and that the firmware actually behaves as annotated — the build has
two independent halves:

1. **Golden byte-match (A).** `init.a51` is a byte-exact transcription of
   the ROM init region. The build assembles it and compares the result to the
   real ROM bytes. If they differ, the transcription is wrong and the build
   fails. This proves *the listing matches the firmware image*.

2. **Simulator behavioral tests (B).** The **real ROM**
   (`../firmware/hex/M2764A@DIP28.HEX`) is run in ucSim (`s51`) and its runtime
   state is checked against the annotation's claims. This proves *the firmware
   behaves as documented*.

The two halves share one `Makefile`.

## Layout

```
rob3/
├── firmware/
│   ├── INSTALL.md               # toolchain prerequisites
│   ├── bin/M2764A@DIP28.BIN     # ROM image (binary)  — golden reference
│   ├── hex/M2764A@DIP28.HEX     # ROM image (Intel HEX) — loaded by the simulator
│   └── src/
│       ├── main.asm             # raw disasm51 output
│       └── annotated/
│           ├── main.annotated.asm      # human-annotated init listing
│           └── teachbox.annotated.asm  # human-annotated keypad scanner
└── simulator/
    ├── Makefile                 # all build/test targets
    ├── BUILD.md                 # this file
    ├── init.a51                 # byte-exact init transcription (device-under-test)
    ├── teachbox_scan.a51        # byte-exact keypad-scanner transcription
    ├── gen_init.py              # regenerates the .a51 transcriptions from the ROM
    ├── build/                   # (generated) .rel/.ihx/.bin, rob3.hex, sim inputs
    ├── ucsim-modules/            # loadable cl_hw plugins (teachbox/, adc/, loopback/)
    └── tests/
        ├── sim_init.sh          # behavioral: init blocks at the ADC/INT1 gate
        └── sim_run.sh           # behavioral: init completes into the main loop
```

## Make targets

| Target | Description |
| :----- | :---------- |
| `make` / `make all` | Assemble init and run the golden byte-match (`verify`). |
| `make verify` | **Golden test.** `cmp` assembled regions vs ROM slice; prints SHA-256. |
| `make sim-init` | Behavioral test: init stalls at `0x0680` (ADC EOC/INT1 wait). |
| `make sim-run` | Behavioral test: inject the gates, run to end of init `0x074B`. |
| `make sim-teachbox` | Behavioral test: keypad scanner decode (P1 injection). |
| `make sim-teachbox-module` | Behavioral test: compiled teachbox cl_hw module (opt-in). |
| `make test` | `verify` + all behavioral tests. |
| `make gen` | Regenerate the `.a51` transcriptions from the ROM (byte-exact). |
| `make clean` | Remove `build/`. |
| `make help` | List targets. |

## Toolchain pipeline

```
init.a51 --sdas8051--> init.rel --sdld--> init.ihx --objcopy--> init.bin
                                                                   |
                                cmp against ../firmware ROM[0x0600..] |
                                                                   v
                                                        GOLDEN PASS/FAIL
```

Overridable variables (e.g. macOS `gobjcopy`):

```bash
make OBJCOPY=gobjcopy verify
make SIM="$(command -v s51)" test
```

## Expected output

```
$ make test
...
PASS  golden[init]: assembled == ROM[0x0600..] (333 bytes)
<sha256>  ./build/init.bin
<sha256>  ./build/rom_init.bin
PASS  init blocks at 0x0680 (JB 0x22.0 -> waits for ADC EOC/INT1)
PASS  SP = 0x31
PASS  IE = 0x84 (EA + EX1)
PASS  IRAM 0x22 = 0x01 (axis mask bit0 set)
PASS  IRAM 0x47 = 0xFF (output shadow latch)
sim_init: OK
PASS  init completed (reached final instruction 0x074B, main loop 0x074D next)
PASS  axis speed table 0x48..0x4D = 01 x6
PASS  IE = 0x07 (EX0+ET0+EX1; fixed-baud path, pre-SETB-EA)
sim_run: OK
ALL TESTS PASSED
```

## What the tests assert (and why)

### Golden (`verify`)
The assembled `init.a51` must be **byte-identical** to
`../firmware/bin/M2764A@DIP28.BIN` over `0x0600`–`0x074C` (333 bytes). Matching
SHA-256 hashes are printed as proof.

### Behavioral (`sim-init`, `sim-run`)
These run the real ROM in ucSim and check runtime state against the annotation.
In brief:

- **`sim-init`** — from reset, init **blocks at `0x0680`** waiting for the ADC
  end-of-conversion (`EOC → INT1`). On a *stock* `s51` with no ADC model this
  stall is the expected, correct behavior.
- **`sim-run`** — injects the missing hardware stimuli (an ADC-EOC/INT1 toggle
  and forcing `P3.0=0` for the fixed-baud path) so init runs to completion at
  `0x074B` with the axis speed table seeded.

The injected stimuli are **test scaffolding**, not claims about the silicon.
The `cl_adc` loadable plugin in `ucsim-modules/adc/` replaces this scaffolding
with a real ADC/EOC model so the ROM can free-run; see that module's README.
Full per-test detail — every assertion, the injection mechanics, how to run a
test standalone, and how to read failures — lives in
**[`tests/README.md`](tests/README.md)**.

## Scope & limitations

- The golden transcription and tests cover the **init region**
  (`0x0600`–`0x074C`) and the **keypad scanner** (`0x0C00`–`0x0C6B`), matching
  the annotated listings. The main loop, servo ISR, serial protocol, and motion
  interpreter are not yet transcribed.
- `init.a51` uses raw `.db` bytes (generated by `make gen`) so the golden
  match is exact. Mnemonic-level documentation lives in
  `../firmware/src/annotated/main.annotated.asm`.
- Stock ucSim models the MCS-51 core only; external peripherals (8255, ADC,
  SRAM, 74LS138 decode) are **not** modeled, which is why the behavioral tests
  are structured around the hardware-dependent gates. The `ucsim-modules/`
  peripherals (teachbox, adc, loopback) add those models as loadable plugins
  (`loadhw`) to a ucSim built with the plugin loader.

## Manual simulator poking

Load the ROM and explore interactively:

```bash
cd simulator
cp ../firmware/hex/M2764A@DIP28.HEX build/rob3.hex
s51 -t 51 -X 11.0592M build/rob3.hex
# then, at the uCsim prompt:
#   reset
#   pc 0x0600
#   dc 0x0600 0x074c      ; disassemble init
#   break 0x0680          ; the ADC/INT1 gate
#   run
#   dump sfr 0xa8 0xa8    ; IE
#   dump iram 0x20 0x2f
#   quit
```
