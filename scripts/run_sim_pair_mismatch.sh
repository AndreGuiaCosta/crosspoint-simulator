#!/bin/bash
# The negative half of the PageFlip pair tests (docs/pageflip.md section 5, phase 3).
#
# run_sim_pair.sh proves two devices that agree on layout read as one spread. This proves the other
# case: two devices that do NOT agree must notice, tell both users, and fall back to reading solo.
# The failure it guards against is the quiet one -- an incompatible peer that still counts as
# present makes every press advance this device by two while the peer ignores all of them.
#
# The divergence is a different screenMargin on the right half, which changes the viewport and so
# changes the layout hash. Any ReaderRenderSpec field would do; the margin is just the cheapest to
# set from outside the UI.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_mismatch.sh [timeout=90]
set -e

TIMEOUT="${1:-90}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

for side in left right; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots" "fs_pf_$side/.crosspoint"
  cp -r fs_/books "fs_pf_$side/books"
  [ -f fs_/.crosspoint/recent.json ] && cp fs_/.crosspoint/recent.json "fs_pf_$side/.crosspoint/recent.json"
done

# The whole point of the run: the right half lays out at a different margin. 5 is the default
# (SCREEN_MARGIN_MIN), so 20 is comfortably distinct and still inside SCREEN_MARGIN_MAX.
write_pair_settings left
write_pair_settings right '"screenMargin":20'

# Stale shots would let a crashed run pass the "never moved" check below.
rm -f fs_/screenshots/pf-mm-right-*.bmp fs_/screenshots/pf-mm-right-*.png

set +e
CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_left.script" 2>sim-mm-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_mismatch_right.script" 2>sim-mm-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-mm-$side.log" || true
done

echo "--- exit codes: left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout, 124=killed) ---"

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

echo "--- mismatch checks ---"
# Both users have to be told. The right half detects on the incoming greeting; the left half only
# learns because the right half answers that greeting with its own hash.
check "right reports the incompatible layout" yes "incompatible layout" sim-mm-right.log
check "left is told too, via the answer"      yes "incompatible layout" sim-mm-left.log
# The substance of the phase: an incompatible peer must not license the two-step advance.
check "right never counts the peer as present" no "peer present" sim-mm-right.log
check "left never counts the peer as present"  no "peer present" sim-mm-left.log
check "right never applies a peer turn"        no "PageFlip peer turn" sim-mm-right.log

echo "--- right half must not have moved ---"
FIRST=$(md5sum fs_/screenshots/pf-mm-right-00.bmp 2>/dev/null | cut -d' ' -f1)
LAST=$(md5sum fs_/screenshots/pf-mm-right-01.bmp 2>/dev/null | cut -d' ' -f1)
if [ -z "$FIRST" ] || [ -z "$LAST" ]; then
  echo "  FAIL screenshots missing (00=${FIRST:-none} 01=${LAST:-none})"
  FAIL=1
elif [ "$FIRST" = "$LAST" ]; then
  echo "  OK   page unchanged across both of the left half's presses"
else
  echo "  FAIL the right half turned a page it should have rejected"
  FAIL=1
fi

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
