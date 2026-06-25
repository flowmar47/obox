#!/usr/bin/env bash
# obox setup — initialize environment and start the stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[obox]${NC} $*"; }
warn()  { echo -e "${YELLOW}[obox]${NC} $*"; }
error() { echo -e "${RED}[obox]${NC} $*" >&2; }

# --- Prerequisites ---
check_prerequisites() {
  info "Checking prerequisites..."

  if ! command -v docker &>/dev/null; then
    error "Docker is not installed. Install from https://docs.docker.com/get-docker/"
    exit 1
  fi

  if ! docker compose version &>/dev/null; then
    error "Docker Compose v2 is required. Install from https://docs.docker.com/compose/install/"
    exit 1
  fi

  if ! docker info &>/dev/null; then
    error "Docker daemon is not running. Start Docker and try again."
    exit 1
  fi

  info "Prerequisites OK"
}

# --- Environment file ---
setup_env() {
  if [[ ! -f .env ]]; then
    info "Creating .env from .env.example..."
    cp .env.example .env

    # Generate secure defaults
    if command -v openssl &>/dev/null; then
      SECRET=$(openssl rand -hex 32)
      API_KEY="sk-obox-$(openssl rand -hex 16)"
      if [[ "$(uname)" == "Darwin" ]]; then
        sed -i '' "s/change-me-generate-with-openssl-rand-hex-32/${SECRET}/" .env
        sed -i '' "s/sk-obox-change-me-generate-a-secure-key/${API_KEY}/" .env
      else
        sed -i "s/change-me-generate-with-openssl-rand-hex-32/${SECRET}/" .env
        sed -i "s/sk-obox-change-me-generate-a-secure-key/${API_KEY}/" .env
      fi
    fi

    warn "Review and update .env before production use (domain, passwords, email)."
  else
    info ".env already exists, skipping"
  fi
}

# --- Compose files ---
compose_files() {
  local files=("-f" "docker-compose.yml")

  if [[ "${OBOX_GPU:-false}" == "true" ]]; then
    files+=("-f" "docker-compose.gpu.yml")
    info "GPU mode enabled"
  fi

  if [[ "${OBOX_DEV:-false}" == "true" ]]; then
    files+=("-f" "docker-compose.dev.yml")
    info "Development mode enabled (direct port access)"
  fi

  echo "${files[@]}"
}

# --- Start stack ---
start_stack() {
  info "Starting obox stack..."
  # shellcheck disable=SC2046
  docker compose $(compose_files) up -d

  info "Waiting for services to become healthy..."
  sleep 10
  "$SCRIPT_DIR/healthcheck.sh" || warn "Some services may still be starting"
}

# --- Pull models ---
pull_models() {
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
  fi

  if [[ -z "${OLLAMA_MODELS:-}" ]]; then
    info "No models configured in OLLAMA_MODELS, skipping pull"
    return
  fi

  info "Pulling configured models: ${OLLAMA_MODELS}"
  IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
  for model in "${MODELS[@]}"; do
    model=$(echo "$model" | xargs)
    [[ -z "$model" ]] && continue
    info "Pulling ${model}..."
    docker exec obox-ollama ollama pull "$model" || warn "Failed to pull ${model}"
  done
}

# --- Main ---
main() {
  info "obox setup starting..."
  check_prerequisites
  setup_env
  start_stack
  pull_models

  echo ""
  info "obox is running!"
  echo ""
  if [[ "${OBOX_DEV:-false}" == "true" ]]; then
    echo "  Open WebUI:  http://localhost:3000"
    echo "  LiteLLM API: http://localhost:4000/v1"
    echo "  Portainer:   http://localhost:9000"
    echo "  Ollama:      http://localhost:11434"
  else
  # shellcheck disable=SC1091
    source .env 2>/dev/null || true
    DOMAIN="${OBOX_DOMAIN:-localhost}"
    echo "  Open WebUI:  http://${DOMAIN}"
    echo "  LiteLLM API: http://${DOMAIN}/v1"
    echo "  Portainer:   http://${DOMAIN}/portainer"
    echo "  Health:      http://${DOMAIN}/health"
  fi
  echo ""
  warn "Set Portainer admin password on first visit to /portainer"
}

main "$@"
