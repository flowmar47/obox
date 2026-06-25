# Architecture

obox is a Docker Compose stack that provides remote access to locally-hosted large language models.

## Components

### Ollama

The inference engine. Ollama downloads, loads, and serves open-source LLM weights. It exposes a native API on port 11434 and is not directly exposed to the internet — all external traffic routes through Caddy or the dev-mode port mappings.

**Data:** Model weights and configuration persist in the `ollama_data` Docker volume.

### Open WebUI

A feature-rich web interface for chatting with models, managing conversations, and configuring RAG pipelines. It connects to Ollama for inference and LiteLLM for OpenAI-compatible model routing.

**Data:** User accounts, chat history, and uploads persist in the `webui_data` volume.

### LiteLLM

An API gateway that translates OpenAI-compatible requests (`/v1/chat/completions`, `/v1/models`) into Ollama API calls. This lets you use the OpenAI SDK, LangChain, or any tool that speaks the OpenAI API format against your local models.

Model routing is configured in `config/litellm/config.yaml`. The catch-all `*` entry passes any model name directly to Ollama, so you can use models without adding them to the config file.

### Portainer

A web UI for managing Docker containers, images, volumes, and networks. Useful for monitoring resource usage, viewing logs, and restarting services without SSH access.

On first visit, you create an admin account. In production, restrict access to `/portainer` via firewall rules or Caddy authentication.

### Prometheus

Metrics collection engine. Scrapes exporters every 15 seconds and stores time-series data with 30-day retention. Runs on the internal network only — not exposed through Caddy.

**Data:** Metrics persist in the `prometheus_data` volume.

### Grafana

Visualization layer for Prometheus metrics. Ships with a pre-provisioned **obox Overview** dashboard covering host resources, container usage, service health, and GPU metrics.

**Data:** Dashboard customizations and settings persist in the `grafana_data` volume.

### Exporters

| Exporter | Metrics |
|----------|---------|
| node-exporter | Host CPU, memory, disk, network |
| cAdvisor | Per-container CPU, memory, I/O |
| blackbox-exporter | HTTP uptime and latency probes |
| dcgm-exporter | NVIDIA GPU utilization and memory (GPU mode) |

### Caddy

Reverse proxy and TLS terminator. In production with a real domain, Caddy automatically provisions Let's Encrypt certificates. Routes:

| Path | Target | Purpose |
|------|--------|---------|
| `/` | Open WebUI :8080 | Chat interface |
| `/v1/*` | LiteLLM :4000 | OpenAI-compatible API |
| `/portainer/*` | Portainer :9000 | Container management |
| `/grafana/*` | Grafana :3000 | Monitoring dashboards |
| `/health` | Caddy (static) | Health check |

## Network

All services communicate on the `obox` bridge network. Only Caddy (ports 80/443) or dev-mode direct ports are exposed to the host.

```
Internet / Client
       │
       ▼
   ┌───────┐
   │ Caddy │ :80, :443
   └───┬───┘
       │ obox network
   ┌───┴────────────────────────────┐
   │                                │
   ▼          ▼          ▼          ▼
WebUI     LiteLLM   Portainer    Ollama
:8080      :4000      :9000     :11434
   │          │                    ▲
   └────┬─────┘                    │
        ▼                          │
     Ollama ───────────────────────┘

   Monitoring (internal network)
   ┌──────────────────────────────────┐
   │ Prometheus ◄── node-exporter     │
   │     ▲      ◄── cAdvisor          │
   │     │      ◄── blackbox-exporter │
   │     │      ◄── litellm /metrics  │
   │     │      ◄── dcgm-exporter     │
   │     ▼                            │
   │  Grafana ──► /grafana (via Caddy)│
   └──────────────────────────────────┘
```

## Data Persistence

| Volume | Contents |
|--------|----------|
| `ollama_data` | Downloaded model weights |
| `webui_data` | Chat history, user data, uploads |
| `portainer_data` | Portainer settings and state |
| `prometheus_data` | Collected metrics (30-day retention) |
| `grafana_data` | Dashboards and Grafana settings |
| `caddy_data` | TLS certificates |
| `caddy_config` | Caddy runtime config |

## Compose Overrides

The base `docker-compose.yml` defines the full stack. Override files layer on additional behavior:

- **`docker-compose.gpu.yml`** — adds NVIDIA GPU device reservations to Ollama
- **`docker-compose.dev.yml`** — disables Caddy, exposes services on localhost ports

Compose files are merged at runtime:

```bash
# Production with GPU
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d

# Development
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

The setup script handles this automatically via `OBOX_GPU` and `OBOX_DEV` environment variables.

## Scaling Considerations

This stack is designed for single-server deployments. For multi-node scaling:

- Run Ollama on dedicated GPU servers and point LiteLLM to remote Ollama instances
- Use an external load balancer instead of Caddy
- Consider vLLM or TGI for higher-throughput serving
- Add Redis for LiteLLM rate limiting and caching

## Resource Requirements

| Model Size | RAM | VRAM (GPU) | Disk |
|------------|-----|------------|------|
| 3B (phi3:mini) | 4 GB | 4 GB | 2 GB |
| 7B (mistral) | 8 GB | 8 GB | 5 GB |
| 13B | 16 GB | 16 GB | 8 GB |
| 70B | 64 GB | 48 GB+ | 40 GB |

CPU-only inference works but is significantly slower than GPU. Start with smaller models (`llama3.2:3b`, `phi3:mini`) and scale up based on available hardware.
