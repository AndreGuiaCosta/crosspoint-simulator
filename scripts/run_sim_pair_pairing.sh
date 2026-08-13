#!/bin/bash
# The pairing screen (docs/pageflip.md section 8.1).
#
# Until it existed the receive path filtered on bookId and compatHash -- "somebody reading the same
# book, laid out the same way", which is every X4 in the room. This drives two instances through the
# real settings UI to the real screen and makes one of them choose the other.
#
# What it can prove that the host tests cannot: that the beacons actually flow between two whole
# firmware instances, that the discovered device turns up as a row, and that Confirm writes a MAC
# into settings.json. What it deliberately also proves is the asymmetry -- the half that chose is
# paired, and the half that did not is still open to anyone.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_pairing.sh [timeout=120]
set -e

TIMEOUT="${1:-120}"
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

# Paired reading on, no paired device: the screen only appears once the feature is switched on, and
# starting from "any nearby device" is the state a user is actually in the first time.
write_pair_settings left
write_pair_settings right

rm -f fs_/screenshots/pf-pairing-*.bmp fs_/screenshots/pf-pairing-*.png

set +e
CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_pairing_left.script" 2>sim-pairing-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_pairing_right.script" 2>sim-pairing-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

shopt -s nullglob
for bmp in fs_/screenshots/pf-pairing-*.bmp; do
  png="${bmp%.bmp}.png"
  if [ ! -f "$png" ] || [ "$bmp" -nt "$png" ]; then
    python3 -c "from PIL import Image; Image.open('$bmp').save('$png')" 2>/dev/null && echo "converted: $png"
  fi
done
shopt -u nullglob

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PFPAIR' "sim-pairing-$side.log" || true
done

echo "--- exit codes: left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"

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

echo "--- each half must find the other, and know which half it is ---"
check "the left half found a right device"  yes "Found a right device" sim-pairing-left.log
check "the right half found a left device"  yes "Found a left device"  sim-pairing-right.log
# The MACs are fixed by slot (02:50:46:00:00:<slot>), which is what makes the assertion below exact
# rather than "something got written".
check "the left half paired with slot 1"    yes "Paired with 02:50:46:00:00:01" sim-pairing-left.log

echo "--- and the choice must reach the settings file ---"
if grep -q '"pageflipPeerMac":"02:50:46:00:00:01"' fs_pf_left/.crosspoint/settings.json; then
  echo "  OK   the left half's settings.json names the right device"
else
  echo "  FAIL the left half's settings.json does not name the right device"
  echo "       $(cat fs_pf_left/.crosspoint/settings.json)"
  FAIL=1
fi

# The half that did not choose is still open to anyone, and that is the state this harness exists to
# make visible: the pair works either way, so nothing else would ever say so.
if grep -q '"pageflipPeerMac":""' fs_pf_right/.crosspoint/settings.json ||
  ! grep -q 'pageflipPeerMac' fs_pf_right/.crosspoint/settings.json; then
  echo "  OK   the half that chose nothing is still paired with nobody"
else
  echo "  FAIL the right half was paired without anyone choosing"
  echo "       $(cat fs_pf_right/.crosspoint/settings.json)"
  FAIL=1
fi

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
