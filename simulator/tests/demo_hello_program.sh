#!/usr/bin/env bash
# DEMO: a "hello world" ROB3 stored program — load it into SRAM and run it.
#
# The ROB3 has no display, so the simplest observable program is:
#     MOVE axis 0 to position 0x80   (mid-travel)
#     MOVE axis 1 to position 0x40
#     END
# We hand-assemble it using the verified instruction encoding (see
# firmware/src/annotated/program_interpreter.annotated.asm), load the bytes into
# external SRAM (the program store, page 0x81 = 0x8100), point the program
# counter at it, and drive the executor (prog_exec, 0x0941) instruction by
# instruction — asserting each move lands in the axis target table and the END
# opcode stops the program.
#
# Instruction encoding used (8-byte slots):
#   single-axis MOVE:  opcode 0x60|axis  (.6=1 .5=1), then target byte, padded.
#     axis 0 -> target 0x40 ; axis 1 -> target 0x41 ; ...
#   END:               any opcode with bit 7 set (we use 0x80).
#
# Runs on stock s51 (pure firmware; no cl_hw modules needed).
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "${2:-}"; fail=1; }
run_sim() { timeout 20 $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g'; }
row() { grep -E "^0x$1" <<<"$2" | tail -1 | awk '{$1="";print}' | sed 's/^ *//'; }

echo "Hello-world program (hand-assembled):"
echo "  0x8100: 60 80 00 00 00 00 00 00   ; MOVE axis0 -> 0x80"
echo "  0x8108: 61 40 00 00 00 00 00 00   ; MOVE axis1 -> 0x40"
echo "  0x8110: 80                        ; END"
echo

# Load the program into SRAM, set the run state, and step the executor three
# times (instr1, instr2, END). Each prog_exec pass runs one instruction and
# returns; we re-enter it at the advanced PC. Dumps after each pass.
prog_setup='set mem xram 0x8100 0x60 0x80 0x00 0x00 0x00 0x00 0x00 0x00
set mem xram 0x8108 0x61 0x40 0x00 0x00 0x00 0x00 0x00 0x00
set mem xram 0x8110 0x80
set mem iram 0x40 0 0 0 0 0 0
set mem iram 0x66 0x00
set mem iram 0x67 0x81
set mem iram 0x28 0x0e
set mem iram 0x26 0x00'

# --- pass 1: MOVE axis0 -> 0x80 ----------------------------------------------
O1="$(printf '%s\npc 0x0941\nbreak 0x0a0b\nstep 150\ndump iram 0x40 0x45\ndump iram 0x66 0x67\nquit\n' "$prog_setup" | run_sim)"
a0="$(row 40 "$O1" | awk '{print $1}')"; pc1="$(row 66 "$O1" | awk '{print $1,$2}')"
if [[ "$a0" == "80" && "$pc1" == "08 81" ]]; then
  pass "instr 1: axis0 target = 0x80, PC -> 0x8108"
else die "instr 1 failed (axis0=$a0 pc=$pc1)" "$O1"; fi

# --- pass 2: MOVE axis1 -> 0x40 (start from PC=0x8108) -----------------------
O2="$(printf 'set mem xram 0x8100 0x60 0x80 0x00 0x00 0x00 0x00 0x00 0x00\nset mem xram 0x8108 0x61 0x40 0x00 0x00 0x00 0x00 0x00 0x00\nset mem xram 0x8110 0x80\nset mem iram 0x40 0x80 0 0 0 0 0\nset mem iram 0x66 0x08\nset mem iram 0x67 0x81\nset mem iram 0x28 0x0e\nset mem iram 0x26 0x00\npc 0x0941\nbreak 0x0a0b\nstep 150\ndump iram 0x40 0x45\ndump iram 0x66 0x67\nquit\n' | run_sim)"
a1="$(row 40 "$O2" | awk '{print $2}')"; pc2="$(row 66 "$O2" | awk '{print $1,$2}')"
if [[ "$a1" == "40" && "$pc2" == "10 81" ]]; then
  pass "instr 2: axis1 target = 0x40, PC -> 0x8110"
else die "instr 2 failed (axis1=$a1 pc=$pc2)" "$O2"; fi

# --- pass 3: END (from PC=0x8110) -> program stops ---------------------------
O3="$(printf 'set mem xram 0x8110 0x80\nset mem iram 0x66 0x10\nset mem iram 0x67 0x81\nset mem iram 0x28 0x0e\nset mem iram 0x26 0x00\npc 0x0941\nbreak 0x094d\nbreak 0x0a0b\nstep 40\ndump iram 0x27 0x27\ndump iram 0x28 0x28\nquit\n' | run_sim)"
if grep -qi 'stop at 0x00094d' <<<"$O3"; then
  s28="$(row 28 "$O3" | awk '{print $1}')"
  pass "instr 3: END opcode (0x80) reached the program-end branch (0x28=0x$s28)"
else die "instr 3 (END) did not stop the program" "$O3"; fi

# --- AUTO: prove the program self-runs from the MAIN LOOP (opt-in) -----------
# With a loader ucsim_51 + the adc module, init reaches the main loop and the
# main-loop motion_exec (0x08FF) fetches/executes the program with no manual
# prog_exec entry. This is the true "load and run".
UCSIM_51="${UCSIM_51:-$HOME/github/razr/ucsim/src/sims/s51.src/ucsim_51}"
ADC="$(cd "$(dirname "$0")/.." && pwd)/ucsim-modules/adc/adc.so"
if [ -x "$UCSIM_51" ] && [ -f "$ADC" ] && \
   printf 'loadhw "%s"\nquit\n' "$ADC" | timeout 10 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | grep -qi 'id_string=adc'; then
  AO="$(printf 'loadhw "%s"\nreset\nset mem sfr 0xb0 0x00\nbreak 0x074d\nrun\nclear\nset mem sfr 0xb0 0xfe\nset mem xram 0x8100 0x60 0x80 0x00 0x00 0x00 0x00 0x00 0x00\nset mem xram 0x8108 0x80\nset mem iram 0x66 0x00\nset mem iram 0x67 0x81\nset mem iram 0x40 0x00\nset mem iram 0x28 0x0e\nset mem iram 0x26 0x00\nbreak 0x0a0b\nstep 200000\ndump iram 0x40 0x40\nquit\n' "$ADC" \
    | timeout 45 "$UCSIM_51" $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g')"
  if [[ "$(row 40 "$AO" | awk '{print $1}')" == "80" ]]; then
    pass "AUTO: program self-ran from the main loop -> axis0 target = 0x80 (no manual prog_exec)"
  else
    die "AUTO: main-loop self-execution did not set axis0" "$AO"
  fi
else
  echo "SKIP  AUTO self-run (needs loader ucsim_51 + adc module)"
fi

echo
if [[ $fail -eq 0 ]]; then
  echo "demo_hello_program: OK — program loaded, ran, moved axes 0/1, and ended."
else
  exit 1
fi
