#!/usr/bin/env python3
"""ROB3 motor test host console.

Reads the serial telemetry from the pot_reader or motor_control sketch and, in
interactive mode, forwards single keystrokes (F/B/0/etc.) to motor_control so
you can drive the axis from the PC keyboard.

Requires pyserial:  pip install pyserial

Examples:
    # just watch telemetry (pot_reader or motor_control):
    python3 monitor.py --port /dev/ttyACM0

    # drive motor_control: type F / B / 0 and Enter to send; 'q' quits:
    python3 monitor.py --port /dev/ttyACM0 --interactive
"""
import argparse
import sys
import threading
import time


def reader_loop(ser, logfile, stop):
    while not stop.is_set():
        try:
            raw = ser.readline()
        except Exception:
            break
        if not raw:
            continue
        line = raw.decode("utf-8", errors="replace").rstrip("\r\n")
        stamp = time.strftime("%H:%M:%S")
        out = f"{stamp}  {line}"
        print(out)
        if logfile:
            logfile.write(out + "\n")
            logfile.flush()


def main() -> int:
    p = argparse.ArgumentParser(description="ROB3 motor test serial console")
    p.add_argument("--port", required=True, help="serial port (/dev/ttyACM0, COM3, ...)")
    p.add_argument("--baud", type=int, default=9600, help="baud rate (sketches use 9600)")
    p.add_argument("--log", default=None, help="optional path to append output to")
    p.add_argument("--interactive", action="store_true",
                   help="forward keystrokes to the board (for motor_control)")
    args = p.parse_args()

    try:
        import serial  # pyserial
    except ImportError:
        print("ERROR: pyserial not installed. Run: pip install pyserial", file=sys.stderr)
        return 2

    try:
        ser = serial.Serial(args.port, args.baud, timeout=1)
    except serial.SerialException as exc:
        print(f"ERROR: could not open {args.port}: {exc}", file=sys.stderr)
        return 1

    logfile = open(args.log, "a", encoding="utf-8") if args.log else None
    print(f"[console] {args.port} @ {args.baud} baud"
          + (" — interactive (F/B/0, 'q' to quit)" if args.interactive else " — Ctrl-C to quit"))
    time.sleep(2)  # allow UNO auto-reset

    stop = threading.Event()
    t = threading.Thread(target=reader_loop, args=(ser, logfile, stop), daemon=True)
    t.start()

    try:
        if args.interactive:
            while True:
                cmd = input()
                if cmd.strip().lower() == "q":
                    break
                # send the first character (F/B/0/etc.) plus newline
                ch = (cmd[:1] or "\n")
                ser.write(ch.encode("ascii", errors="ignore"))
        else:
            while True:
                time.sleep(0.5)
    except (KeyboardInterrupt, EOFError):
        pass
    finally:
        stop.set()
        time.sleep(0.2)
        ser.close()
        if logfile:
            logfile.close()
        print("\n[console] stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
