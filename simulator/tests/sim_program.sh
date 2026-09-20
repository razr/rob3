#!/usr/bin/env bash
# Behavioral test: the ROB3 stored-PROGRAM interpreter (annotated in
# firmware/src/annotated/program_interpreter.annotated.asm).
#
# Crafts instruction bytes in external SRAM (page 0x81 = 0x8100), points the
# program counter (IRAM 0x66:0x67) at them, enters the executor prog_exec
# (0x0941), and asserts the fetch/decode/apply/advance behaviour.
#
# Runs on stock s51 (pure firmware, no cl_hw modules needed — we drive the
# executor directly and seed XRAM/IRAM).
set -euo pipefail

SIM="${SIM:-s51}"
SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

fail=0
pass() { echo "PASS  $1"; }
die()  { echo "FAIL  $1"; echo "----- sim output -----"; echo "${2:-}"; fail=1; }
run_sim() { timeout 20 $SIM $SIMFLAGS "$SAFEHEX" 2>&1 | sed 's/\x1b\[0K//g'; }
row() { grep -E "^0x$1" <<<"$2" | tail -1 | awk '{$1="";print}' | sed 's/^ *//'; }

# --- 1) fetch + 8-byte slot advance (POS-all opcode 0x47) ---------------------
O1="$(printf 'reset\nset mem xram 0x8100 0x47 0x10 0x20 0x30 0x40 0x50 0x60 0x00\nset mem iram 0x66 0x00\nset mem iram 0x67 0x81\nset mem iram 0x28 0x02\nset mem iram 0x26 0x00\npc 0x0941\nbreak 0x0a0b\nstep 120\ndump iram 0x27 0x27\ndump iram 0x66 0x67\nquit\n' | run_sim)"
if [[ "$(row 27 "$O1" | awk '{print $1}')" == "47" ]]; then
  pass "exec: opcode fetched into 0x27 (=0x47)"
else die "exec: opcode not fetched into 0x27" "$O1"; fi
if [[ "$(row 66 "$O1" | awk '{print $1,$2}')" == "08 81" ]]; then
  pass "exec: PC advanced 0x8100 -> 0x8108 (8-byte instruction slot)"
else die "exec: PC did not advance by 8" "$O1"; fi

# --- 2) store-current-position (opcode 0x07, all axes) -> 0x50..0x55 ----------
O2="$(printf 'reset\nset mem xram 0x8100 0x07 0xA1 0xA2 0xA3 0xA4 0xA5 0xA6 0x00\nset mem iram 0x50 0 0 0 0 0 0\nset mem iram 0x66 0x00\nset mem iram 0x67 0x81\nset mem iram 0x28 0x02\nset mem iram 0x26 0x00\npc 0x0941\nbreak 0x0a0b\nstep 120\ndump iram 0x50 0x55\nquit\n' | run_sim)"
if [[ "$(row 50 "$O2" | awk '{print $1,$2,$3,$4,$5,$6}')" == "a1 a2 a3 a4 a5 a6" ]]; then
  pass "exec: store-position (0x07) copies 6 operands -> current pos 0x50..0x55"
else die "exec: store-position 0x07 mismatch" "$O2"; fi

# --- 3) program-end: opcode with bit7 set stops (reaches 0x094D end branch) ---
O3="$(printf 'reset\nset mem xram 0x8100 0x80\nset mem iram 0x66 0x00\nset mem iram 0x67 0x81\nset mem iram 0x28 0x0e\nset mem iram 0x26 0x00\npc 0x0941\nbreak 0x094d\nbreak 0x0a0b\nstep 30\ndump iram 0x27 0x27\nquit\n' | run_sim)"
if grep -qi 'stop at 0x00094d' <<<"$O3" && [[ "$(row 27 "$O3" | awk '{print $1}')" == "80" ]]; then
  pass "exec: end-marker opcode (bit7 set, 0x80) reaches the program-end branch"
else die "exec: end-marker not handled" "$O3"; fi

# --- 4) label resolver: prog_goto maps label m -> PC from the page-0x80 table -
# label table at 0x8000: label 2 -> entry at 0x8004/0x8005 = (lo,hi). Set = 0x34,0x81
# then call prog_goto with R0=2 (bank0 R0 = iram 0x00), expect 0x66:0x67 = 34 81.
O4="$(printf 'reset\nset mem xram 0x8004 0x34\nset mem xram 0x8005 0x81\nset mem iram 0x3e 0x80\nset mem iram 0x00 0x02\nset mem iram 0x66 0x00\nset mem iram 0x67 0x00\npc 0x0a33\nbreak 0x0a41\nstep 20\ndump iram 0x66 0x67\nquit\n' | run_sim)"
if [[ "$(row 66 "$O4" | awk '{print $1,$2}')" == "34 81" ]]; then
  pass "goto: label 2 resolved to PC 0x8134 (2-byte label table at page 0x80)"
else die "goto: label resolve mismatch" "$O4"; fi

if [[ $fail -eq 0 ]]; then
  echo "sim_program: OK"
else
  exit 1
fi
