#!/bin/bash
# A pair must still form when the first greeting is lost (docs/pageflip.md section 4.2).
#
# Discovery rested on a single packet. A device sends its greeting when the layout fingerprint first
# exists and never again unless the layout moves, so one lost datagram meant the two halves never
# met -- not "met late", never, because the heartbeat that would have said hello again is gated on
# having already heard from a peer. On loopback nothing is lost, which is why every other harness
# passes without noticing; on a radio a lost packet is an ordinary Tuesday.
#
# Two devices switched on together produce the same failure with no loss at all: each greets while
# the other's transport is still coming up. That is what this reproduces, deterministically, by
# making both instances drop the first datagram they send.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_discovery.sh [timeout=120]
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

write_pair_settings left
write_pair_settings right

set +e
for side in left right; do
  slot=0
  [ "$side" = "right" ] && slot=1
  # One dropped send each, and the first one is the greeting.
  CROSSPOINT_SIM_SD="./fs_pf_$side" CROSSPOINT_PAGEFLIP_SLOT="$slot" \
    CROSSPOINT_PAGEFLIP_DROP_FIRST_SENDS=1 \
    timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_discovery.script" \
    2>"sim-dc-$side.log" >/dev/null &
  eval "${side}_PID=\$!"
done

wait $left_PID
LEFT_RC=$?
wait $right_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-dc-$side.log" || true
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

echo "--- the greeting must be repeated until somebody answers ---"
check "the left half came up as left"   yes "PageFlip link up as left" sim-dc-left.log
check "the right half came up as right" yes "PageFlip link up as right" sim-dc-right.log
check "the left half found its peer"    yes "peer present" sim-dc-left.log
check "the right half found its peer"   yes "peer present" sim-dc-right.log
# Forming is not the same as pairing: the join is what makes the two halves a spread rather than two
# devices that can hear each other.
check "and the pair joined"             yes "PageFlip join:" sim-dc-left.log

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
