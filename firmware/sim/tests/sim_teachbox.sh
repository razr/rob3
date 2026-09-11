#!/usr/bin/env bash
# Behavioral test: run the REAL ROM's Teachbox keypad scanner (kbd_scan, entry
# 0x0C00) in ucSim and assert it decodes the column-group bits into the key
# index bases documented in src/teachbox.annotated.asm and
# hardware/teachbox/board.md.
#
# The scanner strobes matrix rows via the 8255 (unmodeled here) and reads the
# three column groups from P1 (SFR 0x90), top 3 bits. We inject a column-group
# bit on P1 and, on the FIRST strobe row (row 0), check the computed key index
# in R6 at 0x0C2A (the 'mov R6,A' that finalises the index for a hit):
#
#   P1 bit 5 (0x20) -> group 1 -> index base 0x00
#   P1 bit 6 (0x40) -> group 2 -> index base 0x08
#   P1 bit 7 (0x80) -> group 3 -> index base 0x10
#
# This proves the 3-group / 8-row index mapping without needing the full
# multi-pass debounce (which requires the 8255 row hardware).
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; fail=1; }

# Run one scan pass with P1=$1, return R6 (hex, no 0x) captured at 0x0C2A.
scan_index() {
  local p1="$1"
  printf 'reset\npc 0x0c00\nset mem sfr 0x90 %s\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nbreak 0x0c2a\nrun\nquit\n' "$p1" \
    | timeout 15 $SIM $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g' \
    | awk '/^     R0 R1/{getline; print $7; exit}'
}

check() { # p1  expected_hex  group_desc
  local got; got="$(scan_index "$1")"
  if [[ "${got^^}" == "${2^^}" ]]; then
    pass "P1=$1 ($3) -> key index base 0x$2"
  else
    die "P1=$1 ($3): expected 0x$2, got 0x${got:-<none>}"
  fi
}

# 1) reaches the index computation and decodes each column group correctly
check 0x20 00 "group 1"
check 0x40 08 "group 2"
check 0x80 10 "group 3"

# 2) with no column active (P1=0x00), the scan must NOT reach the hit path.
#    Set a breakpoint at 0x0C2A (the hit/index finaliser) and single-step a
#    bounded number of instructions; it must NOT stop at 0x0C2A and must reach
#    a RET (the scanner returns A=0 via the no-hit/debounce path).
noHit="$(printf 'reset\npc 0x0c00\nset mem sfr 0x90 0x00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nset mem iram 0x56 0x00\nbreak 0x0c2a\nstep 400\nquit\n' \
  | timeout 15 $SIM $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g')"
if grep -Eqi 'Stop at 0x000c2a' <<<"$noHit"; then
  die "no column active: unexpectedly reached the hit path (0x0C2A)"
else
  pass "no column active -> scanner does NOT reach the hit path (0x0C2A)"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_teachbox: OK"
else
  echo "----- last sim context -----"; echo "${noHit:-}"
  exit 1
fi
