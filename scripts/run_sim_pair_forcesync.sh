#!/bin/bash
# The repair half of the PageFlip pair tests (docs/pageflip.md section 5.1, phase 4).
#
# run_sim_pair_mismatch.sh proves two devices that disagree on layout notice and fall back to solo.
# This proves the pair can be put back together: both halves are prompted, one user confirms, and
# that device's render settings are preflighted, committed and applied on the other.
#
# The failure it guards against is a force-sync that reports success without converging -- the peer
# resolving the font is not the same as the peer laying the page out identically, so the check that
# matters is the one at the end: the two devices must agree on a layout afterwards.
#
# Same divergence as the mismatch harness: a different screenMargin on the right half.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_forcesync.sh [timeout=120]
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

# The divergence the force-sync has to repair. 5 is the default (SCREEN_MARGIN_MIN), so the left
# half offering its own settings must bring this back to 5.
write_pair_settings left
write_pair_settings right '"screenMargin":20'

# Stale shots would let a crashed run pass the convergence check below.
rm -f fs_/screenshots/pf-fs-*.bmp fs_/screenshots/pf-fs-*.png
rm -f fs_/screenshots/pf-solo-*.bmp fs_/screenshots/pf-solo-*.png

# The reference walk, on the settings the SOURCE half is pushing (the defaults, untouched above).
# What "converged" means after the sync is that the peer now paginates exactly like this, which a
# left-versus-right comparison can no longer express: the two halves are a page apart by design
# once the join negotiation of section 4.2 has run.
set +e
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-fs-solo.log >/dev/null
SOLO_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_forcesync_left.script" 2>sim-fs-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_forcesync_right.script" 2>sim-fs-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-fs-$side.log" || true
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

echo "--- force-sync checks ---"
check "both halves saw the mismatch first"  yes "incompatible layout" sim-fs-right.log
# Verdict 0 is PageFlipSyncResult::Ok. Any other value means the offer was refused, which is a
# different (and also valid) outcome -- but not the one this harness is for.
check "the peer preflighted the offer"      yes "settings preflight: verdict 0" sim-fs-right.log
check "the peer applied the commit"         yes "applied the pair's settings" sim-fs-right.log
# The source writes nothing: it already has these settings, which is the whole direction of the push.
check "the source rebuilt nothing"          no  "applied the pair's settings" sim-fs-left.log
check "no refusal was reported"             no  "force-sync refused" sim-fs-left.log

echo "--- the pair must actually converge ---"
# The point of the exercise. Both halves re-greet after the apply changes the right half's hash, and
# agreement is what the presence line reports.
check "left counts the peer as present"     yes "peer present" sim-fs-left.log
check "right counts the peer as present"    yes "peer present" sim-fs-right.log

echo "--- the setting itself was written ---"
if grep -q '"screenMargin": *5' fs_pf_right/.crosspoint/settings.json; then
  echo "  OK   right half's margin now matches the source"
else
  echo "  FAIL right half's settings.json still holds its own margin"
  echo "       $(grep -o '"screenMargin"[^,}]*' fs_pf_right/.crosspoint/settings.json || echo 'no screenMargin key')"
  FAIL=1
fi

echo "--- and the repaired pair must lay out like the source, one page apart ---"
# Each half against the reference, not against each other. That is what distinguishes a repair that
# worked from one that merely left the two halves looking different for a new reason: the left must
# be on the source's page 0 and the right on its page 1, both under the source's pagination.
check_against_solo() {  # check_against_solo <half> <shot> <reference page>
  local label="$1" shot="$2" solo="$3" sum solo_sum
  sum=$(md5sum "fs_/screenshots/pf-fs-$label-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  solo_sum=$(md5sum "fs_/screenshots/pf-solo-$solo.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sum" ] || [ -z "$solo_sum" ]; then
    echo "  FAIL $label-$shot: screenshot missing (shot=${sum:-none} reference=${solo_sum:-none})"
    FAIL=1
  elif [ "$sum" = "$solo_sum" ]; then
    echo "  OK   $label-$shot is the source's page $solo"
  else
    echo "  FAIL $label-$shot is not the source's page $solo"
    FAIL=1
  fi
}
check_against_solo left 01 00
check_against_solo right 01 01

[ "$SOLO_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
