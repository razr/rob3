# SRAM

The HM6264LP-15 is the board's volatile data memory. It holds the software workspace, stack area, and runtime variables while the system is powered on, while the EPROM remains the permanent program image.

## Pinout

```text
               HM6264LP-15
              +------U------+
          NC -| 1        28 |- VCC (+5V)
         A12 -| 2        27 |- /WE
          A7 -| 3        26 |- CS2
          A6 -| 4        25 |- A8
          A5 -| 5        24 |- A9
          A4 -| 6        23 |- A11
          A3 -| 7        22 |- /OE
          A2 -| 8        21 |- A10
          A1 -| 9        20 |- /CS1
          A0 -|10        19 |- I/O8
        I/O1 -|11        18 |- I/O7
        I/O2 -|12        17 |- I/O6
        I/O3 -|13        16 |- I/O5
        GND  -|14        15 |- I/O4
              +-------------+
```

## Board connections

```text
                                  +------U------+
                     8031 pin 27 ─┤ 1        28 ├─ VCC (+5V)
      8031 pin 25, 74LS138 pin 3 ─┤ 2        27 ├─ 8255 pin 36
                  74HC373 pin 19 ─┤ 3        26 ├─ 8031 pin 26
                   74HC373 pin 2 ─┤ 4        25 ├─ 8031 pin 21
                  74HC373 pin 16 ─┤ 5        24 ├─ 8031 pin 22
                   74HC373 pin 5 ─┤ 6        23 ├─ 8031 pin 24, 74LS138 pin 2
                  74HC373 pin 15 ─┤ 7        22 ├─ 74HC14 pin 8
                   74HC373 pin 6 ─┤ 8        21 ├─ 8031 pin 23
                   74HC373 pin 9 ─┤ 9        20 ├─ 74HC14 pin 3
                  74HC373 pin 12 ─┤10        19 ├─ 8031 pin 32, 74HC373 pin 18
     8031 pin 39, 74HC373 pin 13 ─┤11        18 ├─ 8031 pin 33
      8031 pin 38, 74HC373 pin 8 ─┤12        17 ├─ 8031 pin 34
      8031 pin 37, 74HC373 pin 7 ─┤13        16 ├─ 8031 pin 35
                             GND ─┤14        15 ├─ 8031 pin 36, 74HC373 pin 14
                                  +-------------+
```

## Notes

- The SRAM shares the same 28-pin memory footprint as the EPROM.
- The board distinguishes them using different control signals: the EPROM is selected by program read timing, while the SRAM is selected by the data memory cycle.

## pin 1 (NC)

The layout is completely correct and logical. The reason pin 1 (NC) of RAM chip is connected to pin 27 (P2.6 / A14) of the Intel 8031 microcontroller comes down to two classic engineering practices in retro-electronics:

1. Future-Proofing for Larger Memory Chips (JEDEC Compatibility)This is a standard PCB design trick. The 28-pin DIP package follows a standardized JEDEC layout. Circuits were often designed to be universal so that a manufacturer could solder either an 8 KB chip (6264) or a 32 KB chip (62256) onto the exact same board without changing the layout.If you compare the pinouts:
- HM6264 (8 KB): Pin 1 = NC (No Connection inside the chip)
- HM62256 (32 KB): Pin 1 = A14 (The extra address line needed to access 32 KB)

Because Pin 1 on your current 6264 chip is truly empty inside the plastic housing (the silicon die is not bonded to this lead), applying the A14 signal to it has absolutely no effect on its operation. However, if someone wanted to upgrade the device's memory in the future, they could just swap in a 62256 chip, and the address line from the 8031 would already be wired and ready to go.

2. Cleaner PCB Trace RoutingWhen routing a parallel address bus on a circuit board, it is much easier to keep the traces running together in a clean block.
- Pin 27 of the 8031 is P2.6, which acts as address line A14.
- Rather than leaving this trace hanging in the middle of nowhere (which can act like an antenna and pick up electrical noise), the designer simply terminated it at Pin 1 of the RAM socket.

Since Pin 1 is dead weight on the 6264 anyway, it acts as a safe, convenient anchor point on the board.

## Reverse-engineering relevance

This device is the live runtime workspace. It holds temporary registers, stacks, working variables, and state mirrors that are essential when reconstructing the firmware's control logic.

For reverse engineering, the SRAM is often the most informative memory device because it shows how the code stores active state, thresholds, sensor values, and command frames during execution. A binary dump alone can be misleading; the runtime SRAM map shows what the firmware is actively using in real time.

## References

* https://cdn-reichelt.de/documents/datenblatt/A300/HM6264.pdf
