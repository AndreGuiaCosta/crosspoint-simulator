#!/bin/bash
# A busy device must not look like a dead one (docs/pageflip.md section 4).
#
# Presence is withdrawn after four missed heartbeats, and the heartbeat is sent from the pump only
# when it can read this device's position -- which needs the render lock. On this host that is never
# a wait worth naming, so every other pair harness is structurally blind to what follows: on real
# e-ink a render is seconds (4,241 ms measured on hardware for an image-bearing page against 0.88 s
# for a text page), and two of them back to back are longer than the peer's timeout. The peer then
# correctly observes silence and gives up a device that was only busy being read -- and the next
# press there advances one page instead of two, which desyncs the spread.
#
# So this harness buys the missing window with CROSSPOINT_SIM_RENDER_STALL_MS, which makes one
# simulator refresh hold the render lock for as long as a slow panel would. The left half stalls;
# the right half is the one under test, because the verdict about a busy device is made by its peer.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_renderstall.sh [timeout=120]
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

# Longer than PEER_PRESENCE_TIMEOUT_MS (four 2 s heartbeats). ONE stall of ten seconds rather than
# two of five: between two stalls the pump gets a chance to heartbeat, which is what made this
# intermittent on hardware -- three flaps on one device, two on the other, in one session.
STALL_MS=10000
# Held back until the pair has formed and settled, so start-up renders stay fast. The first refresh
# past this mark is the one that stalls, and it is the right half's page turn arriving here.
STALL_AFTER_MS=16000

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

rm -f fs_/screenshots/pf-rs-*.bmp fs_/screenshots/pf-rs-*.png

set +e
CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  CROSSPOINT_SIM_RENDER_STALL_MS="$STALL_MS" \
  CROSSPOINT_SIM_RENDER_STALL_AFTER_MS="$STALL_AFTER_MS" \
  CROSSPOINT_SIM_RENDER_STALL_COUNT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_renderstall_left.script" 2>sim-rs-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_renderstall_right.script" 2>sim-rs-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|Render stall|PageFlip' "sim-rs-$side.log" || true
done

echo "--- exit codes: left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"
report_slow_start sim-rs-left.log
report_slow_start sim-rs-right.log

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

# Without these three the headline check below is worthless: a pair that never formed, or a stall
# that never fired, also produces no notice. This is the same false-pass shape the screenshot
# staleness bug had, and it is cheap to close.
echo "--- the pair must form, and the stall must really happen ---"
check "the left half paired"          yes "peer present" sim-rs-left.log
check "the right half paired"         yes "peer present" sim-rs-right.log
check "the left half's render stalled" yes "Render stall: holding" sim-rs-left.log
check "and the stall was released"     yes "Render stall: released" sim-rs-left.log

echo "--- and a busy peer must not be given up ---"
# The headline. Pre-fix the heartbeat is skipped for the whole render rather than deferred, so the
# right half watches ten seconds of silence from a device that is running perfectly well.
check "the right half kept the left"  no "peer went quiet" sim-rs-right.log
# The left half is checked too, and for a different reason: it must go on RECEIVING while it renders.
# Its pump runs on the main task, so a stall there is no excuse for losing the peer either.
check "the left half kept the right"  no "peer went quiet" sim-rs-left.log

echo "--- and the spread must survive it ---"
# The notice is not the bug; the desync is, and this is the check that sees it. A local turn is
# announced only while a peer is present (pageTurn), so a right half that has written the left half
# off turns ONE page and tells nobody -- the left half never hears the second press, and the two
# devices stay a page apart for the rest of the session with no error reported anywhere.
#
# Both presses came from the right half, so a spread that held moves the pair twice: spine 0 to 1,
# then 1 to 2. The second line is the one that only exists if the flap did not happen. Pages are not
# named because the turns cross section boundaries here (test_tables.epub is four short sections),
# which leaves the section unloaded and the page reported as the -1 sentinel.
check "the left half heard the first press"  yes "PageFlip peer turn fwd -> spine 1" sim-rs-left.log
check "and the one inside the flap"          yes "PageFlip peer turn fwd -> spine 2" sim-rs-left.log

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
