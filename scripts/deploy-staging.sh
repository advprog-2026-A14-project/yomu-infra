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

if ! docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
  echo "ERROR: Docker Swarm is not active"
  exit 1
fi

echo "=== Deploying STAGING services via Swarm (image-tag: ${IMAGE_TAG}) ==="

echo "Updating java-staging..."
docker service update \
  --with-registry-auth \
  --image "ghcr.io/advprog-2026-a14-project/yomu-backend-java:${IMAGE_TAG}" \
  yomu_java-staging

echo "Updating rust-staging..."
docker service update \
  --with-registry-auth \
  --image "ghcr.io/advprog-2026-a14-project/yomu-backend-rust:${IMAGE_TAG}" \
  yomu_rust-staging

echo "Updating frontend-staging..."
docker service update \
  --with-registry-auth \
  --image "ghcr.io/advprog-2026-a14-project/yomu-frontend:${IMAGE_TAG}" \
  yomu_frontend-staging

echo "Waiting for STAGING services to become healthy..."
MAX_ATTEMPTS=60
ATTEMPT=0
ALL_HEALTHY=false

while [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; do
  ATTEMPT=$((ATTEMPT + 1))

  UNHEALTHY=$(docker service ls \
    --format '{{.Name}} {{.Replicas}}' |
    grep -E 'yomu_(java-staging|rust-staging|frontend-staging)' |
    awk '$2 !~ /1\/1/ {print $1 " " $2}' || true)

  if [[ -z "${UNHEALTHY}" ]]; then
    ALL_HEALTHY=true
    break
  fi

  if [[ $ATTEMPT -eq 1 ]]; then
    echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: waiting for services to start..."
  elif [[ $((ATTEMPT % 6)) -eq 0 ]]; then
    echo "  Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: still waiting... (${UNHEALTHY//$'\n'/, })"
  fi

  sleep 5
done

if [[ "${ALL_HEALTHY}" != "true" ]]; then
  echo "ERROR: STAGING services did not reach 1/1 replicas within $((MAX_ATTEMPTS * 5)) seconds"
  docker service ls --filter name=yomu_ --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'
  exit 1
fi

echo ""
echo "=== STAGING services deployed successfully ==="
docker service ls --filter name=yomu_ --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}'
echo ""
echo "Staging is available at: https://staging.yomu.my.id"
echo "API endpoints:"
echo "  https://java-staging.yomu.my.id"
echo "  https://rust-staging.yomu.my.id"
