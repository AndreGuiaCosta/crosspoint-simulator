#!/bin/bash
# The peer going away (docs/pageflip.md section 4, phase 5).
#
# Presence is what licenses advancing by two, and until the heartbeat existed nothing ever withdrew
# it: a peer that powered off or walked out of range says nothing on its way out, so this device
# would go on turning two pages per press with no second half to show the other one. Solo reading
# that silently skips every other page is the worst failure the feature has, because it looks like
# the book is broken rather than the pair.
#
# So the check that matters is not the notice. It is the press AFTER the peer is gone landing one
# page on, measured against a reference walk rather than against the vanished peer.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_offline.sh [timeout=120]
set -e

TIMEOUT="${1:-120}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

for side in left right solo; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots" "fs_pf_$side/.crosspoint"
  cp -r fs_/books "fs_pf_$side/books"
  [ -f fs_/.crosspoint/recent.json ] && cp fs_/.crosspoint/recent.json "fs_pf_$side/.crosspoint/recent.json"
done

write_pair_settings left
write_pair_settings right
# The reference is configured as a pair too, and then left to run alone. Deliberate: once the peer
# leaves, the left half carries the status-bar badge for a pair that is configured but absent, and
# these screenshots are compared byte for byte. A reference with paired reading switched off would
# differ by the badge alone and fail for a reason that has nothing to do with page turns. Being
# alone it never advances by two, so it is still exactly one page per press.
write_pair_settings solo

rm -f fs_/screenshots/pf-off-*.bmp fs_/screenshots/pf-off-*.png
rm -f fs_/screenshots/pf-solo-*.bmp fs_/screenshots/pf-solo-*.png

set +e
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-off-solo.log >/dev/null
SOLO_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_offline_left.script" 2>sim-off-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_offline_right.script" 2>sim-off-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-off-$side.log" || true
done

echo "--- exit codes: solo=$SOLO_RC left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"

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

echo "--- the pair must form, then be given up ---"
check "the pair formed first"        yes "peer present" sim-off-left.log
check "the left half noticed it go"  yes "peer went quiet" sim-off-left.log
# Silence is not incompatibility, and reporting it as one would send the user hunting through
# settings for a difference that is not there.
check "and did not call it a mismatch" no "incompatible layout" sim-off-left.log

echo "--- and a press with no peer must turn ONE page ---"
check_against_solo() {  # check_against_solo <shot> <reference page>
  local shot="$1" solo="$2" sum solo_sum
  sum=$(md5sum "fs_/screenshots/pf-off-left-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  solo_sum=$(md5sum "fs_/screenshots/pf-solo-$solo.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sum" ] || [ -z "$solo_sum" ]; then
    echo "  FAIL left-$shot: screenshot missing (shot=${sum:-none} reference=${solo_sum:-none})"
    FAIL=1
  elif [ "$sum" = "$solo_sum" ]; then
    echo "  OK   left-$shot is page $solo"
  else
    echo "  FAIL left-$shot is not page $solo"
    FAIL=1
  fi
}
# Only the shot AFTER the peer left is compared. The one before it was taken while the pair was
# healthy, so it carries no badge, while every reference shot does -- and run_sim_pair.sh already
# covers "a paired left half sits on page 0".
#
# Page 1, not page 2. Page 2 would mean the device was still advancing for a peer that had gone.
check_against_solo 01 01

[ "$SOLO_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
