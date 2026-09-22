# Host serial interface (RS-232)

How a PC host talks to the ROB3 over the DB9 RS-232 link: the wire settings, the
software auto-baud training, the reset handshake, and example commands. Bench-
verified against a real board. See also the firmware side in
`firmware/src/annotated/rs232.asm`.

## Auto-Baud Rate Detection

| Option | Meaning | Typical Value |
|--------|---------|---------------|
| `9600` | Baud rate (bits per second) | 9600 bps |
| `cs8` | Character size = 8 data bits | 8 bits |
| `-cstopb` | Disable 2 stop bits (use 1 stop bit) | 1 stop bit |
| `-parenb` | Disable parity checking/generation | No parity |
| `-crtscts` | Disable RTS/CTS hardware flow control | Off |
| `-ixon` | Disable XON/XOFF software flow control for input | Off |
| `-ixoff` | Disable XON/XOFF software flow control for output | Off |
| `raw` | Disable terminal processing (no character translation, echo, buffering) | Raw bytes |

```bash
$ sudo chmod 666 /dev/ttyUSB0
$ stty -F /dev/ttyUSB0 9600 cs8 -cstopb -parenb -crtscts -ixon -ixoff raw
$ exec 3<> /dev/ttyUSB0
```

## Reset

```bash
$ printf '\x20' >&3
$ head -c 100 <&3 | hexdump -C
  
00000000  f1 f1 f1 f1 f1 f1 f1 f1  f1 15 f3 f1 f1 f1 f1 f1  |................|
*
00000060  f1 f1 f1 f1                                       |....|
00000064

sudo chmod 660 /dev/ttyUSB0
$ exec 3>&-
$ exec 3<&-
```

## Gripper

```bash
printf '\x05\xff\x03' >&3
printf '\x05\x00\x03' >&3
```
