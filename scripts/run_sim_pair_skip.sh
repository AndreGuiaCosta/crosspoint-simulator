#!/bin/bash
# A long-press chapter skip on a paired device (docs/pageflip.md section 4.3).
#
# Every other pair harness moves the spread by presses that both halves can predict: one press, two
# pages, arithmetic. A chapter skip cannot work that way. EpubReaderActivity::skipPages() drops the
# section and increments the spine, so the landing page does not exist yet and no count of steps
# describes it. The device therefore sets announceWhenSettled, and the announce waits for both the
# new section AND a link that is up (EpubReaderActivity.cpp:1852) before telling the peer where it
# ended up. The peer heals to that position and takes one step for its role.
#
# Three ways that can be wrong, and this harness separates them:
#   - the announce never fires (right half never moves at all),
#   - it fires too early, into a link that is still down for the build (same symptom, different
#     cause -- so the log assertions below distinguish them),
#   - it fires but the peer replays it as steps rather than seeking (right half lands somewhere
#     plausible and wrong, which no "did it move" check would catch).
#
# The book matters here. `test_tables.epub` -- the only book in fs_/books/ -- is a cover, a title
# page and two chapters of a few hundred bytes. A skip in it runs off the end of the book, so the
# harness would be testing end-of-book while claiming to test a chapter skip. This one generates a
# six-chapter fixture instead and points recent.json at it, which is also what makes `tap confirm`
# on Home deterministic: HomeActivity opens recentBooks[0] (HomeActivity.cpp:176).
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_skip.sh [timeout=150]
set -e

TIMEOUT="${1:-150}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/pageflip_settings.sh"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

BOOK=fs_/books/test_chapters.epub
python "$SCRIPT_DIR/make_test_chapters_epub.py" "$BOOK" >/dev/null

for side in left right solo; do
  rm -rf "fs_pf_$side"
  mkdir -p "fs_pf_$side/screenshots" "fs_pf_$side/.crosspoint"
  cp -r fs_/books "fs_pf_$side/books"
  # Deliberately NOT fs_/.crosspoint/recent.json: this harness needs the six-chapter book to be the
  # one `tap confirm` opens, and only its own recent.json can promise that.
  printf '{"books":[{"path":"/books/test_chapters.epub","title":"Chapters? In CrossPoint?","author":"","coverBmpPath":""}]}\n' \
    >"fs_pf_$side/.crosspoint/recent.json"
done

# longPressButtonBehavior=1 is CHAPTER_SKIP (CrossPointSettings.h:163). Without it a long press is
# just a page turn and this harness would pass while testing nothing.
write_pair_settings left  '"longPressButtonBehavior":1'
write_pair_settings right '"longPressButtonBehavior":1'
# The reference walk gets the LEFT half's settings, not an empty file, so no setting-dependent
# difference can creep into a byte-exact comparison. Only peer presence differs.
write_pair_settings solo  '"longPressButtonBehavior":1'

rm -f fs_/screenshots/pf-sk-*.bmp fs_/screenshots/pf-sk-*.png fs_/screenshots/pf-sk-solo-ctl.bmp

set +e
CROSSPOINT_SIM_SD=./fs_pf_solo CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_skip_solo_ref.script" 2>sim-sk-solo.log >/dev/null
SOLO_RC=$?

CROSSPOINT_SIM_SD=./fs_pf_left CROSSPOINT_PAGEFLIP_SLOT=0 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_skip_left.script" 2>sim-sk-left.log >/dev/null &
LEFT_PID=$!
CROSSPOINT_SIM_SD=./fs_pf_right CROSSPOINT_PAGEFLIP_SLOT=1 \
  timeout "$TIMEOUT" "$BIN" --script "$SCRIPT_DIR/sim_pageflip_skip_right.script" 2>sim-sk-right.log >/dev/null &
RIGHT_PID=$!

wait $LEFT_PID
LEFT_RC=$?
wait $RIGHT_PID
RIGHT_RC=$?
set -e

for side in left right; do
  echo "--- $side trace ---"
  grep -E '^\[SCRIPT\]|PageFlip|skip' "sim-sk-$side.log" || true
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

# Asserted first because it fails at the point the mistake was made: an instance that never paired
# reads solo, correctly and silently, and would still match the reference on its FIRST screenshot.
echo "--- the pair must exist, in the roles it asked for ---"
check "left came up as left"    yes "PageFlip link up as left"  sim-sk-left.log
check "right came up as right"  yes "PageFlip link up as right" sim-sk-right.log
check "left saw its peer"       yes "peer present"              sim-sk-left.log
check "right saw its peer"      yes "peer present"              sim-sk-right.log

echo "--- the skip must be announced and healed to, not replayed as steps ---"
# The sender's own landing: chapter 2 is spine 1, and a skip always lands on its first page.
check "right healed to the skip's landing" yes "PageFlip heal -> spine 1 page 0" sim-sk-right.log
# A heal is not a divergent join. Both halves started at the same fresh position, so a resume prompt
# here would mean the skip was classified as a conflict -- which converges to the same place and
# would look green everywhere else.
check "right was not prompted to resume"   no  "positions unrelated"             sim-sk-right.log
# Steps are the other wrong answer: AdvanceTwo would move the right half by a fixed count from where
# it was, which for a skip is a page that happens to exist and is not the one the pair is on.
check "right did not replay it as steps"   no  "PageFlip peer turn"              sim-sk-right.log
# The presser announces; it never heals to itself.
check "left did not heal"                  no  "PageFlip heal"                   sim-sk-left.log
check "the pair was not lost over it"      no  "peer went quiet"                 sim-sk-left.log

echo "--- and each half must sit where the spread says it should ---"
# Chapter 2 is spine 1, and a skip always lands on its first page. The right half seeks there and
# takes one further step for its role, so the pair reads pages 0 and 1 of the new chapter.
check "left ended on the new chapter, page 0"  yes "Progress saved: spine=1 offset=0 page=0" sim-sk-left.log
check "right ended on the new chapter, page 1" yes "Progress saved: spine=1 .* page=1"       sim-sk-right.log
# Neither half may still be in the chapter it skipped out of when it last saved.
check "left did not stay behind"               no  "Progress saved: spine=0 .* page=[1-9]"   sim-sk-left.log

echo "--- and both halves must end on the spread, in the chapter that was skipped to ---"
# Page content only, with the status bar masked out: a paired half and a solo reader at the same
# position draw the same text and a different readout beside it (see bmp_content_hash.py). Hashing
# the whole framebuffer would fail this comparison for a reason that has nothing to do with the
# spread.
content_hash() { python3 "$SCRIPT_DIR/bmp_content_hash.py" "$1" 2>/dev/null; }

check_against_solo() {  # check_against_solo <half> <shot> <reference shot>
  local label="$1" shot="$2" solo="$3" sum solo_sum
  sum=$(content_hash "fs_/screenshots/pf-sk-$label-$shot.bmp")
  solo_sum=$(content_hash "fs_/screenshots/pf-sk-solo-$solo.bmp")
  if [ -z "$sum" ] || [ -z "$solo_sum" ]; then
    echo "  FAIL $label-$shot: screenshot missing (shot=${sum:-none} reference=${solo_sum:-none})"
    FAIL=1
  elif [ "$sum" = "$solo_sum" ]; then
    echo "  OK   $label-$shot is the reference's $solo"
    return 0
  else
    echo "  FAIL $label-$shot is not the reference's $solo"
    FAIL=1
  fi
  return 1
}
# Left on the chapter's first page, right on its second: the spread, one page apart, in the new
# chapter. Comparing the halves to each other could not say this -- it can only say "different",
# which is equally true of a pair one page apart and a pair that has desynced by nine.
check_against_solo left  01 00
check_against_solo right 01 01

# The skip has to have moved something. If the fixture ever regresses to a book whose chapters are a
# page long, the two shots above could both be right and the whole run still mean nothing.
BEFORE=$(content_hash fs_/screenshots/pf-sk-left-00.bmp)
AFTER=$(content_hash fs_/screenshots/pf-sk-left-01.bmp)
if [ -n "$BEFORE" ] && [ "$BEFORE" != "$AFTER" ]; then
  echo "  OK   the left half actually left the page it was on"
else
  echo "  FAIL the left half did not leave the page it was on across the skip"
  FAIL=1
fi

# Reported, never asserted. Whether a paired half and a solo reader draw identical chrome at the
# same position is a fact about the reader, not about the skip, and this harness has no business
# failing over it -- but it is the fact that decides whether any harness may compare whole frames
# against a solo walk, so it is measured every run rather than remembered.
echo "--- observation: does peer presence change the pixels? (not asserted) ---"
LEFT00=$(md5sum fs_/screenshots/pf-sk-left-00.bmp 2>/dev/null | cut -d' ' -f1)
SOLOCTL=$(md5sum fs_/screenshots/pf-sk-solo-ctl.bmp 2>/dev/null | cut -d' ' -f1)
if [ -z "$LEFT00" ] || [ -z "$SOLOCTL" ]; then
  echo "  ??   control shot missing; cannot say"
elif [ "$LEFT00" = "$SOLOCTL" ]; then
  echo "  ..   no: paired and solo render identically at spine 0 page 0, whole frame"
else
  echo "  ..   YES: paired and solo differ at the same position, so a solo walk is not a"
  echo "       byte-exact reference for a paired half -- content region only, as used above"
fi

[ "$SOLO_RC" -eq 0 ] && [ "$LEFT_RC" -eq 0 ] && [ "$RIGHT_RC" -eq 0 ] && [ "$FAIL" -eq 0 ]
