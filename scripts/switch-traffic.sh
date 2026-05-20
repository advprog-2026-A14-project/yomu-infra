#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET="${1:-}"

if [[ -z "${TARGET}" ]]; then
  echo "Usage: $0 <blue|green>"
  exit 1
fi

if [[ "${TARGET}" != "blue" && "${TARGET}" != "green" ]]; then
  echo "ERROR: Invalid target '${TARGET}'. Must be 'blue' or 'green'."
  exit 1
fi

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible"
  exit 1
fi

echo "=== Switching traffic to ${TARGET^^} environment ==="

COMPOSE_FILE="${REPO_ROOT}/docker-compose/docker-compose.${TARGET}.yml"

echo "Verifying ${TARGET^^} services are healthy..."
UNHEALTHY=$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.Name}} {{.Health}}' 2>/dev/null | grep -v -E '(healthy|starting)' || true)

if [[ -n "${UNHEALTHY}" ]]; then
  echo "ERROR: Not all ${TARGET^^} services are healthy:"
  echo "${UNHEALTHY}"
  echo ""
  echo "Refusing to switch traffic. Fix unhealthy services before switching."
  exit 1
fi

echo "All ${TARGET^^} services are healthy."

echo "Updating Traefik routing configuration..."
cp "${REPO_ROOT}/traefik/dynamic/${TARGET}-active.yml" "${REPO_ROOT}/traefik/dynamic/routing.yml"

echo "Triggering Traefik configuration reload..."
if docker ps --format '{{.Names}}' | grep -q 'traefik'; then
  TRAEFIK_CONTAINER=$(docker ps --format '{{.Names}}' | grep traefik | head -1)
  docker kill --signal=HUP "${TRAEFIK_CONTAINER}" 2>/dev/null || true
  echo "Sent HUP signal to ${TRAEFIK_CONTAINER}"
else
  echo "WARNING: No running Traefik container found. Configuration will be picked up on next Traefik start."
fi

sleep 2

echo ""
echo "Running smoke tests..."

SMOKE_PASS=0
SMOKE_FAIL=0

if curl -sf --max-time 5 http://localhost/api/java/actuator/health/readiness > /dev/null 2>&1; then
  echo "  [PASS] Java API health endpoint"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Java API health endpoint"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

if curl -sf --max-time 5 http://localhost/api/rust/health > /dev/null 2>&1; then
  echo "  [PASS] Rust API health endpoint"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Rust API health endpoint"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

if curl -sf --max-time 5 http://localhost > /dev/null 2>&1; then
  echo "  [PASS] Frontend"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Frontend"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

echo ""
echo "=== Traffic switch to ${TARGET^^} complete ==="
echo "Smoke tests: ${SMOKE_PASS} passed, ${SMOKE_FAIL} failed"
echo "Active environment: ${TARGET^^}"

if [[ ${SMOKE_FAIL} -gt 0 ]]; then
  echo ""
  echo "WARNING: Some smoke tests failed. Consider running scripts/rollback.sh to revert."
  exit 1
fi