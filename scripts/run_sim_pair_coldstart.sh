#!/bin/bash
# PageFlip cold-start skew test (docs/pageflip.md section 5, phase 3).
#
# The other two harnesses give both halves byte-identical work on freshly copied SD roots, so they
# render within a millisecond of each other and the compat hashes appear simultaneously. That
# symmetry hides a whole class of bug: the layout hash cannot be computed until a device's FIRST
# RENDER has fixed the viewport, so until then a device advertises the "not computed yet" sentinel.
# If the receive path compares that sentinel with a bare equality, two IDENTICALLY configured
# devices report incompatibility whenever one renders faster than the other.
#
# This run creates that skew deliberately: warm the right half's cache, wipe the left half's. The
# right renders in milliseconds, the left takes seconds building sections. That is not an exotic
# setup -- it is "the second time you open the book on one of the devices".
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_coldstart.sh [timeout=90]
set -e

TIMEOUT="${1:-90}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

run_pair() {  # run_pair <left-log> <right-log>
  set +e
  CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
    timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_left.script" 2>"$1" >/dev/null &
  local lpid=$!
  CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
    timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_right.script" 2>"$2" >/dev/null &
  local rpid=$!
  wait $lpid; LEFT_RC=$?
  wait $rpid; RIGHT_RC=$?
  set -e
}

for side in left right; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots" "fs_pf_$side/.crosspoint"
  cp -r fs_/books "fs_pf_$side/books"
  [ -f fs_/.crosspoint/recent.json ] && cp fs_/.crosspoint/recent.json "fs_pf_$side/.crosspoint/recent.json"
done

write_pair_settings left
write_pair_settings right

echo "--- warm-up run (builds both caches; result deliberately not asserted) ---"
rm -f fs_/screenshots/pf-left-*.bmp fs_/screenshots/pf-right-*.bmp
run_pair sim-cs-warm-left.log sim-cs-warm-right.log
echo "    warm-up exit codes: left=$LEFT_RC right=$RIGHT_RC"

# The skew: the right half keeps its cache and renders immediately, the left rebuilds from scratch.
rm -rf fs_pf_left/.crosspoint/epub_*

echo "--- skewed run (right warm, left cold) ---"
rm -f fs_/screenshots/pf-left-*.bmp fs_/screenshots/pf-right-*.bmp
run_pair sim-cs-left.log sim-cs-right.log

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-cs-$side.log" || true
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

echo "--- cold-start checks (the devices are identically configured: nothing may be reported) ---"
check "left never reports an incompatible layout"  no  "incompatible layout" sim-cs-left.log
check "right never reports an incompatible layout" no  "incompatible layout" sim-cs-right.log
# And the skew must not merely be silent -- the pair still has to form once both have rendered.
check "left still pairs"  yes "peer present" sim-cs-left.log
check "right still pairs" yes "peer present" sim-cs-right.log

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
