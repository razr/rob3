#!/usr/bin/env bash
# Repro for issue 003: ucSim's MCS-51 UART never drives the RXD pin, so ROB3's
# software auto-baud loop (which polls the raw P3.0 pin) spins forever.
#
# Shows: on the auto-detect path (P3.0=1), after a large `step`, the PC is stuck
# at the 0x06BF RXD start-bit spin and IE never reaches 0x17 (ES enabled).
#
# Needs the ROB3 `adc` cl_hw module so init reaches the baud branch, and a
# loader-enabled ucsim_51. Set:
#   SIM=/path/to/ucsim_51  (loader build)
#   ADC=/path/to/adc.so
#   HEX=/path/to/@-free rob3.hex
set -euo pipefail

SIM="${SIM:-$HOME/github/razr/ucsim/src/sims/s51.src/ucsim_51}"
HEX="${HEX:-$(cd "$(dirname "$0")/../../.." && pwd)/simulator/build/rob3.hex}"
ADC="${ADC:-$(cd "$(dirname "$0")/../../.." && pwd)/simulator/ucsim-modules/adc/adc.so}"

read -r -d '' S <<EOF || true
loadhw "$ADC"
reset
break 0x06a7
run
set mem sfr 0xb0 0x01
clear
step 500000
where
dump sfr 0xa8 0xa8
quit
EOF

OUT="$(printf '%s\n' "$S" | timeout 30 "$SIM" -t 51 -X 11.0592M "$HEX" 2>&1 | sed 's/\x1b\[0K//g')"
echo "$OUT" | grep -iE 'stop at|0x06bf|^0xa8' | tail -5

if echo "$OUT" | grep -qi '0x0006bf'; then
  echo "REPRO OK: stuck at 0x06BF (RXD start-bit spin) — UART never drove P3.0"
else
  echo "NOTE: did not observe the 0x06BF spin (fixed? or different build)"
fi
