#!/bin/bash
# The divergent join (docs/pageflip.md section 4.3, phase 5).
#
# run_sim_pair.sh covers the join that needs no decision: two devices on the same page, where the
# right one simply steps forward and the spread exists. This covers the one that does. The two
# devices were read separately, so neither position is more right than the other -- both are
# prompted, the user confirms on one, and THAT device's position becomes the pair's.
#
# What it guards against is the tempting shortcut of picking a side automatically. A device that
# guessed would throw away the position the other user was about to choose, and it would do it
# silently. So the checks below are as much about what does NOT happen: the confirming device must
# not move, and nothing may move before the confirm.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_resume.sh [timeout=120]
set -e

TIMEOUT="${1:-120}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

rm -f fs_/screenshots/pf-rs-*.bmp fs_/screenshots/pf-rs-*.png
rm -f fs_/screenshots/pf-solo-*.bmp fs_/screenshots/pf-solo-*.png

set +e
# The reference walk, and the divergence itself. Both are solo runs, so neither pairs with anything.
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-rs-solo.log >/dev/null
SOLO_RC=$?

# Leaves the right half part-read while the left stays at the top of the book: two positions that
# are neither the same nor adjacent, which is the definition of divergent.
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_seed_progress.script" 2>sim-rs-seed.log >/dev/null
SEED_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_resume_left.script" 2>sim-rs-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_resume_right.script" 2>sim-rs-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-rs-$side.log" || true
done

echo "--- exit codes: solo=$SOLO_RC seed=$SEED_RC left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout) ---"

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

echo "--- both halves must be asked, and only the peer may act ---"
check "left saw the divergence"          yes "positions unrelated" sim-rs-left.log
check "right saw it too"                 yes "positions unrelated" sim-rs-right.log
check "right followed the left's choice" yes "reading from the peer's choice" sim-rs-right.log
# The chooser does not move: its position IS the choice. A device that also seeked would be seeking
# to itself at best, and to a position nobody picked at worst.
check "left never followed anything"     no  "reading from the peer's choice" sim-rs-left.log
# Nothing may be repaired here: the layouts agree, only the positions differed.
check "no layout mismatch was reported"  no  "incompatible layout" sim-rs-left.log

echo "--- and the pair must end up one page apart, at the chosen position ---"
check_against_solo() {  # check_against_solo <half> <shot> <reference page>
  local label="$1" shot="$2" solo="$3" sum solo_sum
  sum=$(md5sum "fs_/screenshots/pf-rs-$label-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  solo_sum=$(md5sum "fs_/screenshots/pf-solo-$solo.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sum" ] || [ -z "$solo_sum" ]; then
    echo "  FAIL $label-$shot: screenshot missing (shot=${sum:-none} reference=${solo_sum:-none})"
    FAIL=1
  elif [ "$sum" = "$solo_sum" ]; then
    echo "  OK   $label-$shot is page $solo"
  else
    echo "  FAIL $label-$shot is not page $solo"
    FAIL=1
  fi
}
# The left half opened at the top of the book and confirmed there, so the pair reads from page 0.
check_against_solo left 01 00
check_against_solo right 01 01

[ "$SOLO_RC" -eq 0 ] && [ "$SEED_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
