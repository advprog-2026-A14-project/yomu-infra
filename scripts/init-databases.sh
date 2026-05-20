#!/bin/bash
set -euo pipefail

# ============================================================
# Yomu Platform - Manual Database Initialization
# ============================================================
# Use this script if the initdb.d volume mount didn't run
# (e.g., postgres_data volume already existed from a prior start).
#
# Usage: ./scripts/init-databases.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source .env if available
if [[ -f "${SCRIPT_DIR}/../docker-compose/.env" ]]; then
  set -a
  source "${SCRIPT_DIR}/../docker-compose/.env"
  set +a
fi

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:?POSTGRES_PASSWORD is required}"

echo "=== Initializing Yomu databases ==="

# Check if postgres container is running
if ! docker ps --format '{{.Names}}' | grep -q '^postgres$'; then
  echo "ERROR: postgres container is not running. Start shared services first:"
  echo "  docker compose -f docker-compose/docker-compose.shared.yml up -d"
  exit 1
fi

echo "Creating databases..."
docker exec postgres psql -U "${POSTGRES_USER}" -c "SELECT 1 FROM pg_database WHERE datname = 'yomu_engine'" | grep -q 1 || \
  docker exec postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE yomu_engine;"

docker exec postgres psql -U "${POSTGRES_USER}" -c "SELECT 1 FROM pg_database WHERE datname = 'yomu_db_staging'" | grep -q 1 || \
  docker exec postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE yomu_db_staging;"

docker exec postgres psql -U "${POSTGRES_USER}" -c "SELECT 1 FROM pg_database WHERE datname = 'yomu_engine_staging'" | grep -q 1 || \
  docker exec postgres psql -U "${POSTGRES_USER}" -c "CREATE DATABASE yomu_engine_staging;"

echo "Granting privileges..."
docker exec postgres psql -U "${POSTGRES_USER}" -c "GRANT ALL PRIVILEGES ON DATABASE yomu_engine TO ${POSTGRES_USER};"
docker exec postgres psql -U "${POSTGRES_USER}" -c "GRANT ALL PRIVILEGES ON DATABASE yomu_db_staging TO ${POSTGRES_USER};"
docker exec postgres psql -U "${POSTGRES_USER}" -c "GRANT ALL PRIVILEGES ON DATABASE yomu_engine_staging TO ${POSTGRES_USER};"

echo "=== Database initialization complete ==="
docker exec postgres psql -U "${POSTGRES_USER}" -c "\l" | grep -E 'yomu|Name' || true