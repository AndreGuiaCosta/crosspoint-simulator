#!/bin/bash
# The radio steps aside for a cold chapter build (docs/pageflip.md section 7).
#
# WHAT THIS PROVES AND WHAT IT DOES NOT. The host cannot run out of memory, and this harness does
# not make it: CROSSPOINT_SIM_FREE_HEAP only makes the firmware's heap query REPORT a low figure for
# a window. So this shows that the guard fires at a cold crossing, that the link goes down, that the
# pairing survives it, and that the link comes back. It cannot show that the build then fits. Only
# two X4s can close that, because the failure it guards against was an abort() from a throwing STL
# allocation inside the section builder, which no host run reproduces.
#
# The case is the one that crashed a device on the bench: a peer's page turn crossed a chapter
# boundary, so BOTH halves began building the same cold section at the same moment, each holding the
# 60 KB the radio costs. One survived at 4,668 B free; the other did not.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_heapbuild.sh [timeout=120]
set -e

TIMEOUT="${1:-120}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

# Every script here places its presses on absolute uptime, so a slow start moves the whole run out
# from under them. That is not hypothetical: SDL window creation has taken 15 s on a loaded machine,
# which put the pair's formation at 26 s -- after the window this harness was aiming at. A failure
# from that reads exactly like a logic failure, so name it.
report_slow_start() {  # report_slow_start <log> [limit_ms=4000]
  local log="$1" limit="${2:-4000}" stamp
  stamp=$(grep -m1 "Display initialized" "$log" 2>/dev/null | sed -n 's/^\[\([0-9]*\)\].*/\1/p')
  # Written as a full if: under set -e a false short-circuit ends the whole harness.
  if [ -z "$stamp" ]; then return 0; fi
  if [ "$stamp" -gt "$limit" ]; then
    echo "  NOTE $log started slowly (display ready at ${stamp} ms, limit ${limit}): the timings"
    echo "       below are measured from boot, so treat a failure here as an environment result."
  fi
}

# Under the firmware's PAGEFLIP_COLD_BUILD_MIN_FREE_HEAP (64 KB), so a cold crossing releases the
# link -- and above the two floors that would change what else the reader does: the CSS parser gives
# up under 48 KB and the background build gate pauses under 32 KB. The point is to exercise one
# branch, not to starve the run.
PRESSURE_BYTES=57344
# One window, opened before either half crosses and held across both. The two halves still do not
# cross at the same moment -- a turn that crosses a chapter boundary cannot be announced until the
# presser has laid the new chapter out, so the peer learns of the press only as the presser finishes
# -- but the gap between them is now milliseconds, not seconds, so a single window covers both.
#
# It used to be two narrow staggered windows, and that stagger was load-bearing only because the
# resume waited on the reported heap: the presser stayed down for the whole window and announced its
# turn on the way out, putting the peer's crossing 3 s later. The resume now waits on the build
# instead, so the presser is back ~30 ms after it left and the peer crosses almost immediately.
# Sizing a window to a delay that no longer exists is how this harness fails for the right reason and
# reports the wrong one.
PRESSURE_AFTER_MS=13000
# Still shorter than PEER_PRESENCE_TIMEOUT_MS (8 s), so the stated invariant -- an ordinary chapter
# build costs the pair no presence -- is a property of the run and not of the window's length. It is
# no longer what ends the suspension, though: the link comes back when the build is over, and the
# reported figure is above PAGEFLIP_COLD_BUILD_RESUME_MIN_FREE_HEAP (24 KB) the whole time, so the
# window can be widened for timing headroom without buying the pass it is supposed to be testing.
PRESSURE_FOR_MS=6000

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

write_pair_settings left
write_pair_settings right

rm -f fs_/screenshots/pf-hb-*.bmp fs_/screenshots/pf-hb-*.png

set +e
for side in left right; do
  slot=0
  if [ "$side" = "right" ]; then
    slot=1
  fi
  CROSSPOINT_SIM_SD="./fs_pf_$side" CROSSPOINT_PAGEFLIP_SLOT="$slot" \
    CROSSPOINT_SIM_FREE_HEAP="$PRESSURE_BYTES" \
    CROSSPOINT_SIM_FREE_HEAP_AFTER_MS="$PRESSURE_AFTER_MS" \
    CROSSPOINT_SIM_FREE_HEAP_FOR_MS="$PRESSURE_FOR_MS" \
    timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_heapbuild_$side.script" \
    2>"sim-hb-$side.log" >/dev/null &
  eval "${side}_PID=\$!"
done

wait $left_PID
LEFT_RC=$?
wait $right_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip|Low heap' "sim-hb-$side.log" || true
done

echo "--- exit codes: left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"
report_slow_start sim-hb-left.log
report_slow_start sim-hb-right.log

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
check_count() {  # check_count <description> <expected count> <pattern> <file>
  local n
  n=$(grep -c "$3" "$4")
  if [ "$n" = "$2" ]; then
    echo "  OK   $1"
  else
    echo "  FAIL $1 (expected $2, got $n)"
    FAIL=1
  fi
}

echo "--- the pair must form, then step aside for the build ---"
check "the left half paired"           yes "peer present" sim-hb-left.log
check "the right half paired"          yes "peer present" sim-hb-right.log
# Both halves, because both cross on the same press. A run where only the presser released would
# mean the peer-driven crossing -- the one that actually crashed a device -- is still unguarded.
check "the left half released the link"  yes "releasing the paired link to build the chapter" sim-hb-left.log
check "the right half released the link" yes "releasing the paired link to build the chapter" sim-hb-right.log

echo "--- and take it back afterwards ---"
check "the left half came back"        yes "bringing the paired link back" sim-hb-left.log
check "the right half came back"       yes "bringing the paired link back" sim-hb-right.log

echo "--- with the pairing intact ---"
# The session outlives the transport, and this is the check that says so. Tearing it down would
# reset turnSeq and the join, and two halves finishing their builds at different moments classify as
# Divergent -- a resume prompt in front of the user at every chapter boundary. One join line per log
# means the negotiation happened once, at start-up, and the suspension did not re-run it.
check_count "the left half joined once"  1 "PageFlip join:" sim-hb-left.log
check_count "the right half joined once" 1 "PageFlip join:" sim-hb-right.log
# A build shorter than four heartbeats must not cost presence at all.
check "the left half kept its peer"    no "peer went quiet" sim-hb-left.log
check "the right half kept its peer"   no "peer went quiet" sim-hb-right.log

echo "--- and no press lost on the way ---"
# Both presses came from the right half, and both must reach the left half: the first while its link
# was down for the build, the second after it came back. This is the check that caught the defect
# this harness was written for -- a crossing turn cannot be announced until the new chapter is laid
# out, which is exactly when the link is down, so announcing it there spent the latch on a send that
# never happened and the press was lost for good.
#
# Counted rather than named by spine, because where two turns land depends on the book's pagination
# and on the owed step a boundary crossing leaves behind -- neither of which this harness is about.
check_count "both presses reached the left half" 2 "PageFlip peer turn fwd" sim-hb-left.log

# The link must be down FOR the build, not merely around it. Every check above passed on a build
# where the resume fired 43 ms after the suspend -- before the chapter build had even begun -- so
# the radio was resident for the whole of it and the guard bought nothing. Only ordering catches
# that: the line that brings the link back has to come after the chapter is on screen, not between
# "Cache not found" and the render that follows it. Measured on two X4s, 2026-09-05.
check_build_order() {  # check_build_order <side> <file>
  local suspend build resume render
  # Anchored on the SUSPEND, not on the first "Cache not found" in the log -- the first one is the
  # book opening, long before the pair exists, and anchoring there let this check pass on the very
  # build it was written to fail.
  suspend=$(grep -n "releasing the paired link to build the chapter" "$2" | head -1 | cut -d: -f1)
  if [ -z "$suspend" ]; then
    echo "  FAIL the $1 half never released the link (nothing to order)"
    FAIL=1
    return
  fi
  build=$(awk -v s="$suspend" 'NR>s && /Cache not found, building/ {print NR; exit}' "$2")
  resume=$(awk -v s="$suspend" 'NR>s && /bringing the paired link back/ {print NR; exit}' "$2")
  render=$(awk -v s="$suspend" 'NR>s && /Rendered page/ {print NR; exit}' "$2")
  if [ -z "$build" ]; then
    echo "  FAIL the $1 half released the link but never built a chapter"
    FAIL=1
  elif [ -z "$resume" ] || [ -z "$render" ]; then
    echo "  FAIL the $1 half is missing a resume or a render after the build (resume=${resume:-none} render=${render:-none})"
    FAIL=1
  elif [ "$resume" -lt "$render" ]; then
    echo "  FAIL the $1 half took the link back mid-build (resume at line $resume, chapter on screen at $render)"
    FAIL=1
  else
    echo "  ok   the $1 half kept the link down for the whole build"
  fi
}

check_build_order left  sim-hb-left.log
check_build_order right sim-hb-right.log

# And the build must be OVER when the link returns, not merely resting. This is the stronger form of
# the check above and it is the one that matters: a build that has stopped at BUILD_WINDOW_AHEAD is
# still holding its BuildContext, and on an X4 that context is enough to put free heap under
# BACKGROUND_BUILD_MIN_FREE_HEAP -- the floor the build itself needs to advance. The radio coming
# back on top of that deadlocks the chapter permanently (measured: 4,896 B free, no further page
# processed in 55 s). "Rendered page" cannot see that, because it is equally true of both.
#
# "Build finalized" is the observable, emitted by Section::finalizeBuild(). Its absence between the
# suspend and the resume IS the bug.
check_build_finalized_before_resume() {  # <side> <file>
  local suspend finalized resume
  suspend=$(grep -n "releasing the paired link to build the chapter" "$2" | head -1 | cut -d: -f1)
  [ -z "$suspend" ] && return  # already reported by check_build_order
  resume=$(awk -v s="$suspend" 'NR>s && /bringing the paired link back/ {print NR; exit}' "$2")
  finalized=$(awk -v s="$suspend" 'NR>s && /Build finalized/ {print NR; exit}' "$2")
  if [ -z "$resume" ]; then
    echo "  FAIL the $1 half never took the link back"
    FAIL=1
  elif [ -z "$finalized" ] || [ "$finalized" -gt "$resume" ]; then
    echo "  FAIL the $1 half took the link back onto a live build (finalized=${finalized:-never}, resume=$resume)"
    FAIL=1
  else
    echo "  ok   the $1 half finished the build before taking the link back"
  fi
}

check_build_finalized_before_resume left  sim-hb-left.log
check_build_finalized_before_resume right sim-hb-right.log

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
