#!/usr/bin/env bash
# Behavioral test: drive the REAL ROM init PAST its hardware gates and prove it
# completes into the main loop at 0x074D with the expected post-init state.
#
# Two external stimuli are injected to stand in for absent hardware:
#   1) INT1 gate at 0x0680 (JB 0x22.0 / JNB 0x22.0): the axis-servo ISR would
#      toggle bit 0x22.0 on the ADC EOC. We emulate that by clearing then
#      setting IRAM 0x22 across the two waits.
#   2) Baud branch at 0x06A7 (JB P3.0): we force P3.0 = 0 so the FIXED-baud
#      path is taken (MOV IE,#0x07 ; AJMP init_finish), avoiding the serial
#      auto-detect loop that waits on a live P3.0 edge.
#
# Expected end state (matches firmware/src/annotated/main.annotated.asm):
#   - execution reaches the final init instruction 0x074B (SETB EA), i.e. the
#     main-loop entry 0x074D is next (0x074B chosen as the completion marker
#     because SETB EA then immediately vectors to a pending ISR)
#   - axis speed table 0x48..0x4D = 01 01 01 01 01 01  (step 11)
#   - IE = 0x07  (fixed path EX0+ET0+EX1; EA is set BY the 0x074B instruction)
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

read -r -d '' SCRIPT <<'EOF' || true
reset
pc 0x0600
break 0x0680
run
set mem iram 0x22 0x00
step 1
set mem iram 0x22 0x01
step 1
clear
break 0x06a7
run
clear
set mem sfr 0xb0 0x00
break 0x074b
run
dump iram 0x48 0x55
dump sfr 0xa8 0xa8
quit
EOF

OUT="$(printf '%s\n' "$SCRIPT" | timeout 30 $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "$OUT"; fail=1; }

# 1) reached the final init instruction 0x074B (SETB EA) -> init complete
if grep -Eqi "Stop at 0x00074b" <<<"$OUT"; then
  pass "init completed (reached final instruction 0x074B, main loop 0x074D next)"
else
  die "expected execution to reach 0x074B (end of init)"
fi

# 2) axis speed table 0x48..0x4D preset to 0x01 (first six bytes of the 0x48 row)
line48="$(grep -E '^0x48' <<<"$OUT" | tail -1)"
speeds="$(awk '{print $2,$3,$4,$5,$6,$7}' <<<"$line48")"
if [[ "$speeds" == "01 01 01 01 01 01" ]]; then
  pass "axis speed table 0x48..0x4D = 01 x6"
else
  die "expected 0x48..0x4D = 01 x6 (got '$speeds')"
fi

# 3) IE = 0x07 at 0x074B (fixed-baud path EX0+ET0+EX1; EA not yet set)
if grep -Eqi "0xa8 IE:.*0x07" <<<"$OUT"; then
  pass "IE = 0x07 (EX0+ET0+EX1; fixed-baud path, pre-SETB-EA)"
else
  die "expected IE = 0x07 at 0x074B"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_run: OK"
else
  exit 1
fi
