# Board

```bash
                                 TOP
┌─────────────────────────────────────────────────────────────────────────┐  2 4 6
│     X8      X7       X6       X5       X4       X3       X2     1 X1 6  │  ● ● ●
│ ░░░░░░░░ ░░░░░░░░ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ │  ● ● ●
│                                                                         │  1 3 5
│                                                                         │
│  o o o o o o o o  ┌● ● ● ● ● ● ● ●┐ ┌● ● ● ● ● ● ● ●┐ ┌● ● ● ● ● ● ● ●┐ │
│                   )    L293 #3    │ )    L293 #2    │ )    L293 #1    │ │
│  o o o o o o o o  └● ● ● ● ● ● ● ●┘ └● ● ● ● ● ● ● ●┘ └● ● ● ● ● ● ● ●┘ │
│                                                                         │
│                                                                         │
│ ┌● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●┐ ┌● ● ● ● ● ● ● ● ● ● ● ● ● ●┐ │
│ │                                     o │ │            ADC            │ │
│ │        Intel 8255 PPI (40 pin)        ( ) o                         │ │
│ │                                       │ └● ● ● ● ● ● ● ● ● ● ● ● ● ●┘ │
│ └● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●┘                               │
│ ┌● ● ● ● ● ● ● ● ● ● ● ● ● ●┐                                           │
│ │       Japan 8259 (SRAM)   │             ▲                             │
│ )       HM6264LP-15         │   ●────●   ┌┴┐                            │
│ │       U0012YYO            │   ● 74 ●   │=│ 1N 5400   ┌───────┐        │
│ └● ● ● ● ● ● ● ● ● ● ● ● ● ●┘   ● LS ●   │ │           │L7805V │        │
│ ┌● ● ● ● ● ● ● ● ● ● ● ● ● ●┐   ● 1  ●   └┬┘           └┬──┬──┬┘        │
│ │       M2764A-2FI (EPROM)  │   ● 38 ●    ▲             ▲ GND ▼         │
│ )       PGM 12.5V           │   ●    ●    │             │    5V         │
│ │                           │   ●    ●    9V            │               │
│ └● ● ● ● ● ● ● ● ● ● ● ● ● ●┘   ●─⌒─●                  │               │
│   ┌● ● ● ● ● ● ● ● ● ●┐ ┌● ● ● ● ● ● ●┐                 │ ┌┬─────┐      │
│   )    SGS 74HC573    │ ) SGS 74HC14  │                 └─││ ITT │────o │ Raw +9V Input
│   └● ● ● ● ● ● ● ● ● ●┘ └● ● ● ● ● ● ●┘                   └┴─────┘    o │
│                                                                         │
│  ┌● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●┐                              │
│  │                                       │    ┌● ● ● ●┐                 │
│  )   Intel 8031 CPU (40 pin)             │    )MAX1044│                 │
│  │ o                                     │    └● ● ● ●┘                 │
│  └● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ● ●┘                              │
│ ●────●   ┌● ● ● ● ● ● ●┐  ┌● ● ● ● ● ● ●┐                               │
│ ● 74 ●   ) MM74C04N #2 │  ) MM74C04N #1 │                               │
│ ● LS ●   └● ● ● ● ● ● ●┘  └● ● ● ● ● ● ●┘                               │
│ ● 2  ●                                                                  │
│ ● 44 ●                                                                  │
│ ●    ●                                        ┌● ● ● ● ● ● ●┐           │
│ ●    ●                                        )   M34004    │           │
│ ●    ●                                        └● ● ● ● ● ● ●┘           │
│ ●    ●             20....17                                             │
│ ●─⌒─●            8 7 6 5 4                                             │
│               5V-●●●●●●●●●●                                             │
│  ▓●●●●●●●●●●●●●●●●●●●●●●●●●▓                X10     ▓●●●●●●●●●▓         │
└─────────────────────────────────────────────────────────────────────────┘
                                  BOTTOM
```

- [L293 #1](L293.md#l293-1)
- [L293 #2](L293.md#l293-2)
- [L293 #3](L293.md#l293-3)
- [M34004](M34004.md)
- [MAX1044](MAX1044.md)
- [MM74C04N #1](MM74C04N.md#mm74c04n-1)
- [MM74C04N #2](MM74C04N.md#mm74c04n-2)
- [74LS244](74LS244.md)
- [74HC14](74HC14.md)
- [74HC373](74HC373.md)
- [74LS138](74LS138.md)
- [ADC](adc.md)
- [EPROM 8K](eprom.md)
- [SRAM 8K](sram.md)
- [8255](8255.md)
- [8031](8031.md)
- [resistor pullup array](resistor-pullup-array.md)

## Reverse-engineering view for the 8031 firmware

This board is organized around the classic 8031 external-memory model:

- `P0` is the multiplexed address/data bus (`AD0`-`AD7`).
- `P2` carries the high address lines (`A8`-`A15`).
- `ALE` latches the lower address byte so the 8031 can drive `A0`-`A7` and the data bus without conflict.
- `PSEN` selects the EPROM read cycle.
- `RD` and `WR` select the SRAM and 8255 data-path operations.
- `74HC373` is the address latch stage that preserves the lower address bits during memory access.
- `74LS138` decodes the selected device block so only one memory or peripheral device responds at a time.
- The 8255 exposes the board's parallel I/O map, while the ADC, L293 drivers, and other logic blocks sit behind those memory-mapped control lines.

For binary reverse-engineering, the important architectural observation is that the firmware is not talking to random chips directly; it is talking to a fixed external memory map and a decode network. The true target of the 8031 code is therefore the board's memory and peripheral map, not just the component names on the schematic.

## References

* https://github.com/dev-lab/pcb-retrace
* https://pcbtracer.com/app.html
