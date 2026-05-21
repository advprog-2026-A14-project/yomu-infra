#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROUTING_FILE="${REPO_ROOT}/traefik/dynamic/routing.yml"

echo "=== Yomu Blue-Green Cleanup ==="

if [[ ! -f "${ROUTING_FILE}" ]]; then
  echo "ERROR: No routing.yml found at ${ROUTING_FILE}"
  exit 1
fi

ACTIVE_ENV=""
if grep -q 'frontend-blue' "${ROUTING_FILE}"; then
  ACTIVE_ENV="blue"
  INACTIVE_ENV="green"
elif grep -q 'frontend-green' "${ROUTING_FILE}"; then
  ACTIVE_ENV="green"
  INACTIVE_ENV="blue"
else
  echo "ERROR: Cannot determine current active environment from routing.yml"
  exit 1
fi

echo "Active environment:  ${ACTIVE_ENV^^}"
echo "Inactive environment: ${INACTIVE_ENV^^}"

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible"
  exit 1
fi

INACTIVE_COMPOSE="${REPO_ROOT}/docker-compose/docker-compose.${INACTIVE_ENV}.yml"

if [[ ! -f "${INACTIVE_COMPOSE}" ]]; then
  echo "ERROR: Compose file not found at ${INACTIVE_COMPOSE}"
  exit 1
fi

RUNNING=$(docker compose -f "${INACTIVE_COMPOSE}" ps -q 2>/dev/null || true)

if [[ -z "${RUNNING}" ]]; then
  echo "No running containers found for ${INACTIVE_ENV^^} environment. Nothing to clean up."
  exit 0
fi

echo ""
echo "Stopping ${INACTIVE_ENV^^} environment containers..."
docker compose -f "${INACTIVE_COMPOSE}" down --remove-orphans

echo ""
echo "=== Cleanup complete ==="
echo "Stopped: ${INACTIVE_ENV^^} environment"
echo "Active:  ${ACTIVE_ENV^^} environment"
exit 0
