#!/bin/bash
# Run the simulator under a script and surface the bits a developer / agent
# actually wants to see: the [SCRIPT] command trace, any [ERR] log lines,
# and PNG-converted screenshots (BMPs are written by the sim itself).
#
# Invoke from the firmware repo root, which is where the simulator binary
# is built and where the fs_/ mount lives:
#   bash <path-to-this-script>/run_sim_script.sh <script-path> [timeout=120]
#
# Set SIM_BIN to point at a different PlatformIO env's binary (a project may
# define more than one simulator env), and SIM_LOG to redirect the stderr log.
set -e

SCRIPT="${1:?usage: $0 <script> [timeout=120]}"
TIMEOUT="${2:-120}"
LOG="${SIM_LOG:-sim.log}"
BIN="${SIM_BIN:-./.pio/build/simulator/program}"

if [ ! -x "$BIN" ]; then
  echo "simulator binary missing at $BIN — run pio run -e simulator first" >&2
  exit 1
fi

mkdir -p fs_/screenshots

# Run. The simulator returns non-zero on script failures (expect-timeout = 3,
# parse error = 2). `timeout` adds 124 on its own deadline.
set +e
timeout "$TIMEOUT" "$BIN" --script "$SCRIPT" 2>"$LOG" >/dev/null
RC=$?
set -e

# Convert any new/updated BMPs to PNGs so the Read tool can render them.
# Pillow is the lightest dep that handles 1-bit BMP correctly.
shopt -s nullglob
for bmp in fs_/screenshots/*.bmp; do
  png="${bmp%.bmp}.png"
  if [ ! -f "$png" ] || [ "$bmp" -nt "$png" ]; then
    if python3 -c "from PIL import Image; Image.open('$bmp').save('$png')" 2>/dev/null; then
      echo "converted: $png"
    fi
  fi
done
shopt -u nullglob

# Surface the script trace + any errors. Full log is in $LOG.
echo "--- script trace ---"
grep -E '^\[SCRIPT\]' "$LOG" || true
ERRORS=$(grep -E '\[ERR\]' "$LOG" || true)
if [ -n "$ERRORS" ]; then
  echo "--- errors ---"
  echo "$ERRORS"
fi

exit "$RC"
