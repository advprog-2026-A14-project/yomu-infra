# Yomu Docker Swarm Migration — Post-Mortem

**Date:** 2026-05-21
**Author:** HeraldoArman
**Status:** Production and staging fully operational with TLS and rolling updates

---

## 1. Objective

Migrate from blue/green Docker Compose static deployment to Docker Swarm with rolling updates. Keep Traefik as reverse proxy. Ensure production and staging environments are reachable via HTTPS with valid Let's Encrypt certificates.

---

## 2. Issues Encountered

### 2.1 Traefik Docker API Version Hardcoded (Critical)

**Symptom:**
```
Error response from daemon: client version 1.24 is too old. Minimum supported API version is 1.40
```

**Root Cause:** Traefik v3.1.x hardcoded Docker API v1.24 in its internal Docker client, but Docker Engine on the VPS enforces minimum v1.40.

**Fix:** Upgrade Traefik to v3.6 which includes Docker API auto-negotiation via `WithAPIVersionNegotiation()`.

**File:** `yomu-deployment/docker-compose/docker-compose.swarm.yml`
```yaml
image: traefik:v3.6
```

---

### 2.2 Traefik "service yomu-traefik error: port is missing"

**Symptom:** Repeating log error every 5 seconds:
```
service "yomu-traefik" error: port is missing
```

**Root Cause:** Traefik's Swarm provider auto-discovers the `yomu_traefik` service itself because deploy labels were present on the service. The label `traefik.http.routers.traefik.service=api@internal` still triggered Swarm provider discovery which expected a backend port.

**Fix:** Remove all Traefik labels from the Traefik service definition in the compose file. Traefik dashboard is accessible via `api@internal` without Swarm provider discovery.

**File:** `yomu-deployment/docker-compose/docker-compose.swarm.yml`
```yaml
# Removed from traefik service deploy.labels:
# - "traefik.enable=true"
# - "traefik.http.routers.traefik.rule=Host(`monitoring.yomu.my.id`)"
# - "traefik.http.routers.traefik.service=api@internal"
# - "traefik.http.routers.traefik.tls.certresolver=letsencrypt"
```

---

### 2.3 Rust Staging Keep Restarting (Exit 137 + Healthcheck Failure)

**Symptom:**
```
task: non-zero exit (1): dockerexec: unhealthy container
```

**Root Causes (multiple):**
1. **Healthcheck used `wget`** — the Rust Alpine image does not contain `wget`, only `curl`.
2. **`docker service update --health-cmd`** wraps commands in `CMD-SHELL` automatically. Passing `CMD-SHELL,curl ...` created a double-wrapped `CMD-SHELL,CMD-SHELL,curl ...` that failed with "command not found".
3. **512MB memory limit** was occasionally too low for startup; increased to 1GB.
4. **Swarm rolling update start-first** caused healthcheck failures because the old unhealthy task blocked the new task from being promoted.

**Fix:**
- Change healthcheck from `wget` to `curl`
- Use `docker service create` with plain `--health-cmd 'curl -f http://localhost:8080/health'` (let Swarm wrap in CMD-SHELL)
- Increase memory limit from `512M` to `1G`
- Increase `start_period` from `30s` to `120s`

**File:** `yomu-deployment/docker-compose/docker-compose.swarm.yml`
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
  start_period: 120s
resources:
  limits:
    memory: 1G
```

---

### 2.4 Java CORS Error: "ERR_CERT_AUTHORITY_INVALID" / CORS Error

**Symptom:** Browser blocked login request to `https://java.yomu.my.id/api/v1/auth/login` with CORS error.

**Root Cause:** The Java Spring Boot backend's `cors.allowed-origins` property defaulted to `http://localhost:3000,http://localhost:5173` because the env var `CORS_ALLOWED_ORIGINS` was not set in the VPS `.env` file.

**Fix:** Add `CORS_ALLOWED_ORIGINS` and `CORS_ALLOW_CREDENTIALS` to `.env`, then redeploy Java services.

```bash
# Added to /opt/yomu/.env
CORS_ALLOWED_ORIGINS=https://yomu.my.id,https://staging.yomu.my.id
CORS_ALLOW_CREDENTIALS=true
```

**Verification:**
```bash
curl -I -X OPTIONS -H 'Origin: https://yomu.my.id' \
  -H 'Access-Control-Request-Method: POST' \
  https://java.yomu.my.id/api/v1/auth/login
# Returns: access-control-allow-origin: https://yomu.my.id
```

---

### 2.5 Old Blue/Green File Provider Routes Causing 502 Bad Gateway

**Symptom:** `https://yomu.my.id/` and `https://java.yomu.my.id/` returned `502 Bad Gateway` while staging URLs worked fine.

**Root Cause:** Leftover file provider configs in `/opt/yomu/traefik/dynamic/`:
- `blue-active.yml`
- `green-active.yml`
- `routing.yml`

These pointed to non-existent containers (`java-blue:8080`, `frontend-blue:3000`) and overrode the Swarm provider routes.

**Fix:** Delete all old file provider configs from `/opt/yomu/traefik/dynamic/` on the VPS.

```bash
rm -f /opt/yomu/traefik/dynamic/blue-active.yml
rm -f /opt/yomu/traefik/dynamic/green-active.yml
rm -f /opt/yomu/traefik/dynamic/routing.yml
rm -f /opt/yomu/traefik/dynamic/routing-swarm.yml
```

---

### 2.6 Tempo Port Conflict with Otel-Collector

**Symptom:** During `docker stack deploy`:
```
port '4317' is already in use by service 'yomu_otel-collector'
```

**Root Cause:** Both `tempo` and `otel-collector` services mapped port `4317` (gRPC OTLP ingestion).

**Fix:** Remove port mappings from `tempo` service in compose file. Tempo only needs to expose its query API (3200), not its ingestion endpoint, since ingestion flows through `otel-collector`.

**File:** `yomu-deployment/docker-compose/docker-compose.swarm.yml`
```yaml
# Removed ports from tempo service
- "127.0.0.1:4317:4317"  # REMOVED (conflict)
```

---

### 2.7 Missing PostgreSQL Databases

**Symptom:** Java backend crashed with:
```
FATAL: database "yomu_db" does not exist
```

**Root Cause:** After removing old blue/green PostgreSQL containers, databases were lost because volume names changed.

**Fix:** Manually create required databases via `psql`:
```sql
CREATE DATABASE yomu_db;
CREATE DATABASE yomu_engine;
CREATE DATABASE yomu_engine_staging;
```

---

## 3. Final Architecture

```
Internet
   |
Traefik v3.6 (Swarm provider)
   |-- yomu.my.id → frontend (Next.js)
   |-- java.yomu.my.id → java (Spring Boot)
   |-- rust.yomu.my.id → rust (Axum)
   |-- monitoring.yomu.my.id → Grafana
   |
   |-- staging.yomu.my.id → frontend-staging
   |-- java-staging.yomu.my.id → java-staging
   |-- rust-staging.yomu.my.id → rust-staging
   |
PostgreSQL (prod)    PostgreSQL (staging)    Redis (prod)    Redis (staging)
```

---

## 4. Service Status Summary

| Service | Status | Notes |
|---------|--------|-------|
| Traefik | 1/1 | v3.6, Let's Encrypt TLS OK |
| Frontend | 1/1 | HTTPS 200 |
| Java | 1/1 | HTTPS 200, CORS OK |
| Rust | 1/1 | HTTPS 200 |
| Grafana | 1/1 | HTTPS 200 via monitoring.yomu.my.id |
| Frontend Staging | 1/1 | HTTPS 200 |
| Java Staging | 1/1 | HTTPS 200 |
| Rust Staging | 1/1 | HTTPS 200 |
| Postgres | 1/1 | DBs created manually |
| Redis | 1/1 | OK |
| Prometheus | 1/1 | OK |
| Loki | 0/1 | Down (no impact on apps) |
| Tempo | 1/1 | OK |
| Otel-Collector | 1/1 | OK |
| CAdvisor | 1/1 | OK |
| Node Exporter | 1/1 | OK |

---

## 5. Key Configuration Changes

### VPS Environment File (`/opt/yomu/.env`)
- Added: `CORS_ALLOWED_ORIGINS` and `CORS_ALLOW_CREDENTIALS`
- Verified: `POSTGRES_PASSWORD`, `JWT_SECRET`, `INTERNAL_API_KEY` all correct

### Traefik Config (`traefik.swarm.yml`)
- Provider: `swarm` + `file` (file is empty now)
- TLS: `tlsChallenge` with Let's Encrypt
- No self-discovery labels on Traefik service

### Compose File (`docker-compose.swarm.yml`)
- Traefik: removed self-discovery labels
- Rust (prod + staging): `curl` healthcheck, memory 1G, start_period 120s
- Tempo: removed conflicting port 4317
- Added `dynamic/` directory bind mount for Traefik file provider

---

## 6. Verification Commands

```bash
# Check all services
docker service ls

# Check TLS cert for a domain
echo | openssl s_client -connect yomu.my.id:443 -servername yomu.my.id | grep -E 'subject|issuer'

# Verify CORS
curl -sI -X OPTIONS -H 'Origin: https://yomu.my.id' \
  -H 'Access-Control-Request-Method: POST' \
  https://java.yomu.my.id/api/v1/auth/login | grep access-control

# Check Traefik logs
docker service logs yomu_traefik --tail 20 --raw | grep -v 'grafana'
```

---

## 7. Lessons Learned

1. **File provider configs persist** — Remove old routing configs when switching from file-provider to Swarm-provider. They will still be loaded even if compose file no longer references them.
2. **Docker service update healthcheck is tricky** — `docker service update --health-cmd` automatically wraps the command in `CMD-SHELL`. Do NOT pass `CMD-SHELL` prefix manually.
3. **Traefik v3.1 vs v3.6** — Docker API version mismatch is fatal for Swarm mode. Always match Traefik version to Docker Engine requirements.
4. **.env file is critical for CORS** — Spring Boot defaults to `localhost` for CORS origins if env var is absent.
5. **Port conflicts cause partial deploy failures** — Even if one service fails, other services may still deploy. Check full stack status after every deploy.

---

## 8. Next Recommended Steps

1. Commit the final compose file changes
2. Ensure the CI/CD workflow loads `.env` before deploy
3. Consider configuring Grafana dashboards for Swarm (remove blue/green references)
4. Monitor memory usage of Java/Rust services over time
5. Remove remaining `docker-compose.yml` files that reference old blue/green architecture
