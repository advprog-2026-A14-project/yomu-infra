#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

ROUTING_FILE="${REPO_ROOT}/traefik/dynamic/routing.yml"

PASS=0
FAIL=0
RESULTS=()

check() {
  local label="$1"
  local cmd="$2"

  if eval "${cmd}" > /dev/null 2>&1; then
    RESULTS+=("PASS|${label}")
    PASS=$((PASS + 1))
  else
    RESULTS+=("FAIL|${label}")
    FAIL=$((FAIL + 1))
  fi
}

echo "============================================"
echo "  Yomu Platform Health Check"
echo "============================================"
echo ""

if ! docker info > /dev/null 2>&1; then
  echo "CRITICAL: Docker is not running or not accessible"
  exit 1
fi

echo "--- Traefik ---"
check "Traefik ping" "curl -sf --max-time 5 http://localhost:3001/ping"
check "Traefik dashboard" "curl -sf --max-time 5 http://localhost:3001/api/overview"
echo ""

echo "--- Shared Services ---"
check "PostgreSQL" "docker exec \$(docker ps --format '{{.Names}}' | grep postgres | head -1) pg_isready -U postgres 2>/dev/null || false"
check "Redis" "docker exec \$(docker ps --format '{{.Names}}' | grep redis | head -1) redis-cli ping 2>/dev/null || false"
check "Prometheus" "curl -sf --max-time 5 http://localhost:9090/-/healthy"
check "Grafana" "curl -sf --max-time 5 http://localhost:3000/api/health"
echo ""

ACTIVE_ENV="unknown"
if [[ -f "${ROUTING_FILE}" ]]; then
  if grep -q 'frontend-blue' "${ROUTING_FILE}"; then
    ACTIVE_ENV="blue"
  elif grep -q 'frontend-green' "${ROUTING_FILE}" 2>/dev/null; then
    ACTIVE_ENV="green"
  fi
fi

echo "--- Active Environment: ${ACTIVE_ENV^^} ---"

if [[ "${ACTIVE_ENV}" != "unknown" ]]; then
  COMPOSE_FILE="${REPO_ROOT}/docker-compose/docker-compose.${ACTIVE_ENV}.yml"

  if [[ -f "${COMPOSE_FILE}" ]]; then
    SERVICES=$(docker compose -f "${COMPOSE_FILE}" ps --format '{{.Name}} {{.Health}}' 2>/dev/null || echo "")

    if [[ -n "${SERVICES}" ]]; then
      while IFS= read -r line; do
        NAME=$(echo "${line}" | awk '{print $1}')
        HEALTH=$(echo "${line}" | awk '{print $2}')
        if [[ "${HEALTH}" == "healthy" ]]; then
          RESULTS+=("PASS|${NAME} (container)")
          PASS=$((PASS + 1))
        else
          RESULTS+=("FAIL|${NAME} (container: ${HEALTH})")
          FAIL=$((FAIL + 1))
        fi
      done <<< "${SERVICES}"
    else
      RESULTS+=("FAIL|No ${ACTIVE_ENV^^} containers found")
      FAIL=$((FAIL + 1))
    fi
  fi
else
  RESULTS+=("FAIL|Cannot determine active environment")
  echo "WARNING: Cannot determine active environment from routing.yml" >&2
  FAIL=$((FAIL + 1))
fi

echo ""
echo "--- Endpoint Checks ---"
check "Frontend (https://yomu.my.id)" "curl -sf --max-time 5 -k -L https://yomu.my.id/"
check "Java API (https://java.yomu.my.id/actuator/health/readiness)" "curl -sf --max-time 5 -k https://java.yomu.my.id/actuator/health/readiness"
check "Rust API (https://rust.yomu.my.id/health)" "curl -sf --max-time 5 -k https://rust.yomu.my.id/health"
echo ""

echo "============================================"
echo "  Health Check Results"
echo "============================================"

printf "%-8s %s\n" "STATUS" "CHECK"
printf "%-8s %s\n" "------" "-----"

for result in "${RESULTS[@]}"; do
  STATUS="${result%%|*}"
  LABEL="${result#*|}"
  printf "%-8s %s\n" "${STATUS}" "${LABEL}"
done

echo ""
echo "Total: ${PASS} passed, ${FAIL} failed"

if [[ ${FAIL} -gt 0 ]]; then
  exit 1
fi

exit 0