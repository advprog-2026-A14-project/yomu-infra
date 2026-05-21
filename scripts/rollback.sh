#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROUTING_FILE="${REPO_ROOT}/traefik/dynamic/routing.yml"

if [[ ! -f "${ROUTING_FILE}" ]]; then
  echo "ERROR: No routing.yml found at ${ROUTING_FILE}"
  echo "Cannot determine current active environment."
  exit 1
fi

CURRENT_ENV=""
if grep -q 'frontend-blue' "${ROUTING_FILE}"; then
  CURRENT_ENV="blue"
elif grep -q 'frontend-green' "${ROUTING_FILE}"; then
  CURRENT_ENV="green"
else
  echo "ERROR: Cannot determine current active environment from routing.yml"
  exit 1
fi

TARGET_ENV=""
if [[ "${CURRENT_ENV}" == "blue" ]]; then
  TARGET_ENV="green"
else
  TARGET_ENV="blue"
fi

echo "=== Rolling back from ${CURRENT_ENV^^} to ${TARGET_ENV^^} ==="
echo "Current active: ${CURRENT_ENV^^}"
echo "Rolling back to: ${TARGET_ENV^^}"

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible"
  exit 1
fi

COMPOSE_FILE="${REPO_ROOT}/docker-compose/docker-compose.${TARGET_ENV}.yml"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
  echo "ERROR: Compose file ${COMPOSE_FILE} not found"
  exit 1
fi

echo "Verifying ${TARGET_ENV^^} services are healthy..."
  SERVICES_RUNNING=$(docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${COMPOSE_FILE}" ps --format '{{.Name}} {{.Health}}' 2>/dev/null || true)

if [[ -z "${SERVICES_RUNNING}" ]]; then
  echo "ERROR: ${TARGET_ENV^^} environment is not running. Cannot rollback."
  echo "Start it first with: scripts/deploy-${TARGET_ENV}.sh"
  exit 1
fi

UNHEALTHY=$(echo "${SERVICES_RUNNING}" | grep -v -E '(healthy|starting)' || true)

if [[ -n "${UNHEALTHY}" ]]; then
  echo "ERROR: Not all ${TARGET_ENV^^} services are healthy:"
  echo "${UNHEALTHY}"
  echo "Cannot rollback to unhealthy environment."
  exit 1
fi

echo "All ${TARGET_ENV^^} services are healthy. Proceeding with rollback."

echo "Updating Traefik routing configuration..."
cp "${REPO_ROOT}/traefik/dynamic/${TARGET_ENV}-active.yml" "${REPO_ROOT}/traefik/dynamic/routing.yml"

echo "Triggering Traefik configuration reload..."
if docker ps --format '{{.Names}}' | grep -q 'traefik'; then
  TRAEFIK_CONTAINER=$(docker ps --format '{{.Names}}' | grep traefik | head -1)
  docker kill --signal=HUP "${TRAEFIK_CONTAINER}" 2>/dev/null || true
  echo "Sent HUP signal to ${TRAEFIK_CONTAINER}"
else
  echo "WARNING: No running Traefik container found."
fi

sleep 2

echo "Verifying health after rollback..."
VERIFY_PASS=0
VERIFY_FAIL=0

if curl -sf --max-time 5 http://localhost/api/java/actuator/health/readiness > /dev/null 2>&1; then
  echo "  [PASS] Java API health endpoint"
  VERIFY_PASS=$((VERIFY_PASS + 1))
else
  echo "  [FAIL] Java API health endpoint"
  VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

if curl -sf --max-time 5 http://localhost/api/rust/health > /dev/null 2>&1; then
  echo "  [PASS] Rust API health endpoint"
  VERIFY_PASS=$((VERIFY_PASS + 1))
else
  echo "  [FAIL] Rust API health endpoint"
  VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

if curl -sf --max-time 5 http://localhost > /dev/null 2>&1; then
  echo "  [PASS] Frontend"
  VERIFY_PASS=$((VERIFY_PASS + 1))
else
  echo "  [FAIL] Frontend"
  VERIFY_FAIL=$((VERIFY_FAIL + 1))
fi

echo ""
echo "=== Rollback complete ==="
echo "Previous: ${CURRENT_ENV^^}"
echo "Current:  ${TARGET_ENV^^}"
echo "Health checks: ${VERIFY_PASS} passed, ${VERIFY_FAIL} failed"

if [[ ${VERIFY_FAIL} -gt 0 ]]; then
  echo ""
  echo "WARNING: Some health checks failed after rollback."
  exit 1
fi