#!/usr/bin/env bash
# Behavioral test: prove the RS-232 UART command protocol semantics annotated in
# firmware/src/annotated/rs232_serial.annotated.asm, by running the REAL ROM in
# ucSim and observing state.
#
# ucSim serial note (verified in src/sims/s51.src/serial.cc): `MOV A,SBUF`
# returns the model's internal s_in, and a write to SBUF sets s_out — neither is
# the SBUF SFR cell. So we cannot inject/observe bytes via `set/dump sfr 0x99`.
# Instead we enter each command path AFTER the SBUF read (seeding A / the RX
# buffer / feedback slots) and assert the resulting IRAM + registers. This
# isolates the DISPATCH + FRAMING semantics, which is what we want to pin down.
#
# Cases (all match hardware/host/README.md bench behavior where noted):
#   1) READ feedback (class-0, header 0x47): 0x58..0x5D copied to 0x69..0x6E,
#      header echoed to 0x68, R3=7, R1=0x68, TX buffer mode 0x25.1 set.
#   2) TX helper: streams the response buffer (R1++/R3--) then frames with
#      ETX = 0x03 (reaches 0x0553 = MOV SBUF,#0x03) after the last byte.
#   3) WRITE single-axis position (class-0, header 0x02): 0x60 -> 0x52 (axis 2),
#      ACK mode 0x25.7 set.
#   4) RESET-ACK: the main-loop idle-timeout (0x0785) stages R4 = 0xF1 and arms
#      0x25.3 — the documented `printf '\x20'` -> flood-of-0xF1 reply.
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "${2:-}"; fail=1; }

run_sim() { # stdin script -> stdout (ANSI-stripped)
  timeout 20 $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g'
}

# --- 1) READ feedback -> response buffer + TX arm -----------------------------
OUT1="$(printf 'reset\nset mem iram 0x58 0x11 0x22 0x33 0x44 0x55 0x66\nset mem iram 0x25 0x00\nset mem sfr 0xe0 0x47\npc 0x0440\nbreak 0x0525\nstep 60\ndump iram 0x68 0x6e\ndump iram 0x25 0x25\nquit\n' | run_sim)"
buf="$(grep -E '^0x68' <<<"$OUT1" | tail -1 | awk '{print $2,$3,$4,$5,$6,$7,$8}')"
tx="$(grep -E '^0x25' <<<"$OUT1" | tail -1 | awk '{print $2}')"
if [[ "$buf" == "47 11 22 33 44 55 66" ]]; then
  pass "read-feedback: 0x68..0x6E = 47 11 22 33 44 55 66 (header + 6 feedback)"
else
  die "read-feedback: expected '47 11 22 33 44 55 66', got '$buf'" "$OUT1"
fi
if [[ "${tx,,}" == "02" ]]; then
  pass "read-feedback: TX buffer mode armed (0x25 = 0x02, i.e. 0x25.1 set)"
else
  die "read-feedback: expected 0x25=0x02, got '$tx'" "$OUT1"
fi

# --- 2) TX helper streams buffer then frames ETX ------------------------------
# one call with R3=1 (last byte): must set 0x25.4 (0x25 -> 0x12)
OUT2a="$(printf 'reset\nset mem iram 0x68 0xaa\nset mem iram 0x25 0x02\nset mem iram 0x01 0x68\nset mem iram 0x03 0x01\npc 0x0541\nbreak 0x0550\nbreak 0x0556\nstep 30\ndump iram 0x25 0x25\nquit\n' | run_sim)"
tx2a="$(grep -E '^0x25' <<<"$OUT2a" | tail -1 | awk '{print $2}')"
if [[ "${tx2a,,}" == "12" ]]; then
  pass "tx-helper: last buffer byte sets end flag (0x25 = 0x12, 0x25.4 set)"
else
  die "tx-helper: expected 0x25=0x12 after last byte, got '$tx2a'" "$OUT2a"
fi
# next call (0x25.4 already set): must reach ETX at 0x0553 and clear 0x25.1
OUT2b="$(printf 'reset\nset mem iram 0x25 0x12\nset mem iram 0x01 0x69\npc 0x0541\nbreak 0x0553\nbreak 0x0556\nstep 30\ndump iram 0x25 0x25\nquit\n' | run_sim)"
if grep -Eqi 'Stop at 0x000553' <<<"$OUT2b"; then
  tx2b="$(grep -E '^0x25' <<<"$OUT2b" | tail -1 | awk '{print $2}')"
  if [[ "${tx2b,,}" == "00" ]]; then
    pass "tx-helper: after buffer, reaches ETX (0x0553=MOV SBUF,#0x03) and clears 0x25.1"
  else
    die "tx-helper: reached ETX but 0x25 not cleared (got '$tx2b')" "$OUT2b"
  fi
else
  die "tx-helper: expected to reach ETX path 0x0553" "$OUT2b"
fi

# --- 3) WRITE single-axis position --------------------------------------------
OUT3="$(printf 'reset\nset mem iram 0x50 0x00 0x00 0x00 0x00 0x00 0x00\nset mem iram 0x60 0x80\nset mem iram 0x25 0x00\nset mem sfr 0xe0 0x02\npc 0x0440\nbreak 0x0525\nstep 60\ndump iram 0x50 0x55\ndump iram 0x25 0x25\nquit\n' | run_sim)"
pos="$(grep -E '^0x50' <<<"$OUT3" | tail -1 | awk '{print $2,$3,$4,$5,$6,$7}')"
tx3="$(grep -E '^0x25' <<<"$OUT3" | tail -1 | awk '{print $2}')"
if [[ "$pos" == "00 00 80 00 00 00" ]]; then
  pass "write-position: axis 2 slot 0x52 = 0x80 (0x50..0x55 = 00 00 80 00 00 00)"
else
  die "write-position: expected '00 00 80 00 00 00', got '$pos'" "$OUT3"
fi
if [[ "${tx3,,}" == "80" ]]; then
  pass "write-position: ACK mode armed (0x25 = 0x80, i.e. 0x25.7 set)"
else
  die "write-position: expected 0x25=0x80, got '$tx3'" "$OUT3"
fi

# --- 4) RESET-ACK (main-loop idle-timeout) -> R4=0xF1, 0x25.3 -----------------
OUT4="$(printf 'reset\nset mem iram 0x23 0x80\nset mem iram 0x24 0x04\nset mem iram 0x18 0x01\nset mem iram 0x25 0x00\npc 0x0785\nbreak 0x0797\nstep 20\ndump iram 0x24 0x25\ninfo registers\nquit\n' | run_sim)"
r4="$(grep -A1 'R0 R1 R2 R3 R4 R5 R6 R7' <<<"$OUT4" | tail -1 | awk '{print $5}')"
row24="$(grep -E '^0x24' <<<"$OUT4" | tail -1 | awk '{print $2,$3}')"
if [[ "${r4,,}" == "f1" ]]; then
  pass "reset-ack: R4 = 0xF1 staged (documented reset reply, hardware/host/README.md)"
else
  die "reset-ack: expected R4=0xF1, got '$r4'" "$OUT4"
fi
# 0x24 low nibble cleared (parser reset) and 0x25.3 set (TX armed -> send R4)
if [[ "$row24" == "00 08" ]]; then
  pass "reset-ack: RX parser reset (0x24=0x00) and TX armed (0x25=0x08, 0x25.3 set)"
else
  die "reset-ack: expected 0x24=0x00 0x25=0x08, got '$row24'" "$OUT4"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_serial: OK"
else
  exit 1
fi
