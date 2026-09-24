#!/usr/bin/env bash
# Task158: baseline-vs-working-tree verifier failure-set comparison.
# Usage: bash scripts/task158_baseline_compare.sh <task_number> ...
set -u
REPO=/home/z/my-project/Amethyst-iOS-MyRemastered
BASE=/tmp/task158_baseline

for t in "$@"; do
  v="verify_task$t.py"
  [ -f "$REPO/scripts/$v" ] || { echo "task$t: (no verifier)"; continue; }
  # working tree (with Task158 changes)
  wt=$(cd "$REPO" && timeout 300 python3 "scripts/$v" 2>&1 | grep -E "^\s*\[?FAIL\]?" | sed 's/^ *\[\?FAIL\]\? *//; s/  *$//' | sort -u)
  # baseline worktree (HEAD); task158 only exists in working tree
  if [ -f "$BASE/scripts/$v" ]; then
    bt=$(cd "$BASE" && timeout 300 python3 "scripts/$v" 2>&1 | grep -E "^\s*\[?FAIL\]?" | sed 's/^ *\[\?FAIL\]\? *//; s/  *$//' | sort -u)
  else
    bt=""
  fi
  if [ "$wt" == "$bt" ]; then
    echo "task$t: BASELINE-IDENTICAL ($(echo "$wt" | grep -c . || true) env failures)"
  else
    echo "task$t: DIFFERS"
    echo "  +++ new-in-working-tree:"; diff <(echo "$bt") <(echo "$wt") | grep '^>' | sed 's/^>/    /' | head -8
    echo "  --- gone-in-working-tree:"; diff <(echo "$bt") <(echo "$wt") | grep '^<' | sed 's/^</    /' | head -8
  fi
done
