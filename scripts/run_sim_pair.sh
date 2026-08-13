#!/bin/bash
# Runs two simulator instances as a PageFlip pair (docs/pageflip.md section 11) and reports both
# script traces. Each instance gets its own SD root, because two readers sharing one .crosspoint
# cache directory would be writing the same files concurrently -- a test artefact, not the feature.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair.sh [timeout=90]
#
# Slots come from the environment: slot 0 is the left half, slot 1 the right (see
# PageFlipUdpTransport). SIM_BIN overrides the binary.
#
# Note: ScriptDriver resolves screenshot paths against ./fs_ directly rather than the configured SD
# root, so both instances write their shots to fs_/screenshots. Harmless here because the two
# scripts use different filenames, but do not expect them under fs_pf_left/right.
set -e

TIMEOUT="${1:-90}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

# Fresh SD roots each run: a stale progress.bin would reopen the book mid-way and the two halves
# would start from different pages, which is the divergent join of section 4.3 -- a different test.
# The solo root is the reference walk's; it must be built the same way, or a difference in
# pagination would show up as a spread that is off by a page.
for side in left right solo; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots"
  cp -r fs_/books "fs_pf_$side/books"
  [ -f fs_/.crosspoint/recent.json ] && mkdir -p "fs_pf_$side/.crosspoint" &&
    cp fs_/.crosspoint/recent.json "fs_pf_$side/.crosspoint/recent.json"
done

# Screenshots land in fs_/screenshots (see the note above), which nothing else clears. Without this
# a run that died before taking any would be compared against the previous run's files and pass --
# which is exactly what happened once, hiding a segfault behind three "halves match" lines.
rm -f fs_/screenshots/pf-left-*.bmp fs_/screenshots/pf-right-*.bmp fs_/screenshots/pf-solo-*.bmp \
      fs_/screenshots/pf-left-*.png fs_/screenshots/pf-right-*.png fs_/screenshots/pf-solo-*.png

# The reference walk first, and alone: one instance with no peer turns exactly one page per press,
# which is the ground truth the spread is measured against. Run before the pair rather than
# alongside it, or it would BE the peer.
set +e
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_solo_ref.script" 2>sim-pf-solo.log >/dev/null
SOLO_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_left.script" 2>sim-pf-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_right.script" 2>sim-pf-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

shopt -s nullglob
for bmp in fs_pf_*/screenshots/*.bmp; do
  png="${bmp%.bmp}.png"
  if [ ! -f "$png" ] || [ "$bmp" -nt "$png" ]; then
    python3 -c "from PIL import Image; Image.open('$bmp').save('$png')" 2>/dev/null && echo "converted: $png"
  fi
done
shopt -u nullglob

for side in solo left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-pf-$side.log" || true
done

echo "--- exit codes: solo=$SOLO_RC left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout, 124=killed) ---"

# The pair walks the same pages a solo reader does, split between the two devices: the left half
# shows 0, 2, 4 and the right half 1, 3, 5. Asserting each of the six against the reference is what
# makes this "the spread is exactly one page" rather than merely "the halves are not identical" --
# a pair that had desynced by nine pages would also be not-identical.
#
# Until the join negotiation of section 4.2 landed, the halves DID match, and this check asserted
# that instead. It was a canary, and it fired.
echo "--- spread check: left=solo 0,2,4 right=solo 1,3,5 ---"
MISMATCH=0
check_against_solo() {
  local label="$1" shot="$2" solo="$3"
  local sum solo_sum
  sum=$(md5sum "fs_/screenshots/pf-$label-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  solo_sum=$(md5sum "fs_/screenshots/pf-solo-$solo.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$sum" ] || [ -z "$solo_sum" ]; then
    echo "  $label-$shot: MISSING (shot=${sum:-none} reference=${solo_sum:-none})"
    MISMATCH=1
  elif [ "$sum" = "$solo_sum" ]; then
    echo "  $label-$shot: page $solo, as expected"
  else
    echo "  $label-$shot: NOT page $solo — the spread is off"
    MISMATCH=1
  fi
}

check_against_solo left 00 00
check_against_solo right 00 01
check_against_solo left 01 02
check_against_solo right 01 03
check_against_solo left 02 04
check_against_solo right 02 05

[ "$SOLO_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$MISMATCH" -eq 0 ]
