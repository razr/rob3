# Hardware

## [Motors and potentiometers](motors/README.md)

```ascii
                    Gripper   Axis 5   Axis 4   Axis 3   Axis 2   Axis 1

                     Motor    Motor    Motor    Motor    Motor    Motor

                    Potentio Potentio Potentio Potentio Potentio Potentio
                     meter    meter    meter    meter    meter    meter

                    ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓
```

## [Control Board](board/README.md)

```ascii
┌─────────────────────────────────────────────────────────────────────────┐
│     X8      X7       X6       X5       X4       X3       X2       X1    │
│ ░░░░░░░░ ░░░░░░░░ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ ▓●●●●●●▓ │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│                                                                         │
│             DB25                                        DB9             │
│  ▓●●●●●●●●●●●●●●●●●●●●●●●●●▓                        ▓●●●●●●●●●▓         │
└─────────────────────────────────────────────────────────────────────────┘
```

## PC connection

See [host serial interface](host/README.md) for the RS-232 wire settings, the
reset handshake (`0x20` → `0xF1` reply), and example host commands.

```ascii
                                                          DB9
                                                      ▓●●●●●●●●●▓
                                                           └──────────── PC RS232
```

## [Teachbox](teachbox/README.md)

```ascii
               DB25
   ▓●●●●●●●●●●●●●●●●●●●●●●●●●▓
     ┌─────────┬─────────┬─────────┬─────────┬─────────┐
     │         │         │         │         │         │
     │         │         │         │         │         │
     │    ○    │    ○    │    ○    │    ○    │    o    │
     │  MARK   │  GOTO   │   IF    │    OUT  │   TIM   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │         │
     │         │         │         │         │         │
     │         │         │         │         │  ↓   +  │
     │   DEL   │    7    │    8    │    9    │  ←      │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │         │
     │         │         │         │         │         │
     │         │         │         │         │    ○    │
     │   INS   │    4    │    5    │    6    │   POS   │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │         │
     │         │         │         │         │         │
     │    ○    │         │         │         │   ↑  -  │
     │   RUN   │    1    │    2    │    3    │   →     │
     ├─────────┼─────────┼─────────┼─────────┼─────────┤
     │         │         │         │         │         │
     │         │         │         │         │         │
     │         │         │    ○    │    ○    │         │
     │   STOP  │    0    │  • NOP  │ ERR CLR │   ENT   │
     └─────────┴─────────┴─────────┴─────────┴─────────┘
```
