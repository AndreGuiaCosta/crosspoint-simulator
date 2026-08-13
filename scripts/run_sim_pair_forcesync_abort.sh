#!/bin/bash
# The negative twin of run_sim_pair_forcesync.sh (docs/pageflip.md section 5.1, phase 4).
#
# There: the offer converges, so it is committed and applied. Here: it cannot converge, so the
# preflight refuses it and NOTHING is written on either device -- which is the promise the whole
# three-step exchange exists to keep.
#
# The divergence is deliberately in something force-sync does not push: a status-bar setting. It
# moves the viewport (UITheme::getStatusBarHeight feeds the bottom margin), and the viewport feeds
# the layout hash, but pushing it is out of scope -- the pair shares a layout, not a device
# configuration. So the honest answer is "this offer would not converge", and the user is told to
# match the screens themselves.
#
# The failure it guards against is the expensive lie: an Ok answer, a committed write, a full
# chapter re-layout, and the same mismatch still on screen at the end of it.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_forcesync_abort.sh [timeout=120]
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

# 0 is BOOK_PROGRESS; the default is 2 (HIDE_PROGRESS). A visible progress bar makes this half
# reserve more of the screen, so its viewport differs from the left's however the offer is applied.
write_pair_settings left
write_pair_settings right '"statusBarProgressBar":0'
cp fs_pf_right/.crosspoint/settings.json "$PWD/fs_pf_right/.crosspoint/settings.before.json"

rm -f fs_/screenshots/pf-fsa-*.bmp fs_/screenshots/pf-fsa-*.png

set +e
CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_forcesync_left.script" 2>sim-fsa-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_forcesync_abort_right.script" 2>sim-fsa-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-fsa-$side.log" || true
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

echo "--- abort checks ---"
# Verdict 3 is PageFlipSyncResult::ScreenDiffers: the peer would still lay the page out differently.
check "the peer refused the offer"          yes "settings preflight: verdict 3" sim-fsa-right.log
check "the source was told, with a reason"  yes "force-sync refused" sim-fsa-left.log
# The substance of the phase: a refusal writes nothing, anywhere.
check "the peer wrote nothing"              no  "applied the pair's settings" sim-fsa-right.log
check "the source wrote nothing"            no  "applied the pair's settings" sim-fsa-left.log
check "no layout was rebuilt for it"        no  "rebuilding layout" sim-fsa-right.log
# And the pair stays honestly apart rather than pretending.
check "the peer still counts as absent"     no  "peer present" sim-fsa-right.log

echo "--- the settings file must be untouched ---"
if diff -q fs_pf_right/.crosspoint/settings.before.json fs_pf_right/.crosspoint/settings.json >/dev/null 2>&1; then
  echo "  OK   right half's settings.json is byte-identical"
else
  echo "  FAIL right half's settings.json was written despite the refusal"
  diff fs_pf_right/.crosspoint/settings.before.json fs_pf_right/.crosspoint/settings.json || true
  FAIL=1
fi

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
