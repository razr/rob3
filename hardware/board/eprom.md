# EPROM

The M2764A EPROM stores the board's permanent program code. It is the nonvolatile memory source for the 8031 and is selected through the board's decode and latch logic.

## Pinout

```text
             +---U---+
        VPP ─┤ 1   28 ├─ VCC (+5V)
        A12 ─┤ 2   27 ├─ P (program)
         A7 ─┤ 3   26 ├─ A13 (NC)
         A6 ─┤ 4   25 ├─ A8
         A5 ─┤ 5   24 ├─ A9
         A4 ─┤ 6   23 ├─ A11
         A3 ─┤ 7   22 ├─ G (output enable)
         A2 ─┤ 8   21 ├─ A10
         A1 ─┤ 9   20 ├─ E (chip enable)
         A0 ─┤10   19 ├─ Q7
         Q0 ─┤11   18 ├─ Q6
         Q1 ─┤12   17 ├─ Q5
         Q2 ─┤13   16 ├─ Q4
        GND ─┤14   15 ├─ Q3
             +--------+
```

## Board connections

```text
                               +---U---+
                    VCC (+5V) ─┤ 1   28 ├─ VCC (+5V)
                  8031 pin 25 ─┤ 2   27 ├─ VCC (+5V)
               74HC573 pin 19 ─┤ 3   26 ├─ 8031 pin 26
                74HC573 pin 2 ─┤ 4   25 ├─ 8031 pin 21
               74HC573 pin 16 ─┤ 5   24 ├─ 8031 pin 22
                74HC573 pin 5 ─┤ 6   23 ├─ 8031 pin 24, 74LS138 pin 2
               74HC573 pin 15 ─┤ 7   22 ├─ 74HC14 pin 8
                74HC573 pin 6 ─┤ 8   21 ├─ 8031 pin 23
                74HC573 pin 9 ─┤ 9   20 ├─ 74LS138 pin 12
               74HC573 pin 12 ─┤10   19 ├─ 8031 pin 32, 74HC573 pin 18
  8031 pin 39, 74HC573 pin 13 ─┤11   18 ├─ 8031 pin 33
   8031 pin 38, 74HC573 pin 8 ─┤12   17 ├─ 8031 pin 34
   8031 pin 37, 74HC573 pin 7 ─┤13   16 ├─ 8031 pin 35
                          GND ─┤14   15 ├─ 8031 pin 36, 74HC573 pin 14
                               +--------+
```

## Notes

- The EPROM shares the address and data bus with the SRAM, but is selected separately through the board's decoder and control lines.
- The board uses the EPROM as a program storage device while the SRAM acts as the data workspace during runtime.

## Reverse-engineering relevance

This is the program image. If the goal is to reverse-engineer the 8031 binary, the EPROM is where the firmware bytes originate and where the code fetch path begins.

The critical observation is that the firmware is fetched by the 8031 through the external-memory decode path, not from an isolated CPU core. The `PSEN` signal, address decode, and the external bus all define how the code is actually delivered to the processor.

# References

* https://datasheet.octopart.com/M2764A25F1-STMicroelectronics-datasheet-117746.pdf
* https://downloads.reactivemicro.com/Electronics/ROM/2764%20EPROM.pdf
