#!/bin/bash
# Every PageFlip harness plus the solo page-turn regression, in one pass (~6 minutes).
#
# The whole set is the check that matters, not any one of them: each harness covers a phase of
# docs/pageflip.md, and most of the bugs this feature produced were found by a harness OTHER than
# the one being written at the time. The solo regression at the end is there because every one of
# these gates page turns on peer presence, and the failure mode of getting that wrong is a device
# with no pair turning two pages per press.
#
# Invoke from the firmware repo root:
#   bash <sim>/scripts/run_sim_pair_all.sh [per-harness timeout=150]
#
# Logs go to $HOME rather than /tmp: WSL's /tmp is tmpfs and the distro idle-restarts between
# commands, which has eaten evidence before.
TIMEOUT="${1:-150}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${PAIR_ALL_LOG:-$HOME/pf_harness_out.log}"
RC=0

run() {
  echo "=============== $1 ==============="
  if bash "$SCRIPT_DIR/$1" "$TIMEOUT" >"$OUT" 2>&1; then
    echo "PASS $1"
  else
    echo "FAIL $1"
    RC=1
  fi
  # The per-check lines, which are what says WHICH assertion went. The full trace stays in $OUT.
  grep -E '^  (OK|FAIL)' "$OUT" | tail -30
}

run run_sim_pair.sh
run run_sim_pair_mismatch.sh
run run_sim_pair_coldstart.sh
run run_sim_pair_forcesync.sh
run run_sim_pair_forcesync_abort.sh
run run_sim_pair_resume.sh
run run_sim_pair_offline.sh
run run_sim_pair_wifi.sh
run run_sim_pair_pairing.sh
run run_sim_pair_renderstall.sh
run run_sim_pair_heapbuild.sh
run run_sim_pair_discovery.sh
run run_sim_pair_skip.sh

echo "=============== solo page-turn regression ==============="
if bash "$SCRIPT_DIR/run_sim_script.sh" "$SCRIPT_DIR/sim_page_turn.script" >"$OUT" 2>&1; then
  echo "PASS sim_page_turn.script"
else
  echo "FAIL sim_page_turn.script"
  RC=1
fi

echo "=============== overall: $RC (0=all passed) ==============="
exit $RC
