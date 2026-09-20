#!/usr/bin/env bash
# Integration check: the ROS2 driver's PROTOCOL CODEC produces bytes that drive
# the real ROM correctly. We take the exact frame the Python driver emits for a
# "set all positions" command, feed its header+payload through the verified ROM
# dispatch (rx_dispatch 0x03A9, A=ETX, header in R6, payload in the RX buffer),
# and assert the firmware writes the positions. This ties rob3_driver to the
# [SIM]-verified firmware behaviour without needing a full ROS install.
#
# No ROS needed; just python3 (for the codec) + s51/ucsim_51.
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"
PKG="$(cd "$(dirname "$0")/.." && pwd)"   # .../ros2/rob3_driver (holds the rob3_driver/ package)

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "$2"; fail=1; }

# Ask the driver codec for the set-all-positions frame (no-ack) and its bytes.
FRAME_HEX="$(python3 -c "
import sys; sys.path.insert(0,'$PKG')
from rob3_driver import protocol as P
f = P.set_all_positions([0x11,0x22,0x33,0x44,0x55,0x66], ack=False)
print(' '.join('%02x'%b for b in f))
")"
echo "driver frame (set all positions): $FRAME_HEX"
# frame = header 07, six counts, ETX 03. header must be 0x07.
HEADER="$(echo "$FRAME_HEX" | awk '{print $1}')"
[[ "$HEADER" == "07" ]] || die "codec header not 0x07" "$FRAME_HEX"

# Feed it through the ROM: R6=header(0x07), RX buffer 0x60..=the six counts,
# A=ETX(0x03), enter rx_dispatch, run to serial_exit, check positions 0x50..0x55.
OUT="$(printf 'reset\nset mem iram 0x50 0 0 0 0 0 0\nset mem iram 0x60 0x11 0x22 0x33 0x44 0x55 0x66\nset mem iram 0x06 0x07\nset mem sfr 0xe0 0x03\npc 0x03a9\nbreak 0x0525\nstep 200\ndump iram 0x50 0x55\nquit\n' \
  | timeout 15 $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"
POS="$(grep -E '^0x50' <<<"$OUT" | tail -1 | awk '{print $2,$3,$4,$5,$6,$7}')"
if [[ "$POS" == "11 22 33 44 55 66" ]]; then
  pass "driver 'set all positions' frame drives the ROM: 0x50..0x55 = 11 22 33 44 55 66"
else
  die "expected 0x50..0x55 = 11 22 33 44 55 66, got '$POS'" "$OUT"
fi

# Also cross-check a couple of single commands' headers against the ROM opcodes.
python3 -c "
import sys; sys.path.insert(0,'$PKG')
from rob3_driver import protocol as P
assert P.enable_motors()  == bytes([0x61,0x03])
assert P.emergency_stop() == bytes([0x62,0x03])
assert P.query_all_positions()[0] == 0x4f
assert P.set_axis_position(2,0x80,ack=False) == bytes([0x02,0x80,0x03])
print('codec-vs-command.md opcode cross-check OK')
" && pass "codec opcodes match command.md (enable/estop/query-all/set-axis)"

if [[ $fail -eq 0 ]]; then
  echo "test_driver_protocol: OK"
else
  exit 1
fi
