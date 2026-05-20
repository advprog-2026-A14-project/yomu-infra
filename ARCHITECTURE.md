# Yomu Platform — Architecture

**Platform**: Google Cloud Compute Engine (VPS)
**Domain**: [yomu.my.id](https://yomu.my.id)
**Deployment**: Blue-Green via Docker Compose + Traefik
**Environments**: Production (blue/green), Staging

---

## 1. System Overview

```mermaid
flowchart TB
    subgraph Internet["Internet"]
        User(("User"))
    end

    subgraph GCP["Google Cloud Platform — Compute Engine VPS"]
        subgraph DockerHost["Docker Host"]
            subgraph Shared["Shared Infrastructure"]
                Traefik["Traefik Reverse Proxy\n:80 :443"]
                PG[("PostgreSQL\n5432")]
                Redis[("Redis\n6379")]
                Prom[("Prometheus\n9090")]
                Graf[("Grafana\n3000")]
                Loki[("Loki\n3100")]
                Tempo[("Tempo\n3200 / 4317")]
                OTEL[("OTEL Collector\n4317 / 4318")]
                PGE[("postgres-exporter\n9187")]
                RE[("redis-exporter\n9121")]
            end

            subgraph ProdBG["Production — Blue/Green"]
                direction LR
                subgraph Blue["🔵 Blue (Active / Standby)"]
                    FB["frontend-blue"]
                    JB["java-blue"]
                    RB["rust-blue"]
                end
                subgraph Green["🟢 Green (Active / Standby)"]
                    FG["frontend-green"]
                    JG["java-green"]
                    RG["rust-green"]
                end
            end

            subgraph StagingEnv["Staging — Continuous"]
                FS["frontend-staging"]
                JS["java-staging"]
                RS["rust-staging"]
            end
        end
    end

    User -->|"yomu.my.id"| Traefik
    User -->|"staging.yomu.my.id"| Traefik
    User -->|"grafana.yomu.my.id"| Traefik
    User -->|"prom.yomu.my.id"| Traefik

    Traefik -->|"production.traffic"| Blue
    Traefik -->|"production.traffic"| Green
    Traefik -->|"staging.traffic"| StagingEnv

    JB <--> PG
    JG <--> PG
    JS <--> PG
    RB <--> PG
    RG <--> PG
    RS <--> PG

    RB <--> Redis
    RG <--> Redis
    RS <--> Redis

    FB --> JB
    FG --> JG
    FS --> JS

    JB --> RB
    JG --> RG
    JS --> RS

    JB -.->|"OTLP traces/metrics/logs"| OTEL
    JG -.->|"OTLP traces/metrics/logs"| OTEL
    JS -.->|"OTLP traces/metrics/logs"| OTEL
    RB -.->|"OTLP traces/metrics/logs"| OTEL
    RG -.->|"OTLP traces/metrics/logs"| OTEL
    RS -.->|"OTLP traces/metrics/logs"| OTEL

    OTEL -->|"traces"| Tempo
    OTEL -->|"logs"| Loki
    OTEL -->|"metrics (remote write)"| Prom

    Tempo -.->|"span metrics + service graphs\nremote write"| Prom
    Prom -->|"scrape"| Traefik
    Prom -->|"scrape"| JB & JG & JS
    Prom -->|"scrape"| RB & RG & RS
    Prom -->|"scrape"| FB & FG & FS
    Prom -->|"scrape"| PGE & RE

    Graf --> Prom
    Graf --> Loki
    Graf --> Tempo
```

### Components

| Component | Role | Docker Image | Internal Port |
|-----------|------|-------------|---------------|
| Traefik | Reverse proxy, TLS termination, routing | `traefik:v3.1` | :80, :443, :8080 (dashboard) |
| PostgreSQL | Relational DB (4 databases) | `postgres:18` | :5432 |
| Redis | Cache, session store, leaderboard | `redis:8-alpine` | :6379 |
| Prometheus | Metrics collection + alerting | `prom/prometheus:v2.53.0` | :9090 |
| Grafana | Metrics visualization + dashboards | `grafana/grafana:11.0.0` | :3000 |
| Loki | Log aggregation | `grafana/loki:3.0.0` | :3100 |
| Tempo | Distributed tracing storage + query | `grafana/tempo:2.5.0` | :3200 (HTTP), :4317 (OTLP gRPC) |
| OTEL Collector | Telemetry pipeline | `otel/opentelemetry-collector-contrib:0.104.0` | :4317, :4318, :8889 |
| postgres-exporter | PostgreSQL metrics → Prometheus | `prometheuscommunity/postgres-exporter:v0.15.0` | :9187 |
| redis-exporter | Redis metrics → Prometheus | `oliver006/redis_exporter:v1.58.0` | :9121 |

---

## 2. Network Architecture

```mermaid
flowchart LR
    subgraph Networks["🌐 Docker Networks"]
        subgraph Shared["yomu-shared-network"]
            direction TB
            S1["Traefik"]
            S2["PostgreSQL"]
            S3["Redis"]
            S4["Prometheus"]
            S5["Grafana"]
            S6["Loki"]
            S7["Tempo"]
            S8["OTEL Collector"]
            S9["Exporters"]
        end

        subgraph BlueNet["yomu-blue-network"]
            B1["frontend-blue"]
            B2["java-blue"]
            B3["rust-blue"]
        end

        subgraph GreenNet["yomu-green-network"]
            G1["frontend-green"]
            G2["java-green"]
            G3["rust-green"]
        end

        subgraph StagingNet["yomu-staging-network"]
            ST1["frontend-staging"]
            ST2["java-staging"]
            ST3["rust-staging"]
        end
    end

    Traefik --> Shared
    Traefik --> BlueNet
    Traefik --> GreenNet
    Traefik --> StagingNet

    B1 <--> B2 <--> B3
    G1 <--> G2 <--> G3
    ST1 <--> ST2 <--> ST3

    B1 <--> S1
    G1 <--> S1
    ST1 <--> S1

    B2 <--> S2 & S3
    G2 <--> S2 & S3
    ST2 <--> S2 & S3

    B3 <--> S2 & S3
    G3 <--> S2 & S3
    ST3 <--> S2 & S3
```

### Network Isolation Rules

| Network | Members | Traffic |
|---------|---------|---------|
| `yomu-shared-network` | All shared infra + all app services | Cross-service discovery, DB access, telemetry |
| `yomu-blue-network` | `frontend-blue`, `java-blue`, `rust-blue` + Traefik | Internal blue env communication |
| `yomu-green-network` | `frontend-green`, `java-green`, `rust-green` + Traefik | Internal green env communication |
| `yomu-staging-network` | `frontend-staging`, `java-staging`, `rust-staging` + Traefik | Internal staging communication |

**Key**: Blue and Green services on different networks cannot communicate directly with each other — they go through PostgreSQL, Redis, or Traefik on the shared network. This prevents accidental cross-talk during switches.

---

## 3. Blue-Green Deployment Pattern

```mermaid
sequenceDiagram
    actor Ops as Operations
    participant Blue as 🔵 Blue Environment
    participant Green as 🟢 Green Environment
    participant Traefik as Traefik Proxy
    participant DB as PostgreSQL + Redis
    participant User as Users

    Note over Blue,Green: Production starts with Blue active
    Note over User: All traffic → Blue
    User->>Traefik: yomu.my.id
    Traefik->>Blue: Route to Blue services

    Ops->>Green: Deploy new version
    Green->>DB: Connect to shared DBs
    Note over Green: Health checks pass
    Ops->>Green: Run k6 smoke tests

    Ops->>Traefik: Switch traffic to Green
    Note over User: Traffic now → Green
    User->>Traefik: yomu.my.id
    Traefik->>Green: Route to Green services

    Note over Blue: Blue remains running<br/>(ready for rollback)
    Ops->>Blue: Observe for 1 hour

    alt Rollback needed
        Ops->>Traefik: Switch traffic back to Blue
        Traefik->>Blue: Route to Blue services
        Note over User: Traffic → Blue again
    end

    Note over Blue: After confirmed stability<br/>Blue can be scaled down / redeployed
```

### State Machine

```mermaid
stateDiagram-v2
    [*] --> BlueActive: Initial Deploy
    BlueActive --> GreenDeploying: Deploy Green
    GreenDeploying --> SmokeTests: Deploy OK
    SmokeTests --> GreenActive: Switch Traffic
    SmokeTests --> BlueActive: Deploy Failed (abort)
    GreenActive --> BlueActive: Rollback
    BlueActive --> GreenDeploying: Deploy Green (next cycle)
    GreenActive --> GreenDeploying: Deploy new Green
    GreenActive --> BlueDeploying: Deploy Blue (if needed)
    BlueDeploying --> SmokeTests: Deploy OK
    SmokeTests --> BlueActive: Switch Traffic
    BlueDeploying --> GreenActive: Deploy Failed
    BlueActive --> [*]: Stop both (maintenance)
```

### Router Switching Mechanism

Traefik watches the `/etc/traefik/dynamic/` directory via the **file provider** with `watch: true`. To switch traffic between blue and green:

```bash
# Switch to Green
cp traefik/dynamic/green-active.yml traefik/dynamic/routing.yml
docker kill --signal=HUP traefik
```

Only `routing.yml` is loaded by Traefik at runtime. The switch is instantaneous (no container restart). The inactive environment stays running — if the new environment fails health checks, a single `rollback.sh` command restores traffic to the previous environment.

---

## 4. Request Routing

### Production Routing Matrix

| Host / Path | Router | Service | Environment |
|-------------|--------|---------|-------------|
| `yomu.my.id` / `/*` | `frontend-router` | Frontend (Blue or Green) | Active slot |
| `yomu.my.id/api/java/*` | `java-router` | Java Backend (Blue or Green) | Active slot (strip `/api/java`) |
| `yomu.my.id/api/rust/*` | `rust-router` | Rust Backend (Blue or Green) | Active slot (strip `/api/rust`) |
| `staging.yomu.my.id` / `/*` | `staging-frontend-router` | `frontend-staging` | Staging |
| `staging.yomu.my.id/api/java/*` | `staging-java-router` | `java-staging` | Staging (strip `/api/java`) |
| `staging.yomu.my.id/api/rust/*` | `staging-rust-router` | `rust-staging` | Staging (strip `/api/rust`) |
| `yomu.my.id/grafana/*` | `grafana-router` | Grafana | Infrastructure |
| `yomu.my.id/prometheus/*` | `prometheus-router` | Prometheus | Infrastructure |

### Data Flow: Login Request

```mermaid
sequenceDiagram
    actor User
    participant Traefik as Traefik (:80)
    participant FE as frontend-[blue|green]
    participant Java as java-[blue|green]
    participant PG[("PostgreSQL\nyomu_db")]
    participant Rust as rust-[blue|green]
    participant Redis[("Redis\nSessions")]

    User->>Traefik: POST /api/java/auth/login
    Traefik->>FE: Route to frontend (PathPrefix(/))
    FE->>Java: Proxy to java-[slot]:8080
    Java->>PG: Query user credentials
    PG-->>Java: User data
    Java->>Redis: Store session token
    Java-->>FE: {access_token, user}
    FE-->>Traefik: Set-Cookie: yomu_access_token=...
    Traefik-->>User: HTTP 200 + cookie

    Note over Java,Redis: Java creates outbox event for Rust user sync

    User->>Traefik: GET /api/rust/leaderboard
    Traefik->>FE: Route to frontend
    FE->>Java: Verify JWT via /api/java/auth/me
    Java->>Redis: Validate session
    Java-->>FE: {user}
    FE->>Rust: Proxy with X-Internal-Api-Key header
    Rust->>PG: Query leaderboard scores
    PG-->>Rust: Scores
    Rust->>Redis: Cache leaderboard (TTL 60s)
    Rust-->>FE: {ranks}
    FE-->>User: JSON response
```

---

## 5. Database Architecture

```mermaid
erDiagram
    PostgreSQL {
        database yomu_db "Production Java"
        database yomu_engine "Production Rust"
        database yomu_db_staging "Staging Java"
        database yomu_engine_staging "Staging Rust"
    }

    yomu_db ||--o{ java-blue : "uses"
    yomu_db ||--o{ java-green : "uses"
    yomu_engine ||--o{ rust-blue : "uses"
    yomu_engine ||--o{ rust-green : "uses"

    yomu_db_staging ||--o{ java-staging : "uses"
    yomu_engine_staging ||--o{ rust-staging : "uses"

    yomu_db ||--o{ Users : "auth/users"
    yomu_db ||--o{ Articles : "article content"
    yomu_db ||--o{ Quizzes : "quiz content"
    yomu_db ||--o{ Outbox : "sync events to Rust"

    yomu_engine ||--o{ ShadowUsers : "synced from Java"
    yomu_engine ||--o{ Clans : "clan data"
    yomu_engine ||--o{ Leaderboards : "scores"
    yomu_engine ||--o{ Missions : "gamification"
```

### Database Initialization

On first PostgreSQL start, `scripts/init-databases.sql` is mounted to `/docker-entrypoint-initdb.d/02-init-databases.sql` and executed automatically by the official PostgreSQL Docker image. The script is **idempotent** (uses `IF NOT EXISTS` guards) so it can safely re-run on container restart.

| Database | Created By | Used By | Purpose |
|----------|-----------|---------|---------|
| `yomu_db` | `${POSTGRES_DB}` env var | `java-blue`, `java-green` | Auth, users, articles, quizzes, outbox |
| `yomu_engine` | `init-databases.sql` | `rust-blue`, `rust-green` | Clans, scores, achievements, shadow users |
| `yomu_db_staging` | `init-databases.sql` | `java-staging` | Staging auth/users/articles |
| `yomu_engine_staging` | `init-databases.sql` | `rust-staging` | Staging clans/leaderboards |

---

## 6. Observability Stack (Full Telemetry)

### Metrics Pipeline

```mermaid
flowchart LR
    subgraph Apps["Application Services"]
        JavaApp["Spring Boot\n/actuator/prometheus"]
        RustApp["Axum\n/metrics"]
        NextApp["Next.js\n/api/metrics"]
        PGE2["postgres-exporter"]
        RE2["redis-exporter"]
    end

    subgraph Prometheus["Prometheus"]
        PromScrape["Scrape Manager\n(every 15s)"]
        PromRules["Alert Rules\n(7 rules)"]
        PromTSDB["TSDB Storage"]
    end

    subgraph Visualization["Visualization"]
        Grafana2["Grafana"]
        sub1["Blue-Green Overview"]
        sub2["Service Health"]
        sub3["Environment Comparison"]
    end

    JavaApp -->|"job: java-{slot}"| PromScrape
    RustApp -->|"job: rust-{slot}"| PromScrape
    NextApp -->|"job: frontend-{slot}"| PromScrape
    PGE2 -->|"job: postgres"| PromScrape
    RE2 -->|"job: redis"| PromScrape

    PromScrape --> PromTSDB
    PromRules --> PromTSDB
    PromTSDB --> Grafana2

    Grafana2 --> sub1 & sub2 & sub3
```

### Traces Pipeline

```mermaid
flowchart LR
    subgraph TraceSources["Trace Sources"]
        JT["Java OTEL Agent"]
        RT["Rust app (OTLP)"]
        NT["Next.js (OTLP)"]
    end

    OTEL2["OTEL Collector\n:4317"]
    TempoStorage["Tempo\nTrace Storage"]
    TraceQuery["Grafana\nTraceQL"]

    JT -->|"OTLP/gRPC"| OTEL2
    RT -->|"OTLP/gRPC"| OTEL2
    NT -->|"OTLP/HTTP"| OTEL2

    OTEL2 -->|"OTLP/gRPC"| TempoStorage
    TraceQuery -->|"HTTP :3200"| TempoStorage

    TempoStorage -.->|"span metrics + service graph\nprometheus remote write"| Prom["Prometheus"]
```

### Logs Pipeline

```mermaid
flowchart LR
    JavaApp["Java App\n(OTLP Logs)"]
    RustApp["Rust App\n(OTLP Logs)"]
    OTEL3["OTEL Collector\n:4318"]
    LokiStorage["Loki\nLog Storage"]
    LogQuery["Grafana\nLogQL"]

    JavaApp -->|"OTLP/HTTP"| OTEL3
    RustApp -->|"OTLP/HTTP"| OTEL3
    OTEL3 -->|"HTTP Push"| LokiStorage
    LogQuery -->|"HTTP :3100"| LokiStorage
```

### Three Pillars Coverage

| Signal | Technology | Endpoint | Retention |
|--------|-----------|----------|-----------|
| **Metrics** | Prometheus (+ OTEL remote write) | `prometheus:9090` | Unlimited (local storage) |
| **Logs** | OTEL Collector → Loki | `loki:3100` | 7 days |
| **Traces** | OTEL Collector → Tempo | `tempo:3200` (query), `tempo:4317` (ingest) | 7 days |
| **Dashboards** | Grafana (auto-provisioned) | `grafana:3000` | Persistent (volume) |
| **Alerts** | Prometheus Alertmanager (rules defined) | Eval every 15s | — |

---

## 7. Domain and TLS Architecture

```mermaid
flowchart TB
    User(("Internet User"))
    Cloudflare["Cloudflare DNS\nyomu.my.id"]

    subgraph GCP["GCP Compute Engine"]
        subgraph VPS["VPS (Ubuntu)"]
            TraefikTLS["Traefik\nTLS Termination"]

            subgraph Services["Internal Services"]
                Prod["Production Apps\nBlue / Green"]
                Stage["Staging Apps"]
                Monitor["Monitoring Stack"]
            end
        end
    end

    User -->|"A record → VPS IP"| Cloudflare
    Cloudflare -->|":443 HTTPS"| TraefikTLS

    TraefikTLS -->|"yomu.my.id\nHost header"| Prod
    TraefikTLS -->|"staging.yomu.my.id\nHost header"| Stage
    TraefikTLS -->|"grafana.yomu.my.id\nHost header"| Monitor
    TraefikTLS -->|"prom.yomu.my.id\nHost header"| Monitor

    TraefikTLS -->|":3001 TCP\nno Host needed"| TraefikTLS
```

### DNS Records (yomu.my.id)

| Record | Type | Target | Purpose |
|--------|------|--------|---------|
| `yomu.my.id` | A | VPS Public IP | Production traffic |
| `staging.yomu.my.id` | A | VPS Public IP | Staging traffic |
| `grafana.yomu.my.id` | A | VPS Public IP | Grafana dashboard |
| `prom.yomu.my.id` | A | VPS Public IP | Prometheus (optional, restrict access) |

### TLS Options

1. **Let's Encrypt via Traefik** (recommended):
   Uncomment the `certificatesResolvers` block in `traefik/traefik.yml`. Traefik automatically requests and renews TLS certificates.

2. **Cloudflare Origin Certificates** (alternative):
   Download Cloudflare origin cert, mount to `/etc/traefik/certs/`, and configure TLS in dynamic config.

3. **Self-signed** (staging only):
   Generate with `openssl` and mount to traefik certificates directory.

---

## 8. Alerting Rules

| Alert | Severity | Trigger | Action |
|-------|----------|---------|--------|
| **ServiceDown** | 🔴 Critical | `up == 0` for 1m | Check `docker ps`, review `docker compose logs` |
| **BlueGreenOutOfSync** | 🔴 Critical | Both blue AND green have zero healthy services | Platform-wide outage — investigate infra |
| **DatabaseDown** | 🔴 Critical | `pg_up == 0` | Check PostgreSQL container health |
| **HighErrorRate** | 🟡 Warning | `rate(traefik_service_requests_total{code=~"5.."}[5m]) > 0.1` | Review application logs |
| **HighLatency** | 🟡 Warning | Traefik p95 latency > 2s for 5m | Check DB performance, JVM heap |
| **JavaHeapHigh** | 🟡 Warning | JVM heap > 85% for 5m | Restart Java service or increase memory limit |
| **DiskSpaceLow** | 🟡 Warning | Disk < 10% (if node-exporter present) | Clean logs, extend disk |

---

## 9. Directory Structure

```
yomu-deployment/
├── docker-compose/
│   ├── docker-compose.shared.yml         # Traefik, PostgreSQL, Redis, Prometheus, Grafana,
│   │                                      # Loki, Tempo, OTEL Collector, Exporters
│   ├── docker-compose.blue.yml            # frontend-blue, java-blue, rust-blue
│   ├── docker-compose.green.yml           # frontend-green, java-green, rust-green
│   ├── docker-compose.staging.yml        # frontend-staging, java-staging, rust-staging
│   └── .env.example                       # Secrets template
├── traefik/
│   ├── traefik.yml                        # Static config (entrypoints, TLS, Docker provider, file provider, metrics)
│   └── dynamic/
│       ├── blue-active.yml              # Production routing → Blue
│       ├── green-active.yml             # Production routing → Green
│       ├── routing.yml                   # Active routing (symlink/copy of blue or green)
│       └── staging.yml                   # Always-on staging routing
├── scripts/
│   ├── deploy-blue.sh                     # Deploy to Blue, wait for health
│   ├── deploy-green.sh                    # Deploy to Green, wait for health
│   ├── deploy-staging.sh                 # Deploy to Staging, wait for health
│   ├── switch-traffic.sh <blue|green>   # Switch Traefik routing + smoke test
│   ├── rollback.sh                       # Detect active, switch to other
│   ├── health-check.sh                    # Full platform health check
│   ├── full-deploy.sh                    # End-to-end: deploy → health → smoke → switch
│   └── init-databases.sql               # Create yomu_engine, yomu_db_staging, yomu_engine_staging
├── prometheus/
│   ├── prometheus.yml                     # 12 scrape jobs (6 prod + 3 staging + 2 exporter + traefik + prometheus)
│   └── rules/
│       └── alerts.yml                     # 7 alert rules
├── grafana/
│   ├── dashboards/
│   │   ├── yomu-blue-green-overview.json
│   │   ├── yomu-service-health.json
│   │   └── yomu-environment-comparison.json
│   └── provisioning/
│       ├── dashboards/dashboards.yml
│       └── datasources/datasources.yml
├── loki/loki-config.yml                   # 7-day retention, filesystem storage
├── tempo/tempo-config.yml                # OTLP ingest, local storage, span metrics
├── otel/otel-collector-config.yml        # 3 pipelines: traces→Tempo, metrics→Prometheus, logs→Loki
└── k6/                                    # Load test suites
    ├── smoke/, load/, stress/, spike/, soak/
    └── scripts/
```

---

## 10. Environments Summary

| Aspect | Production | Staging |
|--------|-----------|---------|
| **Strategy** | Blue-Green (one active at a time) | Always-on (no switching) |
| **DB** | `yomu_db`, `yomu_engine` | `yomu_db_staging`, `yomu_engine_staging` |
| **Redis** | Shared | Shared, with `staging_` prefix |
| **Domain** | `yomu.my.id` | `staging.yomu.my.id` |
| **Images** | `yomu-*:latest` (or specific tag) | `yomu-*:staging` |
| **Blue slot** | `frontend-blue`, `java-blue`, `rust-blue` | — |
| **Green slot** | `frontend-green`, `java-green`, `rust-green` | — |
| **Staging slot** | — | `frontend-staging`, `java-staging`, `rust-staging` |
| **Switch** | File-based Traefik HUP | No switch needed |
| **Rollback** | Instant: `rollback.sh` (switches to other slot) | Re-deploy from image |
| **Grafana dashboard** | Blue-Green Overview (+ env comparison) | Viewed via Environment Comparison dashboard |
