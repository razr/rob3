#!/usr/bin/env bash
# Behavioral test for the COMPILED ucSim teachbox peripheral (cl_teachbox).
#
# Unlike sim_teachbox.sh — which injects P1 directly with `set mem sfr 0x90` —
# this test exercises the real hardware model: it presses a key with
#   set hardware teachbox <row> <group>
# and lets the REAL firmware scanner (kbd_scan, 0x0C00) strobe the matrix and
# read the columns from the module. It proves the module's strobe->row decode
# is calibrated to the firmware: the scanner must see the pressed column ONLY
# on the strobed row that matches <row>, i.e. at strobe 0x46 == (row<<4).
#
# This REQUIRES the custom ucsim_51 built with the teachbox module (see
# ../ucsim-modules/README.md). It is OPT-IN: if that binary is not found the
# test SKIPS (exit 0) so the default `make test` on a stock s51 still passes.
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
  echo "SKIP  sim_teachbox_module: custom ucsim_51 (teachbox cl_hw) not found"
  echo "      build it per ../ucsim-modules/README.md, or set UCSIM_51=/path/to/ucsim_51"
  echo "sim_teachbox_module: SKIPPED"
  exit 0
fi

# Confirm the module is actually compiled in; if not, skip rather than fail.
# (`info hw` doesn't list element names in this build, but the teachbox command
#  echoes a confirmation line — use that as the presence probe.)
if ! printf 'set hardware teachbox 0 1\nquit\n' | "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>/dev/null \
     | sed 's/\x1b\[0K//g' | grep -qi 'teachbox:'; then
  echo "SKIP  sim_teachbox_module: ucsim_51 has no 'teachbox' hardware element"
  echo "sim_teachbox_module: SKIPPED"
  exit 0
fi

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; fail=1; }

# Press <row>/<group>, run the scanner to the index-finalise (0x0C2A), and read
# the row strobe latch 0x46. The module must have driven the column only on the
# matching row, so the scanner stops with 0x46 == (row<<4).
strobe_at_hit() { # row group
  printf 'set hardware teachbox %s %s\nreset\npc 0x0c00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nbreak 0x0c2a\nrun\ndump iram 0x46 0x46\nquit\n' "$1" "$2" \
    | timeout 15 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g' \
    | awk '/^0x46/{print $2; exit}'
}

check_row() { # row group expected_strobe_hex
  local got; got="$(strobe_at_hit "$1" "$2")"
  if [[ "${got^^}" == "${3^^}" ]]; then
    pass "press row $1 group $2 -> scanner hit on row $1 (strobe 0x46=0x$got)"
  else
    die "press row $1 group $2: expected strobe 0x$3, got 0x${got:-<none>}"
  fi
}

# Each pressed row must be detected at strobe (row<<4). Cover all 8 decoder rows
# and all 3 column groups (the group only changes which P1 bit; the row is what
# strobed_row() decodes).
for r in 0 1 2 3 4 5 6 7; do
  printf -v exp '%02x' $(( r << 4 ))
  check_row "$r" 1 "$exp"
done
check_row 3 2 30
check_row 5 3 50

# Releasing (single-arg) must make the scanner find NO hit (never reaches 0x0C2A).
rel="$(printf 'set hardware teachbox 2 1\nset hardware teachbox 0\nreset\npc 0x0c00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nset mem iram 0x56 0x00\nbreak 0x0c2a\nstep 400\nquit\n' \
  | timeout 15 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g')"
if grep -Eqi 'Stop at 0x000c2a' <<<"$rel"; then
  die "release: scanner unexpectedly saw a key (reached 0x0C2A)"
else
  pass "release (no key) -> scanner finds no column hit"
fi

if [[ $fail -eq 0 ]]; then
  echo "sim_teachbox_module: OK"
else
  exit 1
fi
