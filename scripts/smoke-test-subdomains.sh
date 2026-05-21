#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PASS=0
FAIL=0
RESULTS=()

check_url() {
  local label="$1"
  local url="$2"
  local extra_opts="${3:-}"

  local cmd="curl -sf --max-time 15"
  if [[ -n "${extra_opts}" ]]; then
    cmd="${cmd} ${extra_opts}"
  fi
  cmd="${cmd} \"${url}\""

  if eval "${cmd}" > /dev/null 2>&1; then
    RESULTS+=("PASS|${label}")
    PASS=$((PASS + 1))
    echo "  [PASS] ${label}"
  else
    RESULTS+=("FAIL|${label}")
    FAIL=$((FAIL + 1))
    echo "  [FAIL] ${label}"
  fi
}

echo "============================================"
echo "  Yomu Subdomain Smoke Test"
echo "============================================"
echo ""

check_url "Rust API (rust.yomu.my.id/health)" "https://rust.yomu.my.id/health" "-k"
check_url "Java API (java.yomu.my.id/actuator/health/readiness)" "https://java.yomu.my.id/actuator/health/readiness" "-k"
check_url "Frontend (yomu.my.id)" "https://yomu.my.id/" "-k -L"

echo ""
echo "============================================"
echo "  Smoke Test Results"
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
