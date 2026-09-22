# INSTALL

Toolchain prerequisites for assembling and simulating the ROB3 firmware
(see [`../simulator/BUILD.md`](../simulator/BUILD.md) for how to actually build
and test).

## What you need

| Tool | Provides | Used for |
| :--- | :------- | :------- |
| `sdas8051` | SDCC 8051 assembler | assemble the annotated source (`firmware/src/annotated/`) |
| `sdld` | SDCC linker (ASlink) | link `.rel` → Intel HEX |
| `objcopy` | GNU binutils | Intel HEX → raw binary |
| `s51` | ucSim 8051 simulator | run the ROM, behavioral tests |
| `make` | GNU Make | drive the build/test targets |

`sdas8051` and `sdld` ship in the **sdcc** package; `s51` ships in the
**ucsim** package.

### Optional (only to regenerate an annotated region from the ROM)

| Tool | Provides | Used for |
| :--- | :------- | :------- |
| `disasm51` | 8051 disassembler (PyPI) | re-disassemble the ROM; drives `d51_to_sdas.py` |

Install in a venv (the environment is externally-managed):
`python3 -m venv /tmp/d51venv && /tmp/d51venv/bin/pip install disasm51`.
Not needed for a normal `make verify` / `make test` — the annotated `.asm`
regions are already committed and assemble as-is.

## Verified environment

These docs were validated on:

- Ubuntu 24.04.4 LTS
- `sdcc` 4.2.0+dfsg-1  (SDCC 4.2.0, provides `sdas8051`, `sdld`)
- `ucsim` 0.8.5-1  (provides `s51`)
- `binutils` 2.42  (provides `objcopy`)
- GNU Make 4.3, Python 3.12

## Install

### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y sdcc ucsim binutils make python3
```

> Note: on some Debian/Ubuntu releases the simulators are split into a
> separate `sdcc-ucsim` package. If `s51` is missing after installing `sdcc`,
> also install `ucsim` (or `sdcc-ucsim`):
> ```bash
> sudo apt-get install -y ucsim || sudo apt-get install -y sdcc-ucsim
> ```

### Fedora / RHEL

```bash
sudo dnf install -y sdcc binutils make python3
# ucSim (s51) is bundled with the sdcc package on Fedora.
```

### macOS (Homebrew)

```bash
brew install sdcc binutils make python3
# Homebrew's sdcc includes the ucSim simulators (s51).
# Homebrew binutils installs as gobjcopy; either symlink it to objcopy on
# PATH or edit OBJCOPY in the Makefile (see ../simulator/BUILD.md).
```

### From source (SDCC + ucSim)

If your distro lacks packages, build SDCC (which includes ucSim) from
<http://sdcc.sourceforge.net/>. Ensure `sdas8051`, `sdld`, and `s51` land on
your `PATH`.

## Verify the installation

```bash
sdas8051              # prints usage/banner
sdld -v               # ASlink banner
s51 -t 51 </dev/null  # ucSim banner, then exits
objcopy --version
make --version
python3 --version
```

All five must resolve on your `PATH`. Then proceed to
[`../simulator/BUILD.md`](../simulator/BUILD.md).

## Troubleshooting

- **`s51: command not found`** — install `ucsim` (or `sdcc-ucsim`). It is not
  always pulled in by `sdcc`.
- **`objcopy: command not found` (macOS)** — Homebrew names it `gobjcopy`.
  Symlink it or set `OBJCOPY=gobjcopy` when invoking `make` (see
  ../simulator/BUILD.md).
- **Filename with `@`** — the shipped ROM image is `hex/M2764A@DIP28.HEX`. The
  Makefile copies it to a shell-safe `simulator/build/rob3.hex` automatically;
  you do not need to rename anything by hand.
