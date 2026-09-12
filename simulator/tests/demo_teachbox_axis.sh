#!/usr/bin/env bash
# DEMO: teachbox -> axis motion, end-to-end, in the custom ucsim_51.
#
# Shows the three verified stages that connect a Teachbox key press to a robot
# axis moving, using the compiled teachbox cl_hw module:
#
#   1. set hardware teachbox <row> <group>   -> the module holds a key; the real
#      firmware scanner kbd_scan (0x0C00) detects it on the matching strobed row.
#   2. kbd_handle (0x0C80) axis-select        -> a numeric key index selects an
#      axis: R1 = 0x50+axis, mode 0x29 = 0x40 (POSITION).
#   3. kh_jog (0x0E26) jog                     -> +/- increments/decrements the
#      selected axis's position slot (@R1 = 0x50+axis), clamped 0x00..0xFF.
#
# NOTE (honest limitation): this drives the stages deterministically (pc/break)
# rather than free-running from reset. A plain `reset; run` does NOT reach the
# scanner because init stalls at the un-modelled ADC/INT1 gate, and the keypad
# DEBOUNCE (0x56/0x57 + flags 0x20.5/.6) needs several main-loop passes that are
# fiddly to reproduce free-standing. The module + scanner + handler + jog are
# each verified; this ties them into one visible "key -> axis moves" run.
#
# Requires the custom ucsim_51 (teachbox module). Opt-in / skips if absent.
# Point at it with UCSIM_51=/path/to/ucsim_51, else it probes PATH and the
# default source build dir. Not part of `make test`; run via `make demo-teachbox`.
set -euo pipefail

SIMFLAGS="${SIMFLAGS:--t 51 -X 11.0592M}"
SAFEHEX="${SAFEHEX:?SAFEHEX not set}"

find_ucsim51() {
  if [[ -n "${UCSIM_51:-}" && -x "${UCSIM_51}" ]]; then echo "$UCSIM_51"; return; fi
  if command -v ucsim_51 >/dev/null 2>&1; then command -v ucsim_51; return; fi
  local p="$HOME/github/danieldrotos/ucsim/src/sims/s51.src/ucsim_51"
  [[ -x "$p" ]] && echo "$p" || echo ""
}
U="$(find_ucsim51)"
if [[ -z "$U" ]] || ! printf 'set hardware teachbox 0 1\nquit\n' \
     | "$U" $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g' | grep -qi 'teachbox:'; then
  echo "SKIP  demo_teachbox_axis: custom ucsim_51 (teachbox cl_hw) not found"
  echo "demo_teachbox_axis: SKIPPED"
  exit 0
fi

echo "== Stage 1: press row 1 group 1; scanner detects it on row 1 =="
printf 'set hardware teachbox 1 1\nreset\npc 0x0c00\nset mem iram 0x47 0x00\nset mem iram 0x20 0x00\nbreak 0x0c2a\nrun\ndump iram 0x46 0x46\nquit\n' \
  | "$U" $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g' \
  | grep -iE 'teachbox:|^0x46' | sed 's/^/   /'

echo "== Stages 2+3: select axis 0 (key index 2), jog '+', watch position 0x50 =="
out="$(printf '%s\n' \
  'set hardware teachbox 1 1' \
  'reset' \
  'set mem iram 0x50 0x40' \
  'set mem iram 0x2a 0x00' \
  'set mem sfr 0xe0 0x02' \
  'pc 0x0c80' 'break 0x0cb1' 'run' \
  'dump iram 0x29 0x29' \
  'set mem sfr 0xd0 0x00' 'set mem sfr 0xe0 0x00' \
  'pc 0x0e26' 'break 0x0e40' 'break 0x0e2f' 'break 0x0e36' 'run' \
  'dump iram 0x50 0x50' \
  'quit' \
  | "$U" $SIMFLAGS "$SAFEHEX" 2>/dev/null | sed 's/\x1b\[0K//g')"

m29="$(awk '/^0x29/{v=$2} END{print v}' <<<"$out")"
p50="$(awk '/^0x50/{v=$2} END{print v}' <<<"$out")"
echo "   axis-select mode 0x29 = 0x${m29:-?} (expect 40 = POSITION)"
echo "   axis 0 position 0x50 : 0x40 -> 0x${p50:-?} (expect 41 after one '+' jog)"

if [[ "${m29^^}" == "40" && "${p50^^}" == "41" ]]; then
  echo "demo_teachbox_axis: OK  (key press -> axis 0 position moved 0x40 -> 0x41)"
else
  echo "demo_teachbox_axis: FAIL"
  echo "----- context -----"; echo "$out"
  exit 1
fi
