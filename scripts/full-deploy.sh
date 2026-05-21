#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TARGET=""
IMAGE_TAG="latest"

while [[ $# -gt 0 ]]; do
  case $1 in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 --target <blue|green> [--image-tag <tag>]"
      exit 1
      ;;
  esac
done

if [[ -z "${TARGET}" ]]; then
  echo "ERROR: --target is required"
  echo "Usage: $0 --target <blue|green> [--image-tag <tag>]"
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

ROUTING_FILE="${REPO_ROOT}/traefik/dynamic/routing.yml"

CURRENT_ENV="unknown"
if [[ -f "${ROUTING_FILE}" ]]; then
  if grep -q 'frontend-blue' "${ROUTING_FILE}"; then
    CURRENT_ENV="blue"
  elif grep -q 'frontend-green' "${ROUTING_FILE}"; then
    CURRENT_ENV="green"
  fi
fi

echo "============================================"
echo "  Yomu Blue-Green Deployment"
echo "============================================"
echo "Current active: ${CURRENT_ENV^^}"
echo "Deploy target:  ${TARGET^^}"
echo "Image tag:      ${IMAGE_TAG}"
echo ""

DEPLOY_ENV="${TARGET}"

echo "=== Step 1: Deploying ${DEPLOY_ENV^^} environment ==="
bash "${SCRIPT_DIR}/deploy-${DEPLOY_ENV}.sh" --image-tag "${IMAGE_TAG}"

echo ""
echo "=== Step 2: Health check on ${DEPLOY_ENV^^} environment ==="
COMPOSE_FILE="${REPO_ROOT}/docker-compose/docker-compose.${DEPLOY_ENV}.yml"

echo "Waiting for ${DEPLOY_ENV^^} services to stabilize..."
sleep 5

UNHEALTHY=$(docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${COMPOSE_FILE}" ps --format '{{.Name}} {{.Health}}' 2>/dev/null | grep -v -E '(healthy|starting)' || true)

if [[ -n "${UNHEALTHY}" ]]; then
  echo "FAIL: Not all ${DEPLOY_ENV^^} services are healthy:"
  echo "${UNHEALTHY}"
  echo ""
  echo "Deployment ABORTED. Current environment (${CURRENT_ENV^^}) remains active."
  exit 1
fi

echo "All ${DEPLOY_ENV^^} services are healthy."
echo ""

echo "=== Step 3: Smoke tests against ${DEPLOY_ENV^^} ==="
SMOKE_PASS=0
SMOKE_FAIL=0

if curl -sf --max-time 10 http://localhost/api/java/actuator/health/readiness > /dev/null 2>&1; then
  echo "  [PASS] Java API health endpoint"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Java API health endpoint"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

if curl -sf --max-time 10 http://localhost/api/rust/health > /dev/null 2>&1; then
  echo "  [PASS] Rust API health endpoint"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Rust API health endpoint"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

if curl -sf --max-time 10 http://localhost > /dev/null 2>&1; then
  echo "  [PASS] Frontend"
  SMOKE_PASS=$((SMOKE_PASS + 1))
else
  echo "  [FAIL] Frontend"
  SMOKE_FAIL=$((SMOKE_FAIL + 1))
fi

if [[ ${SMOKE_FAIL} -gt 0 ]]; then
  echo ""
  echo "FAIL: Smoke tests failed (${SMOKE_FAIL}/$((SMOKE_PASS + SMOKE_FAIL)))."
  echo "Deployment ABORTED. Current environment (${CURRENT_ENV^^}) remains active."
  exit 1
fi

echo "All smoke tests passed."
echo ""

echo "=== Step 4: Switching traffic to ${DEPLOY_ENV^^} ==="
bash "${SCRIPT_DIR}/switch-traffic.sh" "${DEPLOY_ENV}"

if [[ $? -ne 0 ]]; then
  echo ""
  echo "FAIL: Traffic switch encountered errors."
  echo "Consider running scripts/rollback.sh to revert."
  exit 1
fi

echo ""
echo "============================================"
echo "  Deployment Complete"
echo "============================================"
echo "Previous environment: ${CURRENT_ENV^^}"
echo "Current environment:  ${DEPLOY_ENV^^}"
echo ""

# WARNING: Uncomment the block below to automatically stop the old environment after a successful switch.
# This is risky because it removes the ability to quickly rollback.
#
# OLD_ENV=""
# if [[ "${DEPLOY_ENV}" == "blue" ]]; then
#   OLD_ENV="green"
# else
#   OLD_ENV="blue"
# fi
#
# if [[ "${OLD_ENV}" != "unknown" && "${OLD_ENV}" != "${CURRENT_ENV}" ]]; then
#   echo "=== Step 5 (optional): Stopping old ${OLD_ENV^^} environment ==="
#   docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.${OLD_ENV}.yml" down
#   echo "Old ${OLD_ENV^^} environment stopped."
# fi