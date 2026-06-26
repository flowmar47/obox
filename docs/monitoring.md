# Monitoring

obox includes a Prometheus + Grafana monitoring stack for observability across host resources, containers, service health, and GPU utilization.

## Stack

| Component | Purpose | Internal Port |
|-----------|---------|---------------|
| **Prometheus** | Metrics collection and storage (30-day retention) | 9090 |
| **Grafana** | Dashboards and visualization | 3000 |
| **node-exporter** | Host CPU, memory, disk, network | 9100 |
| **cAdvisor** | Per-container resource usage | 8080 |
| **blackbox-exporter** | HTTP uptime probes | 9115 |
| **dcgm-exporter** | NVIDIA GPU metrics (GPU mode only) | 9400 |

## Access

### Production (via Caddy)

| Service | URL | Auth |
|---------|-----|------|
| Grafana | `https://your-domain/grafana` | Admin credentials from `.env` |
| Prometheus | Internal only | Not exposed publicly |

### Development

| Service | URL |
|---------|-----|
| Grafana | http://localhost:3001 |
| Prometheus | http://localhost:9090 |

Default Grafana login: `admin` / value of `GRAFANA_ADMIN_PASSWORD` in `.env`.

## Pre-built Dashboard

The **obox Overview** dashboard is auto-provisioned on startup. It includes:

- **Service Health** — HTTP probe status for WebUI, LiteLLM, Ollama, Prometheus, Grafana
- **Host CPU / Memory** — system-wide utilization
- **Container CPU / Memory** — per-service breakdown for all obox containers
- **Disk Usage** — root filesystem gauge with warning thresholds
- **Network I/O** — receive/transmit rates
- **GPU Utilization / Memory** — NVIDIA metrics (visible when GPU mode is enabled)
- **HTTP Probe Latency** — response time for each probed endpoint

## Configuration

### Environment Variables

```env
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=<strong-password>
GRAFANA_ROOT_URL=https://llm.example.com/grafana/
```

Set `GRAFANA_ROOT_URL` to match your public URL scheme (`https://` in production).

### Prometheus Scrape Targets

Configured in `config/prometheus/prometheus.yml`:

- `node-exporter` — host metrics
- `cadvisor` — container metrics
- `litellm` — API request metrics at `/metrics`
- `blackbox-http` — uptime probes for core services
- `nvidia-gpu` — GPU metrics (target down on CPU-only hosts)

### Adding Custom Dashboards

Place JSON dashboard files in `config/grafana/dashboards/`. They are auto-loaded via provisioning.

To import community dashboards in Grafana:

1. Open Grafana → Dashboards → Import
2. Recommended IDs:
   - **1860** — Node Exporter Full
   - **14282** — Docker cAdvisor

### Adding Alerts (Optional)

Prometheus supports alerting rules. To add them:

1. Create `config/prometheus/alerts.yml`
2. Add a `rule_files` entry in `prometheus.yml`
3. Optionally deploy Alertmanager for notifications

Example alert rule:

```yaml
groups:
  - name: obox
    rules:
      - alert: ServiceDown
        expr: probe_success{job="blackbox-http"} == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Service {{ $labels.instance }} is down"
```

## GPU Monitoring

Enable GPU mode to activate `dcgm-exporter`:

```bash
OBOX_GPU=true ./scripts/setup.sh
```

The obox Overview dashboard includes GPU utilization and memory panels. Metrics use NVIDIA DCGM (`DCGM_FI_DEV_GPU_UTIL`, `DCGM_FI_DEV_FB_USED`, etc.).

Verify GPU metrics are flowing:

```bash
docker exec obox-prometheus wget -qO- http://dcgm-exporter:9400/metrics | head
```

## Security

- **Prometheus is not exposed** through Caddy — accessible only on the internal Docker network
- **Grafana** is exposed at `/grafana` — protect with a strong admin password
- In production, restrict Grafana access to internal IPs or VPN (see [security.md](security.md))
- cAdvisor runs with `privileged: true` for container metrics — required for Docker monitoring

## Troubleshooting

### Grafana shows "No data"

1. Check Prometheus is healthy: `docker compose logs prometheus`
2. Verify scrape targets: Prometheus UI → Status → Targets (dev: http://localhost:9090/targets)
3. Ensure exporters are running: `./scripts/healthcheck.sh`

### Grafana login redirect loop

Set `GRAFANA_ROOT_URL` to match your actual access URL including `/grafana/` suffix:

```env
GRAFANA_ROOT_URL=https://llm.example.com/grafana/
```

### GPU panels empty

- Confirm GPU mode: `OBOX_GPU=true ./scripts/setup.sh`
- Check dcgm-exporter: `docker logs obox-dcgm-exporter`
- Verify NVIDIA toolkit: `docker exec obox-ollama nvidia-smi`

### High disk usage from Prometheus

Default retention is 30 days. Reduce in `docker-compose.yml`:

```yaml
- "--storage.tsdb.retention.time=7d"
```

## Useful Queries

```promql
# Ollama container memory
container_memory_usage_bytes{container_label_com_docker_compose_service="ollama"}

# Service uptime
probe_success{job="blackbox-http"}

# Host memory pressure
(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100

# GPU utilization
DCGM_FI_DEV_GPU_UTIL
```
