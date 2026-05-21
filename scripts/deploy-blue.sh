#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

IMAGE_TAG="latest"

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

export IMAGE_TAG

if ! docker info > /dev/null 2>&1; then
  echo "ERROR: Docker is not running or not accessible"
  exit 1
fi

echo "=== Deploying BLUE environment (image-tag: ${IMAGE_TAG}) ==="

# Pull latest images first
docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.blue.yml" pull frontend-blue java-blue rust-blue

# Only recreate application containers — shared infra (postgres, redis, traefik)
# must NOT restart to avoid breaking the active environment.
docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${REPO_ROOT}/docker-compose/docker-compose.blue.yml" up -d --force-recreate frontend-blue java-blue rust-blue

echo "Waiting for BLUE services to become healthy..."
MAX_ATTEMPTS=60
ATTEMPT=0
ALL_HEALTHY=false

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))
  UNHEALTHY=$(docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${REPO_ROOT}/docker-compose/docker-compose.blue.yml" ps --format '{{.Name}} {{.Health}}' 2>/dev/null | grep -v -E '(healthy|starting)' || true)

  if [[ -z "${UNHEALTHY}" ]]; then
    ALL_HEALTHY=true
    break
  fi

  echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: services still starting... (${UNHEALTHY//$'\n'/, })"
  sleep 5
done

if [[ "${ALL_HEALTHY}" != "true" ]]; then
  echo "ERROR: BLUE services did not become healthy within $((MAX_ATTEMPTS * 5)) seconds"
  docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${REPO_ROOT}/docker-compose/docker-compose.blue.yml" ps
  exit 1
fi

echo ""
echo "=== BLUE environment deployed successfully ==="
docker compose -f "${REPO_ROOT}/docker-compose/docker-compose.shared.yml" -f "${REPO_ROOT}/docker-compose/docker-compose.blue.yml" ps --format "table {{.Name}}\t{{.Status}}\t{{.Health}}"
echo ""
echo "NOTE: Traffic has NOT been switched. Run scripts/switch-traffic.sh to route traffic to BLUE."