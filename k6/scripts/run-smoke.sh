#!/bin/bash
set -euo pipefail

if ! command -v k6 &>/dev/null; then
  echo "Error: k6 is not installed."
  echo "Install it from: https://k6.io/docs/get-started/installation/"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_ROOT="$(dirname "$SCRIPT_DIR")"

echo "=== Running k6 Smoke Test ==="
echo "Target: ${K6_BASE_URL:-http://localhost}"
echo ""

k6 run "${K6_ROOT}/smoke/smoke-test.js"
exit_code=$?

echo ""
if [ $exit_code -eq 0 ]; then
  echo "✅ Smoke test passed"
else
  echo "❌ Smoke test failed (exit code: ${exit_code})"
fi

exit $exit_code