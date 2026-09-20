# Session: ROB3 — RS-232 UART annotation, protocol [SIM] proof, RXD bit-driver, end-to-end serial

**Date:** 2026-09-20
**Task:** Annotate the RS-232 part of the firmware, then progressively *prove* the
serial protocol in ucSim — from command dispatch/framing, to the software
auto-baud bring-up, to a full byte-over-the-wire receive — building the missing
simulator plumbing where ucSim fell short.

Working method: verify against ROM bytes / the running simulator before
asserting; keep the [BYTE]/[SIM]/[HW]/[INFER] provenance; commit small. Notably,
several of my initial assumptions were corrected by the ROM/sim (fixed-baud has
no serial; 115200 is out of the auto-baud range; ucSim doesn't drive the RXD
pin) — those corrections are recorded as findings, not hidden.

## What was done

### 1. Annotated the RS-232 UART handler  [BYTE]
New `firmware/src/annotated/rs232_serial.annotated.asm`: the UART ISR at 0x0300
(RX/TX + the binary command protocol state machine) and the TX helper at 0x0541,
extracted to its own file (precedent: ext1_axis_servo / teachbox). Addresses
byte-verified with xxd (entry 0x0300, exit 0x0525, RETI 0x052E, ACALL 0x0541).
Control flow/SBUF/SCON/buffers are [BYTE]; host command *names* stayed [INFER]
where only the branch structure is known. Cross-reference stub added in
`main.annotated.asm`.

### 2. Protocol semantics — logic level  [SIM]
`simulator/tests/sim_serial.sh` (runs on stock s51). Enters each path with
seeded state and asserts the result:
- READ feedback (hdr 0x47): 0x58..0x5D -> response buffer 0x69..0x6E, R3=7,
  R1=0x68, TX buffer mode 0x25.1.
- TX helper: streams the buffer (R1++/R3--), sets 0x25.4 on the last byte, then
  frames with **ETX = 0x03** (reaches 0x0553 = MOV SBUF,#0x03) — ETX upgraded
  [INFER]->[SIM].
- WRITE single-axis position (hdr 0x02): 0x60 -> 0x52 (axis 2), ACK 0x25.7.
- **RESET-ACK** (main-loop idle-timeout at 0x0785): stages **R4 = 0xF1** and arms
  0x25.3 — this is the documented `printf '\x20'` -> flood-of-0xF1 handshake
  (hardware/host/README.md). Verified R4=0xF1, parser reset, TX armed.

ucSim serial quirk documented: `MOV A,SBUF` returns the model's internal `s_in`
(not the SBUF SFR cell) and a write sets `s_out`; so these tests deliberately
enter AFTER the SBUF read.

### 3. Two hard baud findings  [BYTE][SIM]
- **Fixed-baud (P3.0=0) cannot do serial.** That path sets IE=0x07 (no ES) and
  never starts Timer 1 / writes TH1. Verified at the main loop: IE=0x87 (no ES),
  TCON=0x1A (TR1 clear), TH1=0x00. Serial only works on the auto-detect path.
- **115200 is out of the auto-baud range.** The validation at 0x070A
  (`(run/6 + 8) & 0xF0 == 0x20`) requires ~24..39 Timer-0 ticks/bit (~<=38400
  at 11.0592 MHz). 115200 is ~8 ticks/bit -> never validates.

### 4. ucSim limitation + the `rxd` cl_hw module  [SIM]
ucSim's MCS-51 UART is byte-level and **never drives the P3.0/P3.1 pins**, so the
firmware's software auto-baud — which polls the RAW P3.0 pin (`JB P3.0,$` at
0x06BF) and times edges with Timer 0 — spins forever.
- Filed `simulator/issues/003-mcs51-uart-does-not-drive-rxd-txd-pins/`
  (README + verified repro.sh).
- Built `simulator/ucsim-modules/rxd/` (`cl_rxd`): shifts one 8N1 frame out on
  P3.0 at a configurable **machine-cycles/bit** (the ucSim `xtal` field is
  private, so the harness passes cycles/bit = xtal/baud/12), driven through the
  port write path like the loopback module.

### 5. Auto-baud verified end-to-end  [SIM]
`simulator/tests/sim_serial_autobaud.sh` (opt-in): with `rxd` shifting the
training byte 0x20 at the lock bit-time (128 cyc/bit), the ROM leaves the 0x06BF
spin, captures the edges, validates at 0x070A, derives **TH1=0xFC**, starts
**Timer 1 (TR1)**, and reaches 0x073C with **IE=0x17 (ES on)**.
- Lock window (this XTAL): cyc/bit ~ [104,152] (~6.1..8.9 kbaud as machine-cycle
  time), centred ~128 (~7200); always derives TH1=0xFC.
- **9600 (96 cyc/bit) lands just BELOW the window in this model** and does not
  lock; the model locks at ~128. The wire-baud vs cyc/bit offset is a modelling
  artifact (Timer-0 mode-1 count vs our cycle-based pin timing); the verified
  fact is that the auto-baud path completes and arms the UART.

### 6. Full RX chain over the real wire  [SIM]
`simulator/tests/sim_serial_e2e.sh` (opt-in): the seam the seeded tests skip.
With `adc` + `rxd` loaded and a ucSim `-S in=,out=` link:
- rxd shifts 0x20 -> ROM locks -> the 0x15 ACK is transmitted on the serial
  **output** (real TX);
- a command byte 0x47 on the serial **input** is clocked by the CORE UART into
  **SBUF=0x47** with **RI set (SCON=0x51)** — reception at the derived baud;
- the RX ISR at 0x0300 runs and the RX parser advances (0x24=0x07);
- the **ADC servo ISR (0x00C0) fires in the SAME session** — adc + rxd + serial
  all run together (INT1 servo concurrent with the UART).
Key insight: once auto-baud sets TH1/TR1, the core UART receives normally; the
rxd module is only needed for the pin-level bring-up, after which the standard
byte path takes over.

### 7. Doc move
`software/rs232.md` -> `hardware/host/README.md` (retitled "Host serial
interface (RS-232)"); empty `software/` removed; 5 references updated; link added
from hardware/README.md.

## Verification
- `make verify` (golden byte-match) green throughout (asm edits are docs).
- `make test`: **ALL TESTS PASSED** on both stock `s51` (serial opt-in tests run
  via the default loader path / skip cleanly) and the loader `ucsim_51`.
- New: sim_serial (8 assertions), sim_serial_autobaud (4), sim_serial_e2e (7).
- All `.so` are gitignored; only sources committed.

## Files
- **new** firmware/src/annotated/rs232_serial.annotated.asm
- **new** simulator/ucsim-modules/rxd/{rxd.cc,rxdcl.h,README.md}
- **new** simulator/issues/003-mcs51-uart-does-not-drive-rxd-txd-pins/{README.md,repro.sh}
- **new** simulator/tests/{sim_serial.sh,sim_serial_autobaud.sh,sim_serial_e2e.sh}
- **new** hardware/host/README.md (moved from software/rs232.md)
- firmware/src/annotated/main.annotated.asm (serial vector ref; fixed-baud +
  auto-baud findings)
- simulator/Makefile (sim-serial / sim-serial-autobaud / sim-serial-e2e + test)
- simulator/ucsim-modules/{Makefile,README.md} (rxd)
- simulator/issues/README.md (issue 003 index)
- simulator/tests/README.md (new tests)
- hardware/README.md (host link)

## Open / next
- The command DISPATCH after a fully-received multi-byte frame over the wire
  (0x47 arms 0x24.1; the *next* wire byte or the idle-timeout triggers
  rx_dispatch which fills 0x68..). Proven at logic level (sim_serial.sh) and the
  reception seam is proven (sim_serial_e2e.sh); stitching a full multi-byte
  command+response entirely over the wire is the remaining nicety.
- System-class (hdr.7=1) program upload/download sub-commands: [BYTE] flow,
  [INFER] host names — not yet driven in ucSim.
- L293 direction map still [INFER] (unchanged, unrelated deep task).
- Commits are local on `main`; **not pushed** this session.
