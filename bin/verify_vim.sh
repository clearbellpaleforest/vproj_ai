#!/bin/bash
# verify_vim.sh — source a .vim file, report errors, exit 1 on failure.
# Usage: ./bin/verify_vim.sh path/to/file.vim
# Agents use this to test Vimscript edits before committing them.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: verify_vim.sh <file.vim>" >&2
  exit 2
fi

FILE="$1"
if [ ! -f "$FILE" ]; then
  echo "verify_vim.sh: file not found: $FILE" >&2
  exit 2
fi

# -N: no compat, -u NONE: no vimrc, -i NONE: no swapfile
# :source compiles; :messages shows errors; :qa! exits cleanly
OUTPUT=$(vim -N -u NONE -i NONE -c "source $(printf '%q' "$FILE")" -c "messages" -c "qa!" 2>&1) || true

# Scan for error signatures
if echo "$OUTPUT" | grep -qE '^Error detected|^E[0-9]+:|^Line\s+[0-9]+:'; then
  echo "$OUTPUT"
  exit 1
fi

# No errors found — only show non-noise output (skip "Messages maintainer" boilerplate)
FILTERED=$(echo "$OUTPUT" | grep -v '^Messages maintainer:' | grep -v '^$' || true)
if [ -n "$FILTERED" ]; then
  echo "$FILTERED"
fi
exit 0
