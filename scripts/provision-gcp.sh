#!/usr/bin/env bash
# =============================================================================
# Yomu GCP Provisioning Script
# =============================================================================
# Run once on a fresh GCP Ubuntu instance to install Docker, pull the
# deployment repo, and prepare the environment.
#
# Usage:
#   chmod +x provision-gcp.sh
#   ./provision-gcp.sh
# =============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------
YOMU_DIR="/opt/yomu"
REPO_URL="https://github.com/advprog-2026-a14-project/yomu-deployment.git"

# Determine the target user (the one who invoked sudo, or current user)
if [[ -n "${SUDO_USER:-}" ]]; then
  TARGET_USER="$SUDO_USER"
else
  TARGET_USER="$(logname 2>/dev/null || whoami)"
fi

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
info()  { echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok()    { echo -e "\033[1;32m[OK]\033[0m   $*"; }
warn()  { echo -e "\033[1;33m[WARN]\033[0m $*"; }
error() { echo -e "\033[1;31m[ERR]\033[0m  $*" >&2; }

# ------------------------------------------------------------------------------
# 1. Docker Installation
# ------------------------------------------------------------------------------
info "Checking Docker installation..."

if command -v docker &>/dev/null; then
  ok "Docker is already installed: $(docker --version)"
else
  info "Docker not found. Installing via get.docker.com ..."
  curl -fsSL https://get.docker.com | sh
  ok "Docker installed: $(docker --version)"
fi

# Ensure Docker Compose plugin is available
if ! docker compose version &>/dev/null; then
  info "Installing Docker Compose plugin..."
  apt-get update -qq
  apt-get install -y -qq docker-compose-plugin
fi
ok "Docker Compose: $(docker compose version)"

# ------------------------------------------------------------------------------
# 2. Add user to docker group
# ------------------------------------------------------------------------------
info "Adding user '\033[1m${TARGET_USER}\033[0m' to the 'docker' group..."
usermod -aG docker "${TARGET_USER}" || warn "Could not add ${TARGET_USER} to docker group"
ok "User '${TARGET_USER}' added to docker group"

# ------------------------------------------------------------------------------
# 3. Create Yomu directories
# ------------------------------------------------------------------------------
info "Creating Yomu deployment directories..."

mkdir -p "${YOMU_DIR}"
mkdir -p "${YOMU_DIR}/traefik/certificates"
mkdir -p "${YOMU_DIR}/monitoring/screenshots"
mkdir -p "${YOMU_DIR}/monitoring/reports"
mkdir -p "${YOMU_DIR}/monitoring/benchmarks"
mkdir -p "${YOMU_DIR}/scripts"

# Ensure the target user owns everything
chown -R "${TARGET_USER}:${TARGET_USER}" "${YOMU_DIR}"
chmod 750 "${YOMU_DIR}"

ok "Directories created under ${YOMU_DIR}"

# ------------------------------------------------------------------------------
# 4. Clone the deployment repo
# ------------------------------------------------------------------------------
info "Cloning deployment repository..."

if [[ -d "${YOMU_DIR}/.git" ]]; then
  warn "Repository already exists at ${YOMU_DIR}. Skipping clone."
  info "To update, run: cd ${YOMU_DIR} && git pull"
else
  git clone "${REPO_URL}" "${YOMU_DIR}"
  chown -R "${TARGET_USER}:${TARGET_USER}" "${YOMU_DIR}"
  ok "Repository cloned to ${YOMU_DIR}"
fi

# ------------------------------------------------------------------------------
# 5. Create environment template if missing
# ------------------------------------------------------------------------------
if [[ ! -f "${YOMU_DIR}/.env" ]]; then
  if [[ -f "${YOMU_DIR}/.env.example" ]]; then
    info "Creating .env from .env.example..."
    cp "${YOMU_DIR}/.env.example" "${YOMU_DIR}/.env"
    chown "${TARGET_USER}:${TARGET_USER}" "${YOMU_DIR}/.env"
    chmod 600 "${YOMU_DIR}/.env"
    ok ".env created at ${YOMU_DIR}/.env"
  else
    warn ".env.example not found in repository. You will need to create .env manually."
  fi
else
  ok ".env already exists at ${YOMU_DIR}/.env"
fi

# ------------------------------------------------------------------------------
# 6. Final summary & next steps
# ------------------------------------------------------------------------------
echo ""
echo "============================================================================="
echo "  Yomu GCP Provisioning Complete"
echo "============================================================================="
echo ""
ok  "Docker & Docker Compose installed"
ok  "Repo cloned to ${YOMU_DIR}"
ok  "Directories & permissions set"
echo ""
echo "Next steps:"
echo "  1. Log out and log back in (or run 'newgrp docker') so the docker"
echo "     group membership takes effect."
echo ""
echo "  2. Edit your environment secrets:"
echo "     sudo nano ${YOMU_DIR}/.env"
echo ""
echo "  3. Start the shared infrastructure:"
echo "     cd ${YOMU_DIR}/docker-compose"
echo "     docker compose -f docker-compose.shared.yml up -d"
echo ""
echo "  4. Deploy an environment (choose one):"
echo "     ./scripts/deploy-staging.sh"
echo "     ./scripts/deploy-blue.sh"
echo "     ./scripts/deploy-green.sh"
echo ""
echo "  5. Check health: ./scripts/health-check.sh"
echo ""
echo "============================================================================="
