#!/usr/bin/env bash
# Behavioral test: prove the ROB3 RS-232 SOFTWARE AUTO-BAUD brings the UART up,
# using the `rxd` cl_hw module to drive the P3.0 (RXD) pin at bit level (which
# ucSim's byte-level core UART does not do — see issues/003).
#
# Flow:
#   1) reach the auto-detect start-bit spin (0x06BF) on the P3.0=1 path;
#   2) shift the training byte 0x20 on P3.0 at the LOCK bit time (128 machine
#      cycles/bit at 11.0592 MHz);
#   3) assert the firmware completes auto-detect at 0x073C, with:
#        - TH1 (0x8D) = 0xFC   (derived baud reload)
#        - TCON.6 (TR1) set    (baud timer running; TCON top nibble 0xF)
#        - IE (0xA8) = 0x17    (ES serial interrupt enabled)
#
# NOTE ON BAUD (documented in ucsim-modules/rxd/README.md + issues/003):
#   The host in hardware/host/README.md uses 9600 8N1. In THIS ucSim model the
#   auto-detect validation window is cyc/bit ~ [104,152] (training ~6.1-8.9 kbaud
#   as machine-cycle time), centred ~128 (~7200); 9600 (96 cyc/bit) lands just
#   below and does NOT lock. We therefore drive the lock point (128 cyc/bit).
#   The firmware always derives TH1=0xFC regardless of where in the window the
#   training byte lands. The absolute-baud vs cyc/bit scaling difference (real
#   9600 vs the model's ~7200 lock) is a modelling artifact of representing the
#   training edges in machine cycles; the important, verified fact is that the
#   auto-baud path RUNS TO COMPLETION and arms the UART.
#
# Requires a loader-enabled ucsim_51 plus the adc + rxd cl_hw modules. SKIPS
# cleanly if they are absent, so a stock-s51 `make test` still passes.
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"
UCSIM_51="${UCSIM_51:-$HOME/github/razr/ucsim/src/sims/s51.src/ucsim_51}"

here="$(cd "$(dirname "$0")/.." && pwd)"
ADC="$here/ucsim-modules/adc/adc.so"
RXD="$here/ucsim-modules/rxd/rxd.so"

skip() { echo "SKIP  $1"; echo "sim_serial_autobaud: SKIPPED"; exit 0; }

[ -x "$UCSIM_51" ] || skip "loader-enabled ucsim_51 not found (set UCSIM_51)"
[ -f "$ADC" ] || skip "adc.so not built (make -C ucsim-modules)"
[ -f "$RXD" ] || skip "rxd.so not built (make -C ucsim-modules)"

# Confirm this binary can loadhw (older builds have no loader)
probe="$(printf 'loadhw "%s"\nquit\n' "$RXD" | timeout 10 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g' || true)"
grep -qi 'id_string=rxd' <<<"$probe" || skip "ucsim_51 cannot loadhw the rxd module"

read -r -d '' S <<EOF || true
loadhw "$ADC"
loadhw "$RXD"
reset
break 0x06bf
run
clear
break 0x073c
set hardware rxd 0x20 128
step 40000
dump sfr 0x8d 0x8d
dump sfr 0x88 0x88
dump sfr 0xa8 0xa8
quit
EOF
OUT="$(printf '%s\n' "$S" | timeout 30 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "$OUT"; fail=1; }

grep -qi 'stop at 0x00073c' <<<"$OUT" \
  && pass "auto-baud completes: reached 0x073C (init_finish) after training byte 0x20" \
  || die "auto-baud did not complete (never reached 0x073C)"

grep -Eqi '^0x8d TH1:.*0xfc' <<<"$OUT" \
  && pass "derived TH1 = 0xFC (baud reload)" \
  || die "expected TH1 = 0xFC"

# TR1 = TCON.6: after lock TCON top nibble is 0xF (TF1|TR1|TF0|TR0)
tcon="$(grep -E '^0x88 TCON' <<<"$OUT" | awk '{print $4}')"
if [[ -n "$tcon" ]] && (( (0x${tcon#0x} & 0x40) == 0x40 )); then
  pass "Timer 1 running (TR1 set; TCON=$tcon)"
else
  die "expected TR1 (TCON.6) set, got TCON=$tcon"
fi

grep -Eqi '^0xa8 IE:.*0x17' <<<"$OUT" \
  && pass "serial interrupt enabled: IE = 0x17 (ES+EX1+ET0+EX0)" \
  || die "expected IE = 0x17"

if [[ $fail -eq 0 ]]; then
  echo "sim_serial_autobaud: OK"
else
  exit 1
fi
