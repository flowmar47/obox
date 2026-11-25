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

COMPOSE_FILES=()

usage() {
  cat <<EOF
Usage: $0 [--env-only] [-h|--help]

Initialize .env with generated secrets and start the obox Docker Compose stack.

Options:
  --env-only    Generate .env from .env.example if missing and exit
  -h, --help    Show this help message

Environment variables:
  OBOX_DEV=true   Start in development mode (127.0.0.1 direct ports, no Caddy)
  OBOX_GPU=true   Enable NVIDIA GPU override (docker-compose.gpu.yml)
EOF
}

# --- Secret generators ---
gen_hex() {
  local bytes="$1"
  if command -v openssl &>/dev/null; then
    openssl rand -hex "$bytes"
  elif command -v python3 &>/dev/null; then
    python3 -c "import secrets, sys; print(secrets.token_hex(int(sys.argv[1])))" "$bytes"
  else
    dd if=/dev/urandom bs=256 count=1 2>/dev/null | LC_ALL=C tr -dc '0-9a-f' | cut -c1-"$((bytes * 2))"
  fi
}

gen_password() {
  if command -v openssl &>/dev/null; then
    openssl rand -base64 24 | tr '+/' '-_' | tr -d '='
  elif command -v python3 &>/dev/null; then
    python3 -c "import secrets; print(secrets.token_urlsafe(18))"
  else
    dd if=/dev/urandom bs=256 count=1 2>/dev/null | LC_ALL=C tr -dc 'A-Za-z0-9_-' | cut -c1-24
  fi
}

set_env_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s=%s\n' "$key" "$value"
    else
      printf '%s\n' "$line"
    fi
  done < "$file" > "$tmp"
  mv "$tmp" "$file"
}

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

    local webui_secret litellm_key grafana_pass webui_pass portainer_pass
    webui_secret="$(gen_hex 32)"
    litellm_key="sk-obox-$(gen_hex 16)"
    grafana_pass="$(gen_password)"
    webui_pass="$(gen_password)"
    portainer_pass="$(gen_password)"

    set_env_var .env "WEBUI_SECRET_KEY" "$webui_secret"
    set_env_var .env "LITELLM_MASTER_KEY" "$litellm_key"
    set_env_var .env "GRAFANA_ADMIN_PASSWORD" "$grafana_pass"
    set_env_var .env "WEBUI_ADMIN_PASSWORD" "$webui_pass"
    set_env_var .env "PORTAINER_ADMIN_PASSWORD" "$portainer_pass"

    chmod 600 .env
    warn "Review and update .env before production use (domain, email, passwords)."
  else
    info ".env already exists, skipping"
  fi
}

# --- Compose files ---
compose_files() {
  COMPOSE_FILES=("-f" "docker-compose.yml")

  if [[ "${OBOX_GPU:-false}" == "true" ]]; then
    COMPOSE_FILES+=("-f" "docker-compose.gpu.yml")
    info "GPU mode enabled"
  fi

  if [[ "${OBOX_DEV:-false}" == "true" ]]; then
    COMPOSE_FILES+=("-f" "docker-compose.dev.yml")
    info "Development mode enabled (direct port access on 127.0.0.1)"
  fi
}

# --- Start stack ---
start_stack() {
  info "Starting obox stack..."
  compose_files
  docker compose "${COMPOSE_FILES[@]}" up -d

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
    model="${model#"${model%%[![:space:]]*}"}"
    model="${model%"${model##*[![:space:]]}"}"
    [[ -z "$model" ]] && continue
    info "Pulling ${model}..."
    docker exec obox-ollama ollama pull "$model" || warn "Failed to pull ${model}"
  done
}

base_url_from_domain() {
  local domain="${1:-http://localhost}"
  if [[ "$domain" == http://* || "$domain" == https://* ]]; then
    printf '%s' "${domain%/}"
  elif [[ "$domain" == "localhost" || "$domain" == "127.0.0.1" ]]; then
    printf 'http://%s' "$domain"
  else
    printf 'https://%s' "$domain"
  fi
}

# --- Main ---
main() {
  local env_only=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --env-only)
        env_only=true
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown option: $1"
        usage >&2
        exit 1
        ;;
    esac
  done

  info "obox setup starting..."
  if [[ "$env_only" == "true" ]]; then
    setup_env
    exit 0
  fi

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
    echo "  Grafana:     http://localhost:3001 (admin / see .env)"
    echo "  Prometheus:  http://localhost:9090"
    echo "  Ollama:      http://localhost:11434"
  else
    if [[ -f .env ]]; then
      # shellcheck disable=SC1091
      source .env
    fi
    local base_url
    base_url="$(base_url_from_domain "${OBOX_DOMAIN:-http://localhost}")"
    echo "  Open WebUI:  ${base_url}"
    echo "  LiteLLM API: ${base_url}/v1"
    echo "  Portainer:   ${base_url}/portainer/"
    echo "  Grafana:     ${base_url}/grafana/"
    echo "  Health:      ${base_url}/health"
  fi
  echo ""
  warn "Set Portainer admin password on first visit to /portainer/"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
