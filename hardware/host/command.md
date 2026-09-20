# Eurobtec ROB 3 Low-Level Protocol

The Eurobtec low-level protocol is a **non-standardized communication protocol** used for message transmission and for controlling the **ROB 3** robot via the **RS-232 serial interface**.

The drive controller (**8031 processor**) receives the command words and controls the servo motors of the robot axes and the gripper.

Communication operates **without hardware handshake**. However, for most commands (but not all), the robot sends a response back to the control unit.

For all responses, the robot always returns the **command byte**.

> **Confirmed against the ROM firmware [SIM].** Every command family below was
> verified by driving the header byte through the real 8031 command dispatch in
> ucSim and observing the resulting state (see the confirmation table at the end
> of this file, `firmware/src/annotated/rs232_serial.annotated.asm`, and
> `simulator/tests/sim_serial.sh`). The command byte is decoded from its bit
> fields; the frame's trailing `0x03` (ETX) is checked by the firmware
> (`cjne A,#0x03` at 0x03AE) before the header is acted on — a malformed frame
> is rejected.

---

## Communication Sequence

After a previous **RESET** of the robot (using the reset button on the rear side of the base), the robot interface automatically determines the baud rate.

The very first byte sent from the control unit to the robot must be:

```
0x20 (SPACE)
```

As a response indicating a successful communication startup, the robot sends a
byte back to the control unit. The table below gives the **ROM-verified [SIM]**
meanings; the original manual grouped `0xF1`/`0xF2`/`0xF3` together as "multiple
initialization", which is inaccurate against this firmware (see notes).

| Response | Meaning (ROM-verified) | When / producer |
|----------|------------------------|-----------------|
| `0x15` | **Initialization successful** | emitted once when auto-baud locks — `0x0733` `mov SBUF,#0x15` (after `mov TH1,A` / `setb TR1`). **[SIM] on the wire.** |
| `0xF1` | **Already initialized** (a byte arrived after the UART was already up) | serial idle-timeout — `0x0793` `mov R4,#0xF1`, when a byte was seen (`0x24.2`) and counter `0x18` expires. **[SIM] on the wire** (`15 F1`). |
| `0xF3` | **Command-received ACK** (also the reply if `0x20` is sent as a command frame post-init) | dispatch default — `0x03AC` `mov R4,#0xF3`. Verified [SIM] as the class-0 ACK; plausible "already-initialised" reply but not observed on the wire in the handshake. |
| `0xF2` | **Not a startup reply** — it is a *program single-step* command status | `0x0437` `mov R4,#0xF2`, reachable only via the `hdr.7=1` sub-command chain, **not** from a `0x20` byte. |

> The manual originally listed:
> `0x15` = "Initialization successful"; `0xF1` = `0xF2` = `0xF3` = "Multiple
> initialization of the robot". The `0xF1`/`0xF3` bytes are indeed the
> already-initialized/ACK replies, but **`0xF2` is a command status byte, not a
> startup reply.** See "Status / acknowledgment bytes" below for the full `0xFx`
> family — none of them are error codes.

"Any other response from the robot indicates a communication error" means a byte
**outside** the defined `0xFx`/`0x15`/data set (e.g. line noise) — the `0xFx`
values themselves are acknowledgments, not errors.

After the single `SPACE` initialization byte, the actual command data records can be transmitted.

Each command data record must always be terminated with:

```
0x03 (ETX - End of Text)
```

## Commands for Controlling the Robot

For easier understanding, the actual commands are first presented byte by byte in binary form and then converted to hexadecimal form.

The **command keyword**, which is also returned by the robot as an acknowledgment for positioning commands, is the **first command byte**, excluding the target value (*setpoint (target value)*) or time factor.

## Positioning Commands

### Single-axis positioning command

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Range |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 0 | 0 | 0 | R | a | a | a | `0x00`–`0x0D` |

**Followed by:**

- **1 byte setpoint** (`0x00`–`0xFF`, decimal 0–255)

Where:

- **`R = 1`**: Request an acknowledgment after the robot reaches the target position.
- **`aaa`**: Axis number (`0`–`5`), where **axis 5** corresponds to the **gripper**.

### All-Axes Positioning Command

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Value |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 0 | 0 | 0 | R | 1 | 1 | 1 | `0x0F` |

**Followed by:**

- **7 bytes of setpoints** (`0x00`–`0xFF`, decimal 0–255)

Where:

- **`R = 1`**: Request an acknowledgment after all axes reach their target positions.

**Robot response:**

- The robot returns the **command keyword** (`0x0F`) followed by **`ETX` (`0x03`)**.

## Positioning Commands with Speed Control

### Single-Axis Positioning Command

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Range |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 1 | 1 | 1 | R | a | a | a | `0x70`–`0x7D` |

**Followed by:**

- **1 byte setpoint** (`0x00`–`0xFF`, decimal 0–255)
- **1 byte time factor** `T`

Where:

- **`T = 0`**: Maximum speed.
- **`T = 1`–`7`**: Progressively slower movement.
- **`T = 7`**: Very slow (the axis position is updated approximately every **70 ms**).
- **`R = 1`**: Request an acknowledgment after the robot reaches the target position.
- **`aaa`**: Axis number (`0`–`5`), where **axis 5** corresponds to the **gripper**.

**Robot response:**

- The robot returns the **command keyword** followed by **`ETX` (`0x03`)**.

---

### All-Axes Positioning Command with Speed Control

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Value |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 1 | 1 | 1 | R | 1 | 1 | 1 | `0x7F` |

**Followed by:**

- **6 bytes of setpoints** (`0x00`–`0xFF`, decimal 0–255), one for each axis.
- **6 bytes of time factors** `T`, one for each axis.

When a command is accepted, the previous target position is incremented or decremented by one step after each time interval **T** until the final target position is reached.

The time interval **T** is calculated as:

```
T = time factor × 10 ms
```

If the **time factor is 0**, the robot moves to the target position at its maximum speed.

## Control and Status Commands

### Motor Control Commands

| Command | Description |
|---------|-------------|
| `0x60` | Disable motor control |
| `0x61` | Enable motor control |
| `0x62` | Positioning shutdown (software emergency stop). The current actual position is retained. |

---

### Serial Number Query

| Command | Description |
|---------|-------------|
| `0x63` | Request serial number |

**Robot response:**

The robot returns:

```
Command keyword, S0, S1, S2, ETX
```

---

## Position Query Commands

### Single-Axis Position Query

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Range |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 1 | 0 | 0 | 0 | a | a | a | `0x40`–`0x45` |

Where:

- **`aaa`**: Axis number (`0`–`5`)

**Robot response:**

```
Command keyword, 1 byte actual position value (0–255), ETX
```

---

### All-Axes Position Query

| Bit 7 | Bit 6 | Bit 5 | Bit 4 | Bit 3 | Bit 2 | Bit 1 | Bit 0 | Hex Value |
|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:-----:|:---------:|
| 0 | 1 | 0 | 0 | 0 | 1 | 1 | 1 | `0x4F` |

**Robot response:**

```
Command keyword, 7 bytes actual position values (0–255), ETX
```

---

## Stored programs (same as the Teachbox) — upload & execute over RS-232

The positioning/query commands above act on the robot **immediately**. ROB3 can
also store a **control program** — a sequence of instructions (MARK / GOTO / IF /
OUT / TIM / POS …) — in its **nonvolatile external SRAM** (battery-backed
HM6264, page `0x80` = `0x8000`; base kept in IRAM `0x3E:0x3F`).

**This is the *same* program store and instruction set the Teachbox uses.** The
Teachbox README states the ROB3 "can be programmed directly via the Teachbox …
these instructions are then stored in memory as a control program", and "the
RS-232 serial interface [makes] it possible to control **and program** the robot
from a PC." So a program entered by keypad and one uploaded over serial are the
same bytes in the same memory. The full instruction/command set is documented in
[`../teachbox/README.md`](../teachbox/README.md) ("Summary of all Instructions
and Commands"): `MARK m`, `POS`, `TIM t`, `GOTO m [. n]`, `IF i [. m]`,
`OUT k +/-`, `NOP`, program start/end/`DEL` separators, and the run-control
commands `RUN [.] [m]`, `STOP [.] [m]`, `INS`, `DEL`, `CLR`.

### Upload — the `0x81` block command  [SIM: transport]
A `0x81` header puts the receiver into **block-store mode** (sets RX flag
`0x24.3`, verified [SIM]). The following bytes give a run pointer/length, then
the program bytes, which are streamed into external SRAM with `MOVX`
(verified [SIM]: a byte written via this path lands at SRAM `0x8100`). The
firmware maintains a program header (byte count) at the top of the SRAM page and
sets **program-loaded** (`0x28.1`); a stored program persists across power-off
(lithium-backed, ~10 years per the Teachbox manual).

### Download / readback
Reading the stored program back is the `0x25.6` TX "stream from SRAM" path
(`sys_readprog`, `0x03C9`): it sends the header + program bytes framed with ETX.

### Execution control — the system commands (header bit 7 = 1)
Headers with **bit 7 set** (`0x80`+) are *system* commands. The firmware
subtracts `0x80` and dispatches on the sub-code (`sys_cmd` chain at `0x03E1`),
manipulating the program state byte `0x28`
(`.1`=loaded, `.2`=running, `.3`=motion-active, `.4`=conditional) and calling the
program interpreter (`0x07FF` / `0x0802` / `0x0A33`). These correspond to the
Teachbox **RUN / STEP / STOP / DISPLAY** run-control commands: start execution
from a label, single-step, stop (retaining or clearing state), set conditional
mode, etc. Each returns a program-operation **status byte** (`0xF6` / `0xF2` /
`0xF4`; see the status table below) — these are acknowledgments, not errors.

> Provenance: the SRAM program store, the `0x81` block-store transport, the
> program-loaded flag, and the system-command routing are **[SIM]** verified;
> the shared-store claim is **[HW-doc]** (Teachbox README). The exact **program
> instruction byte format** (what the interpreter at `0x0802`/`0x0A33` decodes
> per stored byte) is **[INFER]** — not yet reverse-engineered. So you *can*
> upload bytes into the program store and trigger execution over RS-232, but the
> on-wire encoding of each instruction is not yet documented here.

---

## ROM confirmation [SIM]

Each command header was driven through the real 8031 dispatch (entry
`rx_dispatch` at `0x03A9`, header in R6, frame terminated with ETX `0x03`) in
ucSim, and the resulting IRAM/response state observed. Firmware landmarks are in
`firmware/src/annotated/rs232_serial.annotated.asm`.

| Command | Documented meaning | ROM-observed effect | Firmware path |
|:--------|:-------------------|:--------------------|:--------------|
| `0x40`–`0x45` | single-axis position query | response buffer `0x68` = header + `feedback[axis]` (`0x58+axis`) + ETX | `c0_read_one` 0x0469 |
| `0x4F` | all-axis position query | `0x68` = header + `feedback[0..5]` (`0x58..0x5D`) + ETX (7 bytes) | 0x0453 |
| `0x00`–`0x05` | single-axis position | `position[0x50+axis]` = setpoint | `c0_pos_one` 0x04CE |
| `0x07` / `0x0F` | all-axis position | `position[0x50..0x55]` = 6 setpoints | `c0_bit6_lo` 0x04BC |
| `0x70`–`0x75` | single-axis position + speed | `target[0x40+axis]` = setpoint; motion mask `0x2B` bit set | `c0_tgt_one` 0x04F0 |
| `0x77` / `0x7F` | all-axis position + speed | `target[0x40..0x45]` = 6 setpoints; mask `0x2B` = `0x3F` (all six) | `c0_654` 0x04DC |
| `0x60` | disable motor control | (no target/position change; control flag path) | `c0_65` 0x048C |
| `0x61` | enable motor control | sets axis-enable flag `0x20.0` | `c0_65_1`→0x0492 |
| `0x62` | positioning shutdown, retain actual position | snapshots `feedback[0x58..]` into `position[0x50..]` | 0x0498 |
| `0x63` | serial number query | `0x68` = header + 3 bytes (S0,S1,S2 from XRAM `0x001F..`) + ETX | `c0_setprog` 0x050B |

Notes:
- The command byte is decoded from its bit fields exactly as the tables above
  describe (bit7/6/5/4 select the class, low 3 bits = axis `0..5`, `7` = all).
- The **acknowledge bit** (bit 3 = `R`) is captured into `0x23.1` at `0x0502`
  (`mov C,0xE0.3 ; mov 0x23.1,C`) — matches the doc's "request acknowledgment".
- All responses are framed by the TX helper (`0x0541`) and terminated with ETX
  `0x03`, confirmed [SIM] in `simulator/tests/sim_serial.sh`.
- The reset handshake (`0x20` → `0x15`, with `0xF1/0xF2/0xF3` on re-init) is
  confirmed: `0x15` is sent at the end of auto-baud lock, `0xF1` is the
  idle-timeout reset-ACK (main loop `0x0785`, `mov R4,#0xF1`); `0xF2`/`0xF3`
  are other staged status bytes (`0x0437`/`0x03AC`). See the annotated file.

## Undocumented / hidden behaviour found in the ROM  [SIM]

An exhaustive sweep of every header `0x00..0xFF` through the dispatch turned up
behaviour the manual does not list. None are secret "extra features" beyond one
family (the digital-input read); the rest are **decoding aliases** — the firmware
does not check every bit, so several byte values map onto the same handler.

### 1. Digital-input read commands (genuinely undocumented)
The read path has a branch (`c0_read_dig`, `0x0471`) taken when **bit 4 = 1** in
the `010x` class, i.e. headers `0x50..0x57`. Instead of an axis pot it appends
**auxiliary/digital-input** bytes, selected by the low bits of the header:
- bit 0 → append RAM `0x5E`  (DI state, "Additional I/O" — see
  docs/reverse_engineering_notes.md, hardware/connectors/db25.md DI1..DI8)
- bit 1 → append RAM `0x5F`  (DI state)
- bit 2 → append P1 (`0x90`)

So e.g. `0x56` → response `[56, 0x5F, P1, ETX]`; `0x5F` → `[5F, 0x5E, 0x5F, P1,
ETX]`. These read the robot's **digital inputs** over serial and are not in the
command table above. (The axis-6/7 arithmetic aliases `0x46`/`0x4E` also happen
to read `0x5E` as "axis 6 feedback".)  [SIM] verified; the electrical meaning of
each DI bit is [HW] per db25.md.

### 2. Aliases from partial bit decoding (not new commands)
- **Control block ignores bits 3:2.** `0x60..0x63` (disable / enable / shutdown /
  serial-number) repeat every 4: `0x64/0x68/0x6C` == `0x60`, `0x65/0x69/0x6D` ==
  `0x61`, etc. So `0x64..0x6F` behave as `0x60..0x63`.
- **Acknowledge-bit variants.** Any command with bit 3 set (`R=1`) routes to the
  same handler as its `R=0` form and additionally sets the ack flag `0x23.1`
  (e.g. `0x08..0x0D` == `0x00..0x05` + ack; `0x78..0x7D` == `0x70..0x75` + ack;
  `0x0F` == `0x07` + ack). This is the documented `R` bit, just not enumerated.
- **Invalid axis 6** (`0x46/0x66/0x76/...`, axis field = 6) is not a real axis;
  the arithmetic still runs and yields out-of-range reads/masks. Not a command.

### 3. Frame terminator is enforced
A frame is only acted on if its last byte is ETX `0x03` (`cjne A,#0x03` at
`0x03AE`); otherwise the header is discarded to the generic-ack path. So a
"command" is really `<header> [payload...] 0x03`.

> Provenance: routing/aliasing is [SIM] (swept 0x00..0xFF through `rx_dispatch`
> and observed state); the DI bit-to-connector mapping is [HW] (db25.md); the
> "no other hidden commands" claim is bounded by this single-frame dispatch
> sweep — the program-interpreter (`0x81` block / `0x89..0x8F` download) and the
> system class (`hdr.7=1`) were exercised only in their empty/no-program state.

## Status / acknowledgment bytes — the `0xFx` family is NOT errors  [SIM]

The robot tags every command reply with a **status byte in the `0xF0` range**;
these are normal acknowledgments, not error codes. The manual's note that "any
*other* response indicates a communication error" means a byte *outside* this
defined set — there is **no distinct NAK/error byte** in the firmware (even a
malformed, non-ETX frame is answered with the normal `0xF3`).

| Status | Meaning | Producer (ROM) |
|:-------|:--------|:---------------|
| `0x15` | initialization OK | `0x0733` `mov SBUF,#0x15` (auto-baud lock) |
| `0xF1` | multiple init (byte received while already up) | `0x0793` `mov R4,#0xF1` (idle-timeout) |
| `0xF3` | **default ACK** — "command received" | `0x03AC` `mov R4,#0xF3` (every class-0 cmd `0x00..0x7F`; also the malformed-frame fallback) |
| `0xF4` | system-class ACK (`0xF3`+1) | `0x03B8` `inc R4` (system cmds `0x80+`) |
| `0xF6` | program-operation status | `0x03F1` `mov R4,#0xF6` |
| `0xF2` | program single-step status | `0x0437` `mov R4,#0xF2` |
| `0xF7` | **motion-complete ACK** (target reached, motors cut) | `0x0776` `mov R4,#0xF7` (main loop, ack-bit reply) |

For **query** commands (`0x40..0x45`, `0x4F`, `0x63`) the reply is the requested
DATA (streamed via the buffer TX path), not a status byte — `R4` is still staged
as `0xF3` but is not what gets sent. All status/data responses are ETX-framed.
Verified by staging `rx_dispatch` per command family and reading `R4`
(`simulator/tests/sim_serial.sh`); the `0x15`/`0xF1` wire emission is confirmed
in `simulator/tests/sim_serial_e2e.sh`.
