#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

GRAFANA_URL="${GRAFANA_URL:-http://localhost:3000}"
GRAFANA_ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
GRAFANA_ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"

DEPLOY_VERSION="${1:-unknown}"
DEPLOY_ENV="${2:-unknown}"

echo "=== Yomu Grafana Deployment Annotation ==="

# Try to source .env if password is not set
if [[ -z "${GRAFANA_ADMIN_PASSWORD}" ]]; then
  ENV_FILE="${REPO_ROOT}/docker-compose/.env"
  if [[ -f "${ENV_FILE}" ]]; then
    # shellcheck source=/dev/null
    set -a
    # shellcheck source=/dev/null
    source "${ENV_FILE}" 2>/dev/null || true
    set +a
  fi
fi

if [[ -z "${GRAFANA_ADMIN_PASSWORD}" ]]; then
  echo "ERROR: GRAFANA_ADMIN_PASSWORD is not set."
  echo "Pass it as an environment variable or place it in docker-compose/.env"
  exit 1
fi

if ! curl -sf --max-time 5 "${GRAFANA_URL}/api/health" > /dev/null 2>&1; then
  echo "ERROR: Grafana is not reachable at ${GRAFANA_URL}"
  exit 1
fi

TIMESTAMP_MS=$(date +%s%3N)

PAYLOAD=$(cat <<EOF
{
  "time": ${TIMESTAMP_MS},
  "timeEnd": ${TIMESTAMP_MS},
  "tags": [
    "deploy",
    "${DEPLOY_ENV}"
  ],
  "text": "Yomu deployment\\nVersion: ${DEPLOY_VERSION}\\nEnvironment: ${DEPLOY_ENV}"
}
EOF
)

echo "Posting deployment annotation to Grafana..."
echo "  URL:       ${GRAFANA_URL}"
echo "  Version:   ${DEPLOY_VERSION}"
echo "  Env:       ${DEPLOY_ENV}"

RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -u "${GRAFANA_ADMIN_USER}:${GRAFANA_ADMIN_PASSWORD}" \
  -d "${PAYLOAD}" \
  "${GRAFANA_URL}/api/annotations" 2>/dev/null || true)

HTTP_CODE=$(echo "${RESPONSE}" | grep -oP 'HTTP_CODE:\K[0-9]+' || true)
BODY=$(echo "${RESPONSE}" | sed '/HTTP_CODE:/d' || true)

if [[ "${HTTP_CODE}" == "200" ]]; then
  echo "SUCCESS: Deployment annotation created."
  echo "  Response: ${BODY}"
  exit 0
else
  echo "ERROR: Failed to create annotation (HTTP ${HTTP_CODE})."
  echo "  Response: ${BODY}"
  exit 1
fi
