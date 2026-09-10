# PB86 button

## Opened

```ascii
                           DB25
                             |
					  +------------+
                      |   +----+   |
         (LED -)  6 --|---| \/ |---|-- 7  (LED +)
                      |   +----+   |
                  1 --|--o------o--|-- 2
                      |      |     |
                  3 --|--o /    o--|-- 4
                      |            |
                      +------------+
```

## Closed

```ascii
                           DB25
                             |
                      +------------+
                      |   +----+   |
         (LED -)  6 --|---| \/ |---|-- 7  (LED +)
                      |   +----+   |
                  1 --|--o------o--|-- 2
                      |      |     |
                  3 --|--o    \ o--|-- 4
                      |            |
                      +------------+
```

## 1. The Switch Type: SPDT (Single Pole Double Throw)

Unlike a standard 4-pin tactile button that only bridges a single connection, the PB86 is an SPDT mechanical switch.
- Pin 3 is the "Common" pin.
- When the button is not pressed, Pin 3 rests against Pin 1 / 2 (Normally Closed circuit).
- When you press the button, it breaks that connection and hinges down to contact Pin 4 / 5 (Normally Open circuit).

## 2. The Built-in Indicator: Independent LED

The extra 2 pins at the bottom (usually labeled with a + and - sign or numbered 6 and 7) belong exclusively to the integrated LED lamp.
- This circuit is electrically completely isolated from the switch itself.
- The robot controller can turn the light on or off independently of whether your finger is pushing the button down (e.g., blinking to indicate an error, or staying solid green when a macro is running)

## References

* http://www.xbswitch.com/Data/switchsmd/upload/image/20230703/XB-PB86-A1-0-R.pdf
* https://www.honyone.com/en/products/show_215.html
* https://github.com/bigattichouse/PB86
* https://github.com/adafruit/Adafruit-PB86-Breakout-PCB
* https://github.com/ScharreSoft/PB86-footprints-and-3d-models/tree/main
* https://www.adafruit.com/product/5631
* https://github.com/adafruit/Fritzing-Library/blob/master/parts/Step%20Switch%20PB86%20Breakout.fzpz
* https://github.com/langhua/fritzing-parts-langhua/blob/main/fzpz/PB86-A0-YELLOW.fzpz
