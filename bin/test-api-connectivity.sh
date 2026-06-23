#!/bin/bash
# test-api-connectivity.sh — Standalone DeepSeek/OpenAI API connectivity test
# Usage: ./test-api-connectivity.sh [api_key]
#   or set DEEPSEEK_API_KEY or OPENAI_API_KEY in environment
set -euo pipefail

API_KEY="${1:-${DEEPSEEK_API_KEY:-${OPENAI_API_KEY:-}}}"
if [ -z "$API_KEY" ]; then
  echo "No API key. Set DEEPSEEK_API_KEY, OPENAI_API_KEY, or pass as argument."
  exit 1
fi

# Determine endpoint and model
if [ -n "${DEEPSEEK_API_KEY:-}" ] || [ -n "${1:-}" ]; then
  API_URL="https://api.deepseek.com/v1/chat/completions"
  MODEL="deepseek-chat"
  PROVIDER="DeepSeek"
else
  API_URL="${OPENAI_API_BASE:-https://api.openai.com/v1/chat/completions}"
  # Strip trailing /v1 if present and re-add
  if [[ "$API_URL" != */chat/completions ]]; then
    API_URL="${API_URL%/}"
    API_URL="${API_URL%/v1}"
    API_URL="${API_URL}/v1/chat/completions"
  fi
  MODEL="${VPROJ_AI_MODEL:-gpt-4o-mini}"
  PROVIDER="OpenAI"
fi

echo "=== API Connectivity Test ==="
echo "Provider:  $PROVIDER"
echo "Endpoint:  $API_URL"
echo "Model:     $MODEL"
echo ""

# Test 1: DNS resolution
HOST=$(echo "$API_URL" | sed 's|https://||;s|/.*||')
echo "--- Test 1: DNS resolution ($HOST) ---"
if host "$HOST" > /dev/null 2>&1; then
  echo "PASS: $HOST resolves"
else
  echo "FAIL: cannot resolve $HOST"
fi

# Test 2: TCP connectivity
echo ""
echo "--- Test 2: TCP connectivity ($HOST:443) ---"
if timeout 5 bash -c "echo >/dev/tcp/$HOST/443" 2>/dev/null; then
  echo "PASS: can connect to $HOST:443"
else
  echo "FAIL: cannot connect to $HOST:443 (check firewall/proxy)"
fi

# Test 3: API call (non-streaming, simple ping)
echo ""
echo "--- Test 3: API call (simple ping) ---"
CURL_OUT=$(mktemp) || CURL_OUT="/tmp/test-api-out.$$"
CURL_ERR=$(mktemp) || CURL_ERR="/tmp/test-api-err.$$"

HTTP_CODE=$(curl -sS -w "%{http_code}" -o "$CURL_OUT" \
  --connect-timeout 10 -m 30 \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one word\"}],\"stream\":false,\"max_tokens\":10}" \
  "$API_URL" 2>"$CURL_ERR" || true)

echo "HTTP status: $HTTP_CODE"

if [ -s "$CURL_ERR" ]; then
  echo "curl stderr:"
  cat "$CURL_ERR"
fi

if [ "$HTTP_CODE" = "200" ]; then
  echo ""
  echo "PASS: API responded 200"
  echo "Response:"
  cat "$CURL_OUT" | head -5
  # Try to extract content
  CONTENT=$(grep -o '"content":"[^"]*"' "$CURL_OUT" 2>/dev/null | head -1 | sed 's/"content":"//;s/"$//' || echo "(could not parse)")
  echo "Content:  $CONTENT"
elif [ -s "$CURL_OUT" ]; then
  echo ""
  echo "Response body:"
  head -20 "$CURL_OUT"
else
  echo ""
  echo "FAIL: No response body (check API key and endpoint)"
fi

rm -f "$CURL_OUT" "$CURL_ERR"

echo ""
echo "=== Test complete ==="
echo "If all tests pass: the API is reachable and your key works."
echo "If Test 3 fails: check API key validity and model name."
echo "If Test 1/2 fail: check network/proxy/DNS configuration."
