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

As a response indicating a successful communication startup, the robot sends one of the following bytes back to the control unit, depending on the initialization state:

| Response | Meaning |
|----------|---------|
| `0x15` | Initialization successful |
| `0xF1` | Multiple initialization of the robot |
| `0xF2` | Multiple initialization of the robot |
| `0xF3` | Multiple initialization of the robot |

Any other response from the robot indicates a communication error.

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
