# obox

**Remote LLM server** — self-hosted AI inference with a web UI, OpenAI-compatible API, and Docker management via Portainer.

```
┌──────────────────────────────────────────────────────────────────┐
│                         Caddy (TLS)                              │
│               your-domain.com / http://localhost                 │
├──────────┬──────────┬──────────────┬──────────────┬────────────────┤
│ Open     │ LiteLLM  │  Portainer   │  Grafana     │  /health       │
│ WebUI    │  /v1/*   │  /portainer/ │  /grafana    │                │
│    │     │ /litellm │              │      │       │                │
│    ▼     │    │     │              │      ▼       │                │
│       Ollama ◄┘     │              │  Prometheus ◄┼── node-exporter│
│    (LLM runtime)                   │      ▲       │    cAdvisor    │
│                                    │      └───────┼── blackbox     │
└────────────────────────────────────┴──────────────┴────────────────┘
```

## Features

- **Ollama** — run open-source LLMs locally (Llama, Mistral, Phi, CodeLlama, and more)
- **Open WebUI** — modern chat interface with model management and conversation history
- **LiteLLM** — OpenAI-compatible API gateway for programmatic access
- **Portainer** — web-based Docker container management
- **Caddy** — automatic HTTPS with Let's Encrypt (production) or local HTTP (`http://localhost`) with security headers
- **Prometheus + Grafana** — host, container, GPU, and HTTP probe monitoring with pre-built dashboards and alert rules

## Quick Start

### Prerequisites

- Docker Engine 24+ and Docker Compose v2
- 8 GB RAM minimum (16 GB recommended for larger models)
- Optional: NVIDIA GPU + [Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) for accelerated inference

### Install

```bash
git clone https://github.com/flowmar47/obox.git
cd obox
./scripts/setup.sh
```

The setup script will:

1. Check Docker prerequisites
2. Create `.env` from `.env.example` with unique generated secrets (`chmod 600 .env`)
3. Start all services
4. Pull configured models (default: `llama3.2:3b`, `phi3:mini`)

### Development Mode

For local development without TLS, expose services on `127.0.0.1` only:

```bash
OBOX_DEV=true ./scripts/setup.sh
# or: make dev
```

| Service     | URL                          |
|-------------|------------------------------|
| Open WebUI  | http://localhost:3000        |
| LiteLLM API | http://localhost:4000/v1     |
| Portainer   | http://localhost:9000        |
| Grafana     | http://localhost:3001        |
| Prometheus  | http://localhost:9090        |
| Ollama      | http://localhost:11434       |

### Production

1. Generate or copy `.env` and customize:

```bash
./scripts/setup.sh --env-only   # or: make env
# Edit: OBOX_DOMAIN=your-domain.com, OBOX_ACME_EMAIL, GRAFANA_ROOT_URL, etc.
```

> Use `OBOX_DOMAIN=http://localhost` for local HTTP, or `OBOX_DOMAIN=your-domain.com` (without scheme) for automatic Let's Encrypt HTTPS.

2. Point your domain's DNS A record to the server

3. Start the stack:

```bash
./scripts/setup.sh
```

4. Set the Portainer admin password on first visit to `https://your-domain.com/portainer/`

## API Usage

LiteLLM exposes an OpenAI-compatible API at `/v1` (and `/litellm`):

```bash
# List models
curl http://localhost:4000/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Chat completion
curl http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.2",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

Use with any OpenAI SDK by setting `base_url` to your obox endpoint.

## Model Management

```bash
# Pull additional models
./scripts/pull-models.sh mistral:7b codellama:7b

# List installed models
docker exec obox-ollama ollama list

# Remove a model
docker exec obox-ollama ollama rm mistral:7b
```

Configure default models in `.env`:

```env
OLLAMA_MODELS=llama3.2:3b,phi3:mini,mistral:7b
```

## GPU Support

Enable NVIDIA GPU acceleration:

```bash
OBOX_GPU=true ./scripts/setup.sh
# or: make gpu
```

Requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed on the host. GPU metrics appear automatically in Grafana when GPU mode is enabled.

## Monitoring

Grafana dashboards are available at `/grafana` (or `http://localhost:3001` in dev mode) with a pre-built **obox Overview** dashboard covering:

- Service health and HTTP probe latency
- Host CPU, memory, disk, and network
- Per-container resource usage for all obox services
- NVIDIA GPU utilization and memory (GPU mode)

Prometheus loads alert rules from `config/prometheus/alerts.yml` (`ServiceDown`, `HighHostMemory`, `HighDiskUsage`, `HighGPUMemory`) and runs internally without public exposure.

```bash
# Production
https://your-domain.com/grafana/

# Development
http://localhost:3001
```

Login with `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` from `.env`.

See [Monitoring Guide](docs/monitoring.md) for dashboards, alerts, and troubleshooting.

## Operations

```bash
# Health check (set OBOX_DEV=true or OBOX_GPU=true to match active mode)
./scripts/healthcheck.sh

# Offline config & script validation
./scripts/validate.sh    # or: make validate

# Back up persistent volumes (webui_data, grafana_data, portainer_data)
./scripts/backup.sh      # or: make backup

# Show container status
make status

# Pull latest images and restart
make update

# Stop the stack
./scripts/stop.sh

# View logs
docker compose logs -f
```

## Configuration

All configuration is via `.env`. See [`.env.example`](.env.example) for which service consumes each variable.

| Variable | Description | Default |
|----------|-------------|---------|
| `OBOX_DOMAIN` | `http://localhost` for HTTP or `your-domain.com` for HTTPS | `http://localhost` |
| `OBOX_ACME_EMAIL` | Let's Encrypt email | `admin@example.com` |
| `WEBUI_SECRET_KEY` | Session signing key | auto-generated |
| `WEBUI_ENABLE_SIGNUP` | Allow new user registration | `false` |
| `WEBUI_ADMIN_EMAIL` | Default Open WebUI admin email | `admin@example.com` |
| `WEBUI_ADMIN_PASSWORD` | Reference Open WebUI admin password | auto-generated |
| `PORTAINER_ADMIN_PASSWORD` | Reference Portainer password for first visit | auto-generated |
| `LITELLM_MASTER_KEY` | API authentication key | auto-generated |
| `OLLAMA_MODELS` | Models to pull on setup | `llama3.2:3b,phi3:mini` |
| `OLLAMA_GPU_ENABLED` | Informational flag (use `OBOX_GPU=true` to enable GPU) | `false` |
| `GRAFANA_ADMIN_USER` | Grafana admin username | `admin` |
| `GRAFANA_ADMIN_PASSWORD` | Grafana admin password | auto-generated |
| `GRAFANA_ROOT_URL` | Grafana public URL | `http://localhost/grafana/` |

## Project Structure

```
obox/
├── docker-compose.yml          # Main stack definition
├── docker-compose.gpu.yml      # GPU override
├── docker-compose.dev.yml      # Development override (127.0.0.1 ports)
├── Makefile                    # Convenience operational targets
├── .env.example                # Environment template
├── config/
│   ├── caddy/Caddyfile         # Reverse proxy routing & security headers
│   ├── litellm/config.yaml     # API gateway model routing
│   ├── prometheus/             # Metrics scrape & alert rules
│   └── grafana/                # Dashboards and provisioning
├── scripts/
│   ├── setup.sh                # One-command setup & secret generation
│   ├── healthcheck.sh          # Service & endpoint health verification
│   ├── pull-models.sh          # Model download helper
│   ├── backup.sh               # Persistent volume backup helper
│   ├── validate.sh             # Offline config & script validator
│   └── stop.sh                 # Graceful shutdown
├── tests/
│   └── test_obox.py            # Offline unit test suite
├── .github/workflows/ci.yml    # CI validation workflow
└── docs/
    ├── architecture.md         # System design
    ├── monitoring.md           # Prometheus/Grafana guide
    ├── setup.md                # Detailed setup guide
    └── security.md             # Security hardening
```

## Documentation

- [Architecture](docs/architecture.md) — system design and component interactions
- [Monitoring](docs/monitoring.md) — Prometheus/Grafana dashboards and alerts
- [Setup Guide](docs/setup.md) — detailed installation and configuration
- [Security](docs/security.md) — hardening for production deployments

## License

MIT — see [LICENSE](LICENSE).
