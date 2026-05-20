#!/bin/bash
set -euo pipefail

TARGET=""
BASE_URL="http://localhost"

usage() {
  echo "Usage: $0 --target <blue|green> [--base-url <url>]"
  echo ""
  echo "Options:"
  echo "  --target     Environment to validate: blue or green"
  echo "  --base-url   Base URL (default: http://localhost)"
  echo ""
  echo "Example:"
  echo "  $0 --target blue"
  echo "  $0 --target green --base-url http://staging.yomu.test"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --base-url)
      BASE_URL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "Error: --target is required"
  usage
fi

if [[ "$TARGET" != "blue" && "$TARGET" != "green" ]]; then
  echo "Error: target must be 'blue' or 'green', got: $TARGET"
  usage
fi

if ! command -v k6 &>/dev/null; then
  echo "Error: k6 is not installed."
  echo "Install it from: https://k6.io/docs/get-started/installation/"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_ROOT="$(dirname "$SCRIPT_DIR")"

echo "========================================"
echo "  Blue-Green Deployment Validation"
echo "========================================"
echo ""
echo "  Target:   ${TARGET}"
echo "  Base URL: ${BASE_URL}"
echo ""

export K6_BASE_URL="$BASE_URL"

echo "Validating ${TARGET} environment..."
echo ""

if k6 run "${K6_ROOT}/smoke/smoke-test.js"; then
  echo ""
  echo "✅ ${TARGET^} environment validated successfully"
  exit 0
else
  exit_code=$?
  echo ""
  echo "❌ ${TARGET^} environment validation FAILED"
  echo "   Do NOT switch traffic to this environment."
  exit $exit_code
fi