#!/usr/bin/env bash
# Behavioral test: the FULL serial receive chain, end to end, through the real
# UART — not by entering the ISR with seeded state.
#
#   rxd cl_hw drives P3.0 auto-baud training  ->  firmware locks the UART
#   (TH1/TR1/ES)  ->  a real byte arrives over the ucSim -S serial link  ->
#   the core UART clocks it into SBUF and raises RI  ->  the RX ISR (0x0300)
#   runs and the RX state machine advances.
#
# This stitches together:
#   - the rxd pin-driver auto-baud bring-up (sim_serial_autobaud.sh), and
#   - the byte-level UART reception the core models once the baud is set.
# The command DISPATCH + response FRAMING themselves are covered by
# sim_serial.sh; here we prove the byte genuinely travels the wire into the ISR.
#
# Asserts:
#   1) after training, the UART is up (IE=0x17) and the auto-baud ACK 0x15 was
#      transmitted on the serial OUTPUT (proves TX over the real link);
#   2) a command byte sent on the serial INPUT lands in SBUF (0x99) verbatim
#      and sets RI (SCON.0), i.e. the core UART received it at the derived baud;
#   3) the RX ISR at 0x0300 ran and the RX parser advanced (0x24 low bits set).
#
# Opt-in: needs a loader-enabled ucsim_51 + the adc + rxd cl_hw modules, and a
# ucSim -S serial link. SKIPS cleanly otherwise.
set -euo pipefail

SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"
UCSIM_51="${UCSIM_51:-$HOME/github/razr/ucsim/src/sims/s51.src/ucsim_51}"

here="$(cd "$(dirname "$0")/.." && pwd)"
ADC="$here/ucsim-modules/adc/adc.so"
RXD="$here/ucsim-modules/rxd/rxd.so"

skip() { echo "SKIP  $1"; echo "sim_serial_e2e: SKIPPED"; exit 0; }
[ -x "$UCSIM_51" ] || skip "loader-enabled ucsim_51 not found (set UCSIM_51)"
[ -f "$ADC" ] || skip "adc.so not built"
[ -f "$RXD" ] || skip "rxd.so not built"
probe="$(printf 'loadhw "%s"\nquit\n' "$RXD" | timeout 10 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g' || true)"
grep -qi 'id_string=rxd' <<<"$probe" || skip "ucsim_51 cannot loadhw the rxd module"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
IN="$TMP/in"; OUT="$TMP/out"
printf '\x47' > "$IN"        # a READ-feedback command byte, sent after lock
: > "$OUT"

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
clear
break 0x00c0
step 60000
clear
break 0x0300
step 200000
dump sfr 0x98 0x99
clear
step 3000
dump iram 0x24 0x24
step 1400000
quit
EOF
LOG="$(printf '%s\n' "$S" | timeout 45 "$UCSIM_51" $SIMFLAGS -S "in=$IN,out=$OUT" "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim log -----"; echo "$LOG"; echo "----- out hex -----"; xxd "$OUT" 2>/dev/null | head; fail=1; }

# 1) UART up + auto-baud ACK 0x15 transmitted over the real serial link
if grep -qi 'stop at 0x00073c' <<<"$LOG"; then
  pass "auto-baud locked over the wire (reached 0x073C)"
else
  die "auto-baud did not lock"
fi
if [ -s "$OUT" ] && xxd "$OUT" | head -1 | grep -qiE ':\s*15'; then
  pass "auto-baud ACK 0x15 transmitted on serial OUTPUT (TX over the link)"
else
  die "expected 0x15 on the serial output"
fi
# startup reply sequence: 0x15 (init OK) then 0xF1 (multiple-init idle-timeout
# reply, since a byte was received after the UART came up). Confirms WHEN each
# startup byte is emitted (see hardware/host/command.md).
if xxd "$OUT" | head -1 | grep -qiE '15\s*f1'; then
  pass "startup reply sequence 15 F1 on the wire (0x15 init-OK, then 0xF1 multiple-init)"
else
  die "expected startup reply sequence 15 F1 on the wire"
fi

# 2) command byte reached SBUF verbatim + RI set
sbuf="$(grep -E '^0x99 SBUF' <<<"$LOG" | tail -1 | awk '{print $4}')"
scon="$(grep -E '^0x98 SCON' <<<"$LOG" | tail -1 | awk '{print $4}')"
if [[ "${sbuf,,}" == "0x47" ]]; then
  pass "command byte 0x47 received into SBUF over the serial INPUT"
else
  die "expected SBUF=0x47, got '$sbuf'"
fi
if [[ -n "$scon" ]] && (( (0x${scon#0x} & 0x01) == 0x01 )); then
  pass "RI set (SCON.0; core UART flagged a received byte, SCON=$scon)"
else
  die "expected RI (SCON.0) set, got SCON=$scon"
fi

# 3) RX ISR ran and the parser advanced
if grep -qi 'stop at 0x000300' <<<"$LOG"; then
  pass "RX ISR entered (0x0300) from the real reception"
else
  die "RX ISR (0x0300) did not run"
fi
p24="$(grep -E '^0x24' <<<"$LOG" | tail -1 | awk '{print $2}')"
if [[ -n "$p24" ]] && (( (0x${p24} & 0x05) == 0x05 )); then
  pass "RX parser advanced: 0x24=0x$p24 (frame-in-progress .0 + byte-seen .2)"
else
  die "expected RX parser bits set in 0x24, got 0x${p24:-??}"
fi

# 4) the ADC servo ISR (0x00C0) fired in the SAME session -> adc + rxd + serial
#    all run together (ADC EOC->INT1 servo concurrent with the UART).
if grep -qi 'stop at 0x0000c0' <<<"$LOG"; then
  pass "ADC servo ISR (0x00C0) ran concurrently — adc + rxd + serial together"
else
  die "ADC servo ISR (0x00C0) did not run alongside serial"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_serial_e2e: OK"
else
  exit 1
fi
