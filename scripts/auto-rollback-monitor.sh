#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PROMETHEUS_URL="${PROMETHEUS_URL:-http://localhost:9090}"
MONITOR_DURATION_MINUTES=5
CHECK_INTERVAL_SECONDS=15
MAX_ERROR_RATE=5.0
MAX_LATENCY_SECONDS=2.0

ROLLBACK_SCRIPT="${SCRIPT_DIR}/rollback.sh"

if [[ ! -x "${ROLLBACK_SCRIPT}" ]]; then
  echo "ERROR: rollback.sh not found or not executable at ${ROLLBACK_SCRIPT}"
  exit 1
fi

wait_for_prometheus() {
  local attempts=0
  while [[ ${attempts} -lt 6 ]]; do
    if curl -sf --max-time 5 "${PROMETHEUS_URL}/-/healthy" > /dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts + 1))
    echo "Waiting for Prometheus to be ready... (${attempts}/6)"
    sleep 5
  done
  echo "ERROR: Prometheus is not reachable at ${PROMETHEUS_URL}"
  exit 1
}

query_prometheus() {
  local promql="$1"
  local encoded_query
  encoded_query=$(curl -sG --data-urlencode "query=${promql}" "${PROMETHEUS_URL}/api/v1/query" 2>/dev/null || true)
  echo "${encoded_query}"
}

extract_value() {
  local json="$1"
  local value
  value=$(echo "${json}" | grep -oP '(?<="value":\[)[^\]]*' | awk -F',' '{print $2}' || true)
  if [[ -z "${value}" || "${value}" == "null" ]]; then
    echo "NaN"
  else
    echo "${value}"
  fi
}

echo "=== Blue-Green Deployment Auto-Rollback Monitor ==="
echo "Prometheus:       ${PROMETHEUS_URL}"
echo "Duration:         ${MONITOR_DURATION_MINUTES} minutes"
echo "Check interval:   ${CHECK_INTERVAL_SECONDS} seconds"
echo "Max error rate:   ${MAX_ERROR_RATE}%"
echo "Max p95 latency:  ${MAX_LATENCY_SECONDS}s"
echo ""

wait_for_prometheus

ERROR_PROMQL='sum(rate(traefik_service_requests_total{code=~"5.."}[1m])) / sum(rate(traefik_service_requests_total[1m])) * 100'
LATENCY_PROMQL='histogram_quantile(0.95, sum(rate(traefik_entrypoint_request_duration_seconds_bucket[1m])) by (le))'

TOTAL_CHECKS=$((MONITOR_DURATION_MINUTES * 60 / CHECK_INTERVAL_SECONDS))
CHECK_COUNT=0
ROLLED_BACK=0

while [[ ${CHECK_COUNT} -lt ${TOTAL_CHECKS} ]]; do
  CHECK_COUNT=$((CHECK_COUNT + 1))
  TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

  echo "[${TIMESTAMP}] Check ${CHECK_COUNT}/${TOTAL_CHECKS}"

  error_json=$(query_prometheus "${ERROR_PROMQL}")
  latency_json=$(query_prometheus "${LATENCY_PROMQL}")

  error_rate=$(extract_value "${error_json}")
  latency=$(extract_value "${latency_json}")

  if [[ "${error_rate}" == "NaN" ]]; then
    error_rate="0.0"
  fi
  if [[ "${latency}" == "NaN" ]]; then
    latency="0.0"
  fi

  echo "  Error rate (5xx): ${error_rate}%"
  echo "  P95 latency:      ${latency}s"

  needs_rollback=0

  if awk "BEGIN {exit !(${error_rate} > ${MAX_ERROR_RATE})}"; then
    echo "  ALERT: Error rate ${error_rate}% exceeds threshold ${MAX_ERROR_RATE}%"
    needs_rollback=1
  fi

  if awk "BEGIN {exit !(${latency} > ${MAX_LATENCY_SECONDS})}"; then
    echo "  ALERT: P95 latency ${latency}s exceeds threshold ${MAX_LATENCY_SECONDS}s"
    needs_rollback=1
  fi

  if [[ ${needs_rollback} -eq 1 ]]; then
    echo ""
    echo "CRITICAL: Thresholds exceeded. Initiating automatic rollback..."
    echo ""
    if bash "${ROLLBACK_SCRIPT}"; then
      echo "Auto-rollback completed successfully."
      ROLLED_BACK=1
    else
      echo "ERROR: Auto-rollback script failed."
      exit 1
    fi
    break
  fi

  sleep "${CHECK_INTERVAL_SECONDS}"
done

echo ""

if [[ ${ROLLED_BACK} -eq 1 ]]; then
  echo "=== Monitoring ended: Rollback was triggered ==="
  exit 0
fi

echo "=== Monitoring complete: All checks passed ==="
echo "Total checks: ${CHECK_COUNT}"
echo "No thresholds exceeded. Deployment is stable."
exit 0
