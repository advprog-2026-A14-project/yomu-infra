#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_TAG="staging"

while [[ $# -gt 0 ]]; do
  case $1 in
    --image-tag)
      IMAGE_TAG="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--image-tag <tag>]"
      exit 1
      ;;
  esac
done

export STAGING_IMAGE_TAG="${IMAGE_TAG}"

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible"
  exit 1
fi

echo "=== Deploying STAGING environment (image-tag: ${IMAGE_TAG}) ==="

docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.staging.yml" pull frontend-staging java-staging rust-staging

docker compose \
  -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" \
  -f "${REPO_ROOT}/docker-compose/docker-compose.staging.yml" \
  up -d --force-recreate --no-deps frontend-staging java-staging rust-staging

echo "Waiting for STAGING services to become healthy..."
MAX_ATTEMPTS=60
ATTEMPT=0
ALL_HEALTHY=false

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  UNHEALTHY=$(docker compose \
    -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" \
    -f "${REPO_ROOT}/docker-compose/docker-compose.staging.yml" \
    ps --format '{{.Name}} {{.Health}}' 2>/dev/null | grep -v -E '(healthy|starting)' || true)

  if [[ -z "${UNHEALTHY}" ]]; then
    ALL_HEALTHY=true
    break
  fi

  echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: services still starting... (${UNHEALTHY//$'\n'/, })"
  sleep 5
done

if [[ "${ALL_HEALTHY}" != "true" ]]; then
  echo "ERROR: STAGING services did not become healthy within $((MAX_ATTEMPTS * 5)) seconds"
  docker compose \
    -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" \
    -f "${REPO_ROOT}/docker-compose/docker-compose.staging.yml" \
    ps
  exit 1
fi

echo ""
echo "=== STAGING environment deployed successfully ==="
docker compose \
  -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" \
  -f "${REPO_ROOT}/docker-compose/docker-compose.staging.yml" \
  ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
echo ""
echo "Staging is available at: http://staging.yomu.my.id"
