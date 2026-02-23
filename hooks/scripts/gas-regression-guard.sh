#!/bin/bash
set -uo pipefail

THRESHOLD="${GAS_REGRESSION_THRESHOLD:-500}"
SNAPSHOT_PATH="${GAS_SNAPSHOT_PATH:-.gas-snapshot}"

if ! command -v forge &>/dev/null; then
  echo "GAS_GUARD: forge not found, skipping"; exit 0
fi
if [ ! -f "$SNAPSHOT_PATH" ]; then
  echo "GAS_GUARD: No baseline at $SNAPSHOT_PATH — run /gas:baseline --update"; exit 0
fi

DIFF_OUTPUT=$(forge snapshot --diff "$SNAPSHOT_PATH" 2>&1) || {
  echo "GAS_GUARD: forge snapshot failed (build error or no tests)"; exit 0
}

REGRESSIONS=""
while IFS= read -r line; do
  if [[ "$line" =~ \+([0-9]+)\ gas ]]; then
    GAS_DELTA="${BASH_REMATCH[1]}"
    if (( GAS_DELTA > THRESHOLD )); then
      REGRESSIONS="${REGRESSIONS}  ${line}\n"
    fi
  fi
done <<< "$DIFF_OUTPUT"

if [ -z "$REGRESSIONS" ]; then
  echo "GAS_GUARD: ✅ No regressions above ${THRESHOLD} gas"; exit 0
fi

echo ""
echo "GAS_GUARD: ⛽ REGRESSION DETECTED"
echo "GAS_GUARD: ─────────────────────────────────────────"
printf "%b" "$REGRESSIONS"
echo "GAS_GUARD: ─────────────────────────────────────────"
echo "GAS_GUARD: Threshold: ${THRESHOLD} gas | Run /gas:analyze to investigate"
echo ""
exit 0
