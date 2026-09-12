# simulator

Simulation and verification assets for the ROB3 firmware **initialization
sequence** (ROM `0x0600`–`0x074C`). Driven by the `Makefile` in this directory
(`simulator/Makefile`). It reads the ROM image and annotated sources from
`../firmware/`.

For prerequisites see `../firmware/INSTALL.md`; for the full build/test workflow
and the rationale behind the tests see `BUILD.md` (in this directory). This file just
documents what lives in this directory.

## Contents

| Path | Kind | Description |
| :--- | :--- | :---------- |
| `init.a51` | source (generated) | Byte-exact transcription of the ROM init region. Device-under-test for the golden byte-match. Regenerate with `make gen`; do not hand-edit. |
| `gen_init.py` | tool | Regenerates `init.a51` from `../firmware/bin/M2764A@DIP28.BIN`. |
| `tests/sim_init.sh` | test | Behavioral: runs the real ROM in ucSim and asserts init **blocks** at the ADC/INT1 gate (`0x0680`). |
| `tests/sim_run.sh` | test | Behavioral: injects the hardware gates and asserts init **completes** into the main loop (`0x074B`/`0x074D`). |
| `tests/README.md` | doc | Per-test detail: assertions, injected stimuli, standalone run, reading failures. |
| `build/` | generated | Assembler/linker output (`init.rel`, `init.ihx`, `init.bin`), the ROM slice (`rom_init.bin`), and the shell-safe HEX copy (`rob3.hex`). Created by `make`; removed by `make clean`. |

> `init.a51` is committed (it is the DUT and is validated by CI/the golden
> test). Everything under `build/` is disposable and should not be committed.

## How it fits together

```
gen_init.py  --(make gen)-->  init.a51
                                 |
                       (make assemble/link/bin)
                                 v
                       build/init.bin  ==  ../firmware/bin/M2764A@DIP28.BIN[0x0600..]   <- golden (make verify)

../firmware/hex/M2764A@DIP28.HEX --(copied)--> build/rob3.hex --(s51)--> tests/*.sh    <- behavioral (make sim-init / sim-run)
```

## Quick use

From the `simulator/` directory:

```bash
make verify     # golden byte-match only
make sim-init   # behavioral: the ADC-gated stall
make sim-run    # behavioral: run past the gates into the main loop
make test       # all of the above
```

## Regenerating `init.a51`

If the ROM image or the init region bounds change, regenerate:

```bash
make gen        # calls: python3 gen_init.py <rom.bin> init.a51 0x0600 333
```

`gen_init.py` takes `<rom.bin> <out.a51> <org_hex> <length_dec>` and emits an
absolute `CODE` area of raw `.db` bytes so the golden comparison is exact.

## Notes / gotchas

- **Shell-safe HEX.** The shipped image `../firmware/hex/M2764A@DIP28.HEX` has
  an `@` in its name. The Makefile copies it to `build/rob3.hex`; simulator
  commands use that copy. Don't pass the `@` path directly to `s51`.
- **The tests target the init region only.** Main loop, ISRs, serial protocol,
  and the motion interpreter are not covered here.
- **ucSim models the CPU core only** — no 8255 / ADC / SRAM / 74LS138. That is
  why `sim_run.sh` injects stimuli (an ADC-EOC/INT1 toggle and forcing
  `P3.0=0`) to get past the hardware-dependent gates; those injections are test
  scaffolding, documented inline in the script.
