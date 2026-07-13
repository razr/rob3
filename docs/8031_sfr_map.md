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
| IE  | 0xA8 | Interrupt Enable | 0x17 or 0x07 (EA+ES+ET0+EX0 or EA+ET0+EX0) |
| P3  | 0xB0 | Port 3 | Special function pins |
| PSW | 0xD0 | Program Status Word | Bank select (RS0, RS1) |
| ACC | 0xE0 | Accumulator | General computation |
| B   | 0xF0 | B register | Multiplication/division |

## Register Bank Usage

| Bank | PSW bits | Address | Used By |
|------|----------|---------|---------|
| 0    | RS1=0,RS0=0 | 0x00-0x07 | Main loop, general code |
| 1    | RS1=0,RS0=1 | 0x08-0x0F | ISR ext0, ISR ext1 |
| 2    | RS1=1,RS0=0 | 0x10-0x17 | Serial ISR (Timer 1) |
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

### IE Register Values
- During normal operation: IE = 0x97 (EA=1, ES=1, ET1=0, EX1=1, ET0=1, EX0=1)
  - Note: Timer 1 overflow interrupt NOT used (baud gen only)
- Alternate: IE = 0x07 (fast mode without serial interrupt)
- Serial interrupt handled via polling RI/TI in Timer 1 ISR

### Interrupt Handling Notes
- External Int 0 and External Int 1 appear to be edge-triggered (based on TCON settings)
- The serial port interrupt is effectively handled inside the Timer 1 overflow ISR by checking RI/TI flags directly
- ISRs save/restore PSW for bank switching
- ISRs save ACC in register before use

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
