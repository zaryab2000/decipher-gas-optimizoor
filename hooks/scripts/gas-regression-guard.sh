#!/bin/bash
# Gas regression guard — PostToolUse hook for src/**/*.sol Write/Edit events.
# Runs forge snapshot --diff and warns when any test's gas increases above the
# configured threshold. Always exits 0 — never breaks the Claude Code session.
set -euo pipefail

THRESHOLD="${GAS_REGRESSION_THRESHOLD:-500}"
SNAPSHOT_PATH="${GAS_SNAPSHOT_PATH:-.gas-snapshot}"

if ! command -v forge &>/dev/null; then
  echo "GAS_GUARD: forge not found, skipping"; exit 0
fi
if [ ! -f "$SNAPSHOT_PATH" ]; then
  echo "GAS_GUARD: No baseline at $SNAPSHOT_PATH — run /gas:baseline --update"; exit 0
fi

# forge snapshot --diff exits non-zero on build failure; capture output regardless.
DIFF_OUTPUT=""
DIFF_OUTPUT=$(forge snapshot --diff "$SNAPSHOT_PATH" 2>&1) || true

# Regression lines from `forge snapshot --diff` look exactly like:
#   ↑ CounterTest::testFoo() (gas: 27606 → 49882 | 22276 80.693%)
# The line starts with the ↑ character (U+2191) and the delta is the integer
# immediately after "| " before the space+percentage. We match that field.
# Improvement lines use ↓ and stable lines use ━ — we ignore both.
REGRESSIONS=()
while IFS= read -r line; do
  # Match lines that start with the ↑ regression marker
  if [[ "$line" == $'\xe2\x86\x91'* ]]; then
    # Extract delta: the integer after "| " in the line
    if [[ "$line" =~ \|[[:space:]]([0-9]+)[[:space:]] ]]; then
      GAS_DELTA="${BASH_REMATCH[1]}"
      if [[ "$GAS_DELTA" -gt "$THRESHOLD" ]]; then
        REGRESSIONS+=("  ${line}")
      fi
    fi
  fi
done <<< "$DIFF_OUTPUT"

if [ "${#REGRESSIONS[@]}" -eq 0 ]; then
  echo "GAS_GUARD: No regressions above ${THRESHOLD} gas"; exit 0
fi

echo ""
echo "GAS_GUARD: REGRESSION DETECTED"
echo "GAS_GUARD: -----------------------------------------"
for regression_line in "${REGRESSIONS[@]}"; do
  echo "$regression_line"
done
echo "GAS_GUARD: -----------------------------------------"
echo "GAS_GUARD: Threshold: ${THRESHOLD} gas | Run /gas:analyze to investigate"
echo ""
exit 0
