#!/bin/bash
# WiFi coexistence (docs/pageflip.md section 6, phase 6).
#
# One radio, one channel. ESP-NOW peers must sit on the same channel and associating with an AP
# lets the AP choose it, so the pair stands aside while WiFi is up. What makes that more than
# politeness: the SDK transport's begin() runs its own end() first, and that end() disconnects WiFi
# and puts the mode back to off -- a book opened during a download would silently kill it.
#
# The guard is an ENTRY guard, not a suspend/resume state machine, and the reason is worth keeping
# in front of whoever changes this: WiFi.getMode() is the only signal there is, and PageFlip's own
# begin() puts the radio in WIFI_STA. With the link up, "is WiFi active" answers yes about this
# device's own pair. The question is therefore only ever asked with the link down.
#
# Reachable on hardware by exactly one route: Settings -> Network leaves the connection up for a
# parent to manage and does not reboot, unlike the seven other activities that raise WiFi. Join a
# network there, back out, open a book.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_wifi.sh [timeout=120]
set -e

TIMEOUT="${1:-120}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

fresh_root() {  # fresh_root <side>
  rm -rf "fs_pf_$1"
  mkdir -p "fs_pf_$1/screenshots" "fs_pf_$1/.crosspoint"
  cp -r fs_/books "fs_pf_$1/books"
  [ -f fs_/.crosspoint/recent.json ] && cp fs_/.crosspoint/recent.json "fs_pf_$1/.crosspoint/recent.json"
  return 0
}

for side in left right solo; do fresh_root "$side"; done
write_pair_settings left
write_pair_settings right

rm -f fs_/screenshots/pf-wifi-*.bmp fs_/screenshots/pf-wifi-*.png
rm -f fs_/screenshots/pf-solo-*.bmp fs_/screenshots/pf-solo-*.png
rm -f fs_/screenshots/pf-badged-*.bmp fs_/screenshots/pf-badged-*.png

# TWO reference walks, and the second one is not redundant. These screenshots are compared byte for
# byte, and the status-bar badge is part of the bytes: a suspended half is a pair that is configured
# and not connected, so it carries the badge, while the same half once the pair has formed does not.
# One reference could only ever match half the shots.
set +e
write_pair_settings solo
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-wifi-badged.log >/dev/null
BADGED_RC=$?
for shot in fs_/screenshots/pf-solo-*.bmp; do
  [ -f "$shot" ] && mv "$shot" "${shot/pf-solo-/pf-badged-}"
done

# And again with paired reading switched off entirely, for the shots taken once the pair is up.
# From a fresh root: the first walk left progress at the end of its six pages, and a reference that
# resumed there would be a walk through different pages.
fresh_root solo
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-wifi-solo.log >/dev/null
SOLO_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_wifi_left.script" 2>sim-wifi-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_wifi_right.script" 2>sim-wifi-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

shopt -s nullglob
for bmp in fs_/screenshots/pf-wifi-*.bmp fs_/screenshots/pf-solo-*.bmp fs_/screenshots/pf-badged-*.bmp; do
  png="${bmp%.bmp}.png"
  if [ ! -f "$png" ] || [ "$bmp" -nt "$png" ]; then
    python3 -c "from PIL import Image; Image.open('$bmp').save('$png')" 2>/dev/null && echo "converted: $png"
  fi
done
shopt -u nullglob

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip|WiFi' "sim-wifi-$side.log" || true
done

echo "--- exit codes: badged=$BADGED_RC solo=$SOLO_RC left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"

FAIL=0
check() {  # check <description> <expected: yes|no> <pattern> <file>
  if grep -q "$3" "$4"; then FOUND=yes; else FOUND=no; fi
  if [ "$FOUND" = "$2" ]; then
    echo "  OK   $1"
  else
    echo "  FAIL $1 (expected $2, got $FOUND)"
    FAIL=1
  fi
}

echo "--- WiFi up: the link must stand aside, and say so ---"
check "the left half suspended the link" yes "paired reading is suspended" sim-wifi-left.log
# The order matters as much as the fact: a link that came up and was then torn down would have
# disconnected WiFi on its way out, which is the failure this guard exists to prevent.
if grep -n "paired reading is suspended\|PageFlip link up as left" sim-wifi-left.log | head -1 |
  grep -q "paired reading is suspended"; then
  echo "  OK   it suspended BEFORE any link came up"
else
  echo "  FAIL the link came up first — WiFi would have been torn down under the user"
  FAIL=1
fi

echo "--- WiFi down: the link must come back ---"
check "the left half resumed"          yes "WiFi released the radio" sim-wifi-left.log
check "and came up in the left role"   yes "PageFlip link up as left" sim-wifi-left.log
check "and the pair formed"            yes "peer present" sim-wifi-right.log

echo "--- pages: suspended reads solo, resumed reads as a spread ---"
check_shot() {  # check_shot <label> <shot> <reference file stem> <reference index>
  local label="$1" shot="$2" ref="$3" idx="$4" sum ref_sum
  sum=$(md5sum "fs_/screenshots/pf-wifi-$label-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  ref_sum=$(md5sum "fs_/screenshots/$ref-$idx.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sum" ] || [ -z "$ref_sum" ]; then
    echo "  FAIL $label-$shot: screenshot missing (shot=${sum:-none} reference=${ref_sum:-none})"
    FAIL=1
  elif [ "$sum" = "$ref_sum" ]; then
    echo "  OK   $label-$shot is page $idx"
  else
    echo "  FAIL $label-$shot is not page $idx"
    FAIL=1
  fi
}
# Suspended: against the paired-alone reference, badge and all. Page 1, not page 2 — a suspended
# half that still advanced by two would be a reader silently skipping every other page.
check_shot left 00 pf-badged 00
check_shot left 01 pf-badged 01
# Resumed: against the paired-reading-off reference, because the badge is gone with the suspension.
# Page 0, because this half was a page ahead and section 4.2 calls that Swapped: the two exchange
# positions rather than one chasing the other.
check_shot left 02 pf-solo 00
check_shot right 00 pf-solo 01
# And one press moves the pair by two, which is the whole feature working again after the radio
# came back. The right half pressed nothing at all.
check_shot left 03 pf-solo 02
check_shot right 01 pf-solo 03

[ "$BADGED_RC" -eq 0 ] && [ "$SOLO_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
