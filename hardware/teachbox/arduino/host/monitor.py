#!/usr/bin/env python3
"""ROB3 Teachbox test host monitor.

Reads the serial output of the led_test or keypad_test Arduino sketch and
prints it (optionally logging to a file). This is the "Python script running
on a modern PC" side of the bring-up test described in
hardware/teachbox/test.md.

Requires pyserial:  pip install pyserial

Examples:
    python3 monitor.py --port /dev/ttyACM0
    python3 monitor.py --port COM3 --baud 9600 --log run.log
"""
import argparse
import sys
import time


def main() -> int:
    parser = argparse.ArgumentParser(description="ROB3 Teachbox serial monitor")
    parser.add_argument("--port", required=True,
                        help="serial port (e.g. /dev/ttyACM0, /dev/ttyUSB0, COM3)")
    parser.add_argument("--baud", type=int, default=9600,
                        help="baud rate (sketches use 9600)")
    parser.add_argument("--log", default=None,
                        help="optional path to also append output to")
    args = parser.parse_args()

    try:
        import serial  # pyserial
    except ImportError:
        print("ERROR: pyserial not installed. Run: pip install pyserial",
              file=sys.stderr)
        return 2

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except serial.SerialException as exc:
        print(f"ERROR: could not open {args.port}: {exc}", file=sys.stderr)
        return 1

    logfile = open(args.log, "a", encoding="utf-8") if args.log else None
    print(f"[monitor] {args.port} @ {args.baud} baud — Ctrl-C to quit")
    # Give the UNO time to reset after the port opens.
    time.sleep(2)

    try:
        while True:
            raw = ser.readline()
            if not raw:
                continue
            line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
            stamp = time.strftime("%H:%M:%S")
            out = f"{stamp}  {line}"
            print(out)
            if logfile:
                logfile.write(out + "\n")
                logfile.flush()
    except KeyboardInterrupt:
        print("\n[monitor] stopped")
    finally:
        ser.close()
        if logfile:
            logfile.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
