# obox

**Remote LLM server** — self-hosted AI inference with a web UI, OpenAI-compatible API, and Docker management via Portainer.

```
┌─────────────────────────────────────────────────────────────┐
│                        Caddy (TLS)                          │
│              your-domain.com / localhost                     │
├──────────┬──────────────┬──────────────┬────────────────────┤
│ Open     │  LiteLLM     │  Portainer   │  /health           │
│ WebUI    │  /v1/*       │  /portainer  │                    │
│    │     │      │       │              │                    │
│    └─────┼──────┘       │              │                    │
│          ▼              │              │                    │
│       Ollama ◄──────────┘              │                    │
│    (LLM runtime)                        │                    │
└─────────────────────────────────────────────────────────────┘
```

## Features

- **Ollama** — run open-source LLMs locally (Llama, Mistral, Phi, CodeLlama, and more)
- **Open WebUI** — modern chat interface with model management and conversation history
- **LiteLLM** — OpenAI-compatible API gateway for programmatic access
- **Portainer** — web-based Docker container management
- **Caddy** — automatic HTTPS with Let's Encrypt (production) or plain HTTP (local dev)

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
2. Create `.env` from `.env.example` with generated secrets
3. Start all services
4. Pull configured models (default: `llama3.2:3b`, `phi3:mini`)

### Development Mode

For local development without TLS, expose services on direct ports:

```bash
OBOX_DEV=true ./scripts/setup.sh
```

| Service     | URL                          |
|-------------|------------------------------|
| Open WebUI  | http://localhost:3000        |
| LiteLLM API | http://localhost:4000/v1     |
| Portainer   | http://localhost:9000        |
| Ollama      | http://localhost:11434       |

### Production

1. Copy and configure environment:

```bash
cp .env.example .env
# Edit: OBOX_DOMAIN, OBOX_ACME_EMAIL, passwords, API keys
```

2. Point your domain's DNS A record to the server

3. Start the stack:

```bash
./scripts/setup.sh
```

4. Set the Portainer admin password on first visit to `https://your-domain.com/portainer`

## API Usage

LiteLLM exposes an OpenAI-compatible API at `/v1`:

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
```

Requires the [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) installed on the host.

## Operations

```bash
# Health check
./scripts/healthcheck.sh

# Stop the stack
./scripts/stop.sh

# View logs
docker compose logs -f

# View logs for a specific service
docker compose logs -f ollama
```

## Configuration

All configuration is via `.env`. See [`.env.example`](.env.example) for the full list.

| Variable | Description | Default |
|----------|-------------|---------|
| `OBOX_DOMAIN` | Public hostname | `localhost` |
| `OBOX_ACME_EMAIL` | Let's Encrypt email | — |
| `WEBUI_SECRET_KEY` | Session signing key | auto-generated |
| `WEBUI_ENABLE_SIGNUP` | Allow new user registration | `false` |
| `LITELLM_MASTER_KEY` | API authentication key | auto-generated |
| `OLLAMA_MODELS` | Models to pull on setup | `llama3.2:3b,phi3:mini` |
| `OLLAMA_GPU_ENABLED` | Enable GPU (use with `OBOX_GPU=true`) | `false` |

## Project Structure

```
obox/
├── docker-compose.yml          # Main stack definition
├── docker-compose.gpu.yml      # GPU override
├── docker-compose.dev.yml      # Development override (direct ports)
├── .env.example                # Environment template
├── config/
│   ├── caddy/Caddyfile         # Reverse proxy routing
│   └── litellm/config.yaml     # API gateway model routing
├── scripts/
│   ├── setup.sh                # One-command setup
│   ├── healthcheck.sh          # Service health verification
│   ├── pull-models.sh          # Model download helper
│   └── stop.sh                 # Graceful shutdown
└── docs/
    ├── architecture.md         # System design
    ├── setup.md                # Detailed setup guide
    └── security.md             # Security hardening
```

## Documentation

- [Architecture](docs/architecture.md) — system design and component interactions
- [Setup Guide](docs/setup.md) — detailed installation and configuration
- [Security](docs/security.md) — hardening for production deployments

## License

MIT — see [LICENSE](LICENSE).
