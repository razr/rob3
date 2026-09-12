#!/usr/bin/env bash
# Behavioral test: run the REAL ROM init in ucSim (s51) and assert that its
# runtime behavior matches firmware/src/annotated/main.annotated.asm.
#
# The init deliberately blocks at 0x0680 (JB 0x22.0) waiting for the EXT1
# (axis-servo) ISR, which only fires on the ADC's EOC -> INT1. With no ADC
# model, that pulse never arrives, so a bounded step run must END at 0x0680.
# That stall IS the expected, hardware-dependent behavior.
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

STEPS=400000
OUT="$(printf 'reset\npc 0x0600\nstep %d\ndump iram 0x20 0x2f\ndump iram 0x47 0x47\ndump sfr 0x81 0x81\ndump sfr 0xa8 0xa8\nquit\n' "$STEPS" \
      | $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "$OUT"; fail=1; }

# 1) init must stall at the ADC/INT1 gate (0x0680)
if grep -qi "Stop at 0x000680" <<<"$OUT"; then
  pass "init blocks at 0x0680 (JB 0x22.0 -> waits for ADC EOC/INT1)"
else
  die "expected stall at 0x0680 (ADC/INT1 wait)"
fi

# 2) stack pointer initialized to 0x31
if grep -Eqi "0x81 SP:.*0x31" <<<"$OUT"; then
  pass "SP = 0x31"
else
  die "expected SP = 0x31"
fi

# 3) IE = 0x84 (EA + EX1) — axis-servo interrupt enabled
if grep -Eqi "0xa8 IE:.*0x84" <<<"$OUT"; then
  pass "IE = 0x84 (EA + EX1)"
else
  die "expected IE = 0x84"
fi

# 4) axis rotation mask 0x22 has bit0 set (0x01) -> reason it is waiting
line20="$(grep -E '^0x20' <<<"$OUT" | tail -1)"
# columns after '0x20' are bytes 0x20..0x27; byte 0x22 is the 3rd value
b22="$(awk '{print $4}' <<<"$line20")"
if [[ "$b22" == "01" ]]; then
  pass "IRAM 0x22 = 0x01 (axis mask bit0 set)"
else
  die "expected IRAM 0x22 = 0x01 (got '$b22')"
fi

# 5) output shadow latch 0x47 = 0xFF
if grep -Eqi "0x47[[:space:]]+ff" <<<"$OUT"; then
  pass "IRAM 0x47 = 0xFF (output shadow latch)"
else
  die "expected IRAM 0x47 = 0xFF"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_init: OK"
else
  exit 1
fi
