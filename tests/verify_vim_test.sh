#!/bin/bash
# Test verify_vim.sh — catches bad vim9script, passes good.
# Run: bash tests/verify_vim_test.sh

set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== verify_vim.sh self-tests ==="

# Test 1: exists
if [ -x "./bin/verify_vim.sh" ]; then
  echo "PASS: verify_vim.sh exists and is executable"
else
  echo "FAIL: verify_vim.sh missing or not executable"
  exit 1
fi

# Test 2: catches bad vim9script
BAD=$(mktemp)
echo "vim9script" > "$BAD"
echo "nosuchcommand 123" >> "$BAD"
if ./bin/verify_vim.sh "$BAD" > /tmp/vv_out.txt 2>&1; then
  echo "FAIL: should have exited non-zero for bad file"
  rm -f "$BAD"
  exit 1
else
  if grep -qE "E492|Error detected" /tmp/vv_out.txt; then
    echo "PASS: catches bad vim9script"
  else
    echo "FAIL: output missing error signature"
    cat /tmp/vv_out.txt
    rm -f "$BAD"
    exit 1
  fi
fi
rm -f "$BAD"

# Test 3: passes good vim9script
GOOD=$(mktemp)
cat > "$GOOD" << 'GOODEOF'
vim9script
var x: number = 42
def Good(): string
  return 'ok'
enddef
GOODEOF
if ./bin/verify_vim.sh "$GOOD" > /tmp/vv_out.txt 2>&1; then
  echo "PASS: accepts valid vim9script"
else
  echo "FAIL: rejected valid file"
  cat /tmp/vv_out.txt
  rm -f "$GOOD"
  exit 1
fi
rm -f "$GOOD"

# Test 4: our actual source files compile
for f in src/autoload/vproj_ai.vim tests/vim_agent_runtime.vim; do
  if ./bin/verify_vim.sh "$f" > /tmp/vv_out.txt 2>&1; then
    echo "PASS: $f compiles"
  else
    echo "FAIL: $f has errors"
    cat /tmp/vv_out.txt
    exit 1
  fi
done

rm -f /tmp/vv_out.txt
echo "=== All verify_vim.sh self-tests passed ==="
