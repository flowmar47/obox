# Setup Guide

Detailed installation and configuration instructions for obox.

## System Requirements

### Minimum

- Linux server (Ubuntu 22.04+ recommended) or macOS with Docker Desktop
- 4 CPU cores
- 8 GB RAM
- 20 GB free disk space
- Docker Engine 24.0+
- Docker Compose v2.20+

### Recommended (Production)

- 8+ CPU cores
- 32 GB RAM
- NVIDIA GPU with 8+ GB VRAM
- 100 GB SSD
- Public IP with domain name

## Step-by-Step Installation

### 1. Install Docker

**Ubuntu/Debian:**

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
# Log out and back in for group changes
```

**Verify:**

```bash
docker --version
docker compose version
```

### 2. Clone and Configure

```bash
git clone https://github.com/flowmar47/obox.git
cd obox
cp .env.example .env
```

Edit `.env` with your settings:

```env
# Required for production
OBOX_DOMAIN=llm.example.com
OBOX_ACME_EMAIL=admin@example.com

# Security — generate with: openssl rand -hex 32
WEBUI_SECRET_KEY=<generated-secret>
LITELLM_MASTER_KEY=sk-obox-<generated-key>

# Disable public signup
WEBUI_ENABLE_SIGNUP=false
WEBUI_ADMIN_EMAIL=admin@example.com
WEBUI_ADMIN_PASSWORD=<strong-password>

# Models to install
OLLAMA_MODELS=llama3.2:3b,phi3:mini
```

### 3. DNS Configuration

Point your domain to the server:

```
llm.example.com  A  <your-server-ip>
```

Wait for DNS propagation (usually a few minutes).

### 4. Firewall

Open required ports:

```bash
# UFW example
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

Do not expose Ollama (11434), LiteLLM (4000), or Portainer (9000) directly — Caddy handles external access.

### 5. Start the Stack

```bash
./scripts/setup.sh
```

For GPU servers:

```bash
# Install NVIDIA Container Toolkit first
OBOX_GPU=true ./scripts/setup.sh
```

### 6. Verify

```bash
./scripts/healthcheck.sh
```

Visit your domain:

- `https://llm.example.com` — Open WebUI
- `https://llm.example.com/v1/models` — API (with auth header)
- `https://llm.example.com/portainer` — Container management

### 7. Initial Configuration

**Open WebUI:** Log in with the admin credentials from `.env`. Create additional users from Settings if needed.

**Portainer:** On first visit, create an admin account. Connect to the local Docker environment.

**LiteLLM:** Test the API:

```bash
source .env
curl https://llm.example.com/v1/models \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY"
```

## GPU Setup (NVIDIA)

### Install Drivers

```bash
# Ubuntu
sudo apt install nvidia-driver-535
sudo reboot
nvidia-smi  # verify
```

### Install Container Toolkit

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | \
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

sudo apt update
sudo apt install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

### Verify GPU in Container

```bash
OBOX_GPU=true ./scripts/setup.sh
docker exec obox-ollama nvidia-smi
```

## Adding Models

### Via Script

```bash
./scripts/pull-models.sh mistral:7b codellama:7b
```

### Via Ollama CLI

```bash
docker exec -it obox-ollama ollama pull mistral:7b
docker exec obox-ollama ollama list
```

### Via Open WebUI

Navigate to Settings → Models → Pull Model, enter the model name.

### Register in LiteLLM

Add to `config/litellm/config.yaml` for a friendly alias, or use the catch-all `*` route which passes any name to Ollama directly.

## Updating

```bash
./scripts/stop.sh
docker compose pull
./scripts/setup.sh
```

## Troubleshooting

### Services won't start

```bash
docker compose logs ollama
docker compose logs open-webui
```

### Out of memory

Use smaller models or increase swap:

```bash
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### TLS certificate issues

Ensure `OBOX_DOMAIN` matches your DNS A record and port 80 is reachable (required for ACME HTTP challenge).

### Model pull fails

Check disk space and network:

```bash
df -h
docker exec obox-ollama ollama pull llama3.2:3b
```

### Reset everything

```bash
./scripts/stop.sh
docker compose down -v  # WARNING: deletes all data volumes
./scripts/setup.sh
```
