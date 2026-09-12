#!/usr/bin/env bash
# Behavioral test for the COMPILED ucSim ADC peripheral (cl_adc).
#
# The ROB3 firmware init blocks at 0x0680 (JB 0x22.0) waiting for the axis-servo
# ISR, which only runs on the ADC's end-of-conversion (EOC -> INT1). On a stock
# s51 that pulse never arrives, so sim_run.sh has to hand-inject IRAM 0x22 to
# fake it. This test proves the REAL hardware model does the job instead: with
# the cl_adc module compiled in, a plain `reset; run` (only forcing P3.0=0 for
# the fixed-baud path, which is a serial-line condition, not an ADC one) reaches
# the main loop 0x074D on its own, because the ADC asserts EOC->INT1 and the
# servo ISR (0x00C0) actually executes.
#
# This REQUIRES the custom ucsim_51 built with the adc module (see
# ../ucsim-modules/README.md). It is OPT-IN: if that binary (or the element) is
# not found the test SKIPS (exit 0) so the default `make test` on a stock s51
# still passes.
#
# Point it at the binary via UCSIM_51=/path/to/ucsim_51, or it probes:
#   $UCSIM_51, ucsim_51 on PATH, ~/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51
set -euo pipefail

SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

find_ucsim51() {
  if [[ -n "${UCSIM_51:-}" && -x "${UCSIM_51}" ]]; then echo "$UCSIM_51"; return; fi
  if command -v ucsim_51 >/dev/null 2>&1; then command -v ucsim_51; return; fi
  local p="$HOME/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51"
  [[ -x "$p" ]] && { echo "$p"; return; }
  echo ""
}

UCSIM_51="$(find_ucsim51)"
if [[ -z "$UCSIM_51" ]]; then
  echo "SKIP  sim_adc: custom ucsim_51 (adc cl_hw) not found"
  echo "      build it per ../ucsim-modules/README.md, or set UCSIM_51=/path/to/ucsim_51"
  echo "sim_adc: SKIPPED"
  exit 0
fi

# Confirm the module is compiled in; the adc command echoes a state line.
if ! printf 'set hardware adc\nquit\n' | "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>/dev/null \
     | sed 's/\x1b\[0K//g' | grep -qi 'adc\['; then
  echo "SKIP  sim_adc: ucsim_51 has no 'adc' hardware element"
  echo "sim_adc: SKIPPED"
  exit 0
fi

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "${OUT:-}"; fail=1; }

# 1) FREE-RUN: from reset, with only P3.0=0 (fixed-baud) and NO ADC injection,
#    init must reach the main loop 0x074D because the ADC drives EOC->INT1.
OUT="$(printf 'reset\nset mem sfr 0xb0 0x00\nbreak 0x074d\nrun 3000000\ndump sfr 0xa8 0xa8\nquit\n' \
  | timeout 30 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"
if grep -Eqi 'Stop at 0x00074d' <<<"$OUT"; then
  pass "free-run reaches main loop 0x074D via ADC EOC->INT1 (no hand-injection)"
else
  die "expected free-run to reach 0x074D (ADC model should drive INT1)"
fi

# 2) The axis-servo ISR (0x00C0) actually executes on its own (the EOC target).
OUT="$(printf 'reset\nset mem sfr 0xb0 0x00\nbreak 0x00c0\nrun 3000000\nquit\n' \
  | timeout 30 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"
if grep -Eqi 'Stop at 0x0000c0' <<<"$OUT"; then
  pass "axis-servo ISR (0x00C0) fires from a natural EOC->INT1"
else
  die "expected the servo ISR at 0x00C0 to run (EOC->INT1 not asserted?)"
fi

# 3) A seeded feedback value flows through the ADC read in the servo ISR. The
#    ISR feedback path does MOV DPH,#0x59 / MOVX A,@DPTR (0x00D8) to read the
#    ADC; breaking right after (0x00D9) the accumulator must equal the seeded
#    value. Seed all channels so it holds regardless of which channel the
#    round-robin is servicing when the break hits.
OUT="$(printf 'reset\nset hardware adc 0 0x5a\nset hardware adc 1 0x5a\nset hardware adc 2 0x5a\nset hardware adc 3 0x5a\nset hardware adc 4 0x5a\nset hardware adc 5 0x5a\nset hardware adc 6 0x5a\nset hardware adc 7 0x5a\nset mem sfr 0xb0 0x00\nbreak 0x00d9\nrun 3000000\ndump sfr 0xe0 0xe0\nquit\n' \
  | timeout 30 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"
if grep -Eqi '0xe0 ACC:.*0x5a' <<<"$OUT"; then
  pass "seeded ADC feedback (0x5A) flows through the servo-ISR MOVX read (ACC=0x5A)"
else
  die "expected ACC=0x5A after the servo-ISR ADC read at 0x00D8"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_adc: OK"
else
  exit 1
fi
