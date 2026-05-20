# Yomu Infrastructure

Infrastructure-as-Code for the Yomu observability stack on Google Cloud VPS.

## Stack

| Tool | Purpose | Port |
|------|---------|------|
| Traefik | Reverse proxy / load balancer | 80, 443, 3001 |
| Prometheus | Metrics collection | 9090 |
| Grafana | Metrics visualization | 3001 |
| Loki | Log aggregation | 3100 |
| Tempo | Distributed tracing | 4317 (OTLP) |
| OTEL Collector | Trace/log/metrics pipeline | 4317, 4318 |
| K6 | Load testing | CLI |

## Structure

```
docker-compose/   # Compose fragments (base, staging, production, overrides)
traefik/          # Reverse proxy config (dynamic routes, middleware, certs)
prometheus/       # Prometheus config, scrape rules, alert rules
grafana/          # Dashboard JSON, datasources, provisioning
loki/             # Log aggregation config
tempo/            # Trace storage config
otel/             # OpenTelemetry collector config
scripts/          # Deploy, rollback, switch, backup scripts
monitoring/       # Screenshots, reports, benchmarks from test runs
k6/               # Load test suites (smoke, load, stress, spike, soak)
.github/workflows/# CI/CD pipelines
```

## Deploy

```bash
# Blue-green deployment
./scripts/deploy-blue.sh
./scripts/switch-traffic.sh

# Rollback
./scripts/rollback.sh
```

## Observability

- **Grafana**: `http://your-vps:3001` (admin/admin)
- **Prometheus**: `http://your-vps:9090`
- **Loki**: `http://your-vps:3100`
- **Tempo**: `http://your-vps:4317` (OTLP gRPC)
- **Traefik Dashboard**: `http://your-vps:3001/dashboard/`

## License

MIT OR Apache-2.0
