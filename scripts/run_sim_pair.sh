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
# would start from different pages, which is a different test (the join negotiation, section 4).
for side in left right; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots"
  cp -r fs_/books "fs_pf_$side/books"
  [ -f fs_/.crosspoint/recent.json ] && mkdir -p "fs_pf_$side/.crosspoint" &&
    cp fs_/.crosspoint/recent.json "fs_pf_$side/.crosspoint/recent.json"
done

# Screenshots land in fs_/screenshots (see the note above), which nothing else clears. Without this
# a run that died before taking any would be compared against the previous run's files and pass --
# which is exactly what happened once, hiding a segfault behind three "halves match" lines.
rm -f fs_/screenshots/pf-left-*.bmp fs_/screenshots/pf-right-*.bmp \
      fs_/screenshots/pf-left-*.png fs_/screenshots/pf-right-*.png

set +e
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

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip' "sim-pf-$side.log" || true
done

echo "--- exit codes: left=$LEFT_RC right=$RIGHT_RC (0=quit, 3=expect timeout, 124=killed) ---"

# The halves currently track each other exactly: the one-page offset is established by the join
# negotiation (docs/pageflip.md section 4.2), which is phase 5 and not implemented, so a matching
# pair of screenshots is the correct result today. This check is a canary -- when the join lands it
# MUST start failing, and should then be replaced by "differs by exactly one page".
echo "--- spread check (expect identical until the join negotiation lands) ---"
MISMATCH=0
for shot in 00 01 02; do
  LEFT_SUM=$(md5sum "fs_/screenshots/pf-left-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  RIGHT_SUM=$(md5sum "fs_/screenshots/pf-right-$shot.bmp" 2>/dev/null | cut -d' ' -f1)
  if [ -z "$LEFT_SUM" ] || [ -z "$RIGHT_SUM" ]; then
    echo "  $shot: MISSING (left=${LEFT_SUM:-none} right=${RIGHT_SUM:-none})"
    MISMATCH=1
  elif [ "$LEFT_SUM" = "$RIGHT_SUM" ]; then
    echo "  $shot: halves match"
  else
    echo "  $shot: halves DIFFER — expected while phase 5 is unimplemented?"
    MISMATCH=1
  fi
done

[ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$MISMATCH" -eq 0 ]
