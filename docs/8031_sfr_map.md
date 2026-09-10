# 8031 Special Function Register Usage Map

## Standard 8051 SFRs Used in ROB3 Firmware

| SFR | Address | Name | Usage in Firmware |
|-----|---------|------|-------------------|
| P0  | 0x80 | Port 0 | External bus (data/address multiplex) |
| SP  | 0x81 | Stack Pointer | Set to 0x31 during init |
| DPL | 0x82 | DPTR Low | External memory addressing |
| DPH | 0x83 | DPTR High | Device select for external I/O |
| TCON| 0x88 | Timer Control | Timer/counter enable, interrupt edge |
| TMOD| 0x89 | Timer Mode | Set to 0x21 (T1=mode2, T0=mode1) |
| TL0 | 0x8A | Timer 0 Low | Loaded with 0x11 in ISR |
| TL1 | 0x8B | Timer 1 Low | Not directly set (auto-reload) |
| TH0 | 0x8C | Timer 0 High | Loaded with 0xE8 in ISR |
| TH1 | 0x8D | Timer 1 High | Baud rate reload value (auto-detected) |
| SCON| 0x98 | Serial Control | Set to 0x50 (Mode 1, REN) |
| SBUF| 0x99 | Serial Buffer | Read/write serial data |
| P1  | 0x90 | Port 1 | Digital I/O (read for sensors) |
| IE  | 0xA8 | Interrupt Enable | Init: 0x84 (EA+EX1); fixed-baud path 0x07 (EX0+ET0+EX1); auto-baud path 0x17 (adds ES) |
| P3  | 0xB0 | Port 3 | Special function pins |
| PSW | 0xD0 | Program Status Word | Bank select (RS0, RS1) |
| ACC | 0xE0 | Accumulator | General computation |
| B   | 0xF0 | B register | Multiplication/division |

## Register Bank Usage

| Bank | PSW bits | Address | Used By |
|------|----------|---------|---------|
| 0    | RS1=0,RS0=0 | 0x00-0x07 | Main loop, general code |
| 1    | RS1=0,RS0=1 | 0x08-0x0F | ISR ext0, ISR ext1 |
| 2    | RS1=1,RS0=0 | 0x10-0x17 | Serial ISR (0x0300) |
| 3    | RS1=1,RS0=1 | 0x18-0x1F | Not explicitly used as bank |

## Port 3 Pin Assignments

| Pin | Bit | Function | Usage |
|-----|-----|----------|-------|
| P3.0| 0xB0.0 | RXD | Serial receive / baud detection |
| P3.1| 0xB0.1 | TXD | Serial transmit |
| P3.2| 0xB0.2 | INT0 | External interrupt 0 (motor pulse) |
| P3.3| 0xB0.3 | INT1 | External interrupt 1 (axis servo) |
| P3.4| 0xB0.4 | T0 | Input: program/trigger signal |
| P3.5| 0xB0.5 | T1 | Not identified |
| P3.6| 0xB0.6 | WR | External bus write strobe |
| P3.7| 0xB0.7 | RD | External bus read strobe |

## Timer Configuration

### Timer 0 (System Tick)
- TMOD: Mode 1 (16-bit timer)
- Reload: TH0=0xE8, TL0=0x11 → counts 0xE811 to 0xFFFF (6127 counts)
- At 11.0592 MHz: period ≈ 5.5 ms
- Used for: system timing, axis update triggers, timeout management
- Prescaler 0x1D counts 10 ticks → 55ms sub-rate for slow events

### Timer 1 (Baud Rate Generator)
- TMOD: Mode 2 (8-bit auto-reload)
- TH1: Auto-detected from incoming signal
- Standard values: 0xFD (9600 baud @ 11.0592 MHz)
- Used for: UART baud rate generation

## Interrupt Priority and Enable

### IE Register Values (verified from init)
- Init sets IE = 0x84 (EA + EX1) to start the first axis-feedback cycle.
- Fixed-baud path (P3.0 low at startup): IE = 0x07 (EX0 + ET0 + EX1; no serial int).
- Auto-baud path: IE = 0x17 at 0x0739 (adds ES → serial interrupt-driven).
- Timer 1 overflow interrupt (ET1) is never enabled — Timer 1 is baud-gen only.

### Interrupt Handling Notes
- External Int 0 and External Int 1 are edge-triggered (per TCON settings).
- INT1 is driven by the ADC end-of-conversion (EOC → 8031 pin 13); the axis
  servo ISR runs on each conversion.
- The serial port has its **own** ISR at 0x0300 (the 0x0023 vector falls through
  0xFF padding to `ljmp 0x0300` at 0x0035). It is NOT handled inside a Timer 1
  ISR. When ES is enabled (auto-baud path, IE=0x17) serial is interrupt-driven;
  otherwise RI/TI may be polled.
- ISRs save/restore PSW for bank switching and save ACC before use.

## SCON Configuration
```
SCON = 0x50
  Bit 7 (SM0) = 0  \
  Bit 6 (SM1) = 1   } Mode 1: 8-bit UART, variable baud
  Bit 5 (SM2) = 0  - No multiprocessor
  Bit 4 (REN) = 1  - Receive enable
  Bit 3 (TB8) = 0  - Not used in Mode 1
  Bit 2 (RB8) = 0  - Not used in Mode 1
  Bit 1 (TI)  = 0  - TX interrupt flag (polled)
  Bit 0 (RI)  = 0  - RX interrupt flag (polled)
```
