#!/usr/bin/env bash
# obox healthcheck — verify all services are running
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS=0
FAIL=0

check_container() {
  local name="$1"
  if docker ps --format '{{.Names}}' | grep -q "^${name}$"; then
    local status
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$name" 2>/dev/null || echo "running")
    case "$status" in
      healthy|running|"<no value>"|"")
        echo -e "  ${GREEN}✓${NC} ${name} (${status})"
        PASS=$((PASS + 1))
        ;;
      unhealthy|exited|dead)
        echo -e "  ${RED}✗${NC} ${name} (${status})"
        FAIL=$((FAIL + 1))
        ;;
      *)
        echo -e "  ${YELLOW}~${NC} ${name} (${status})"
        PASS=$((PASS + 1))
        ;;
    esac
  else
    echo -e "  ${RED}✗${NC} ${name} (not running)"
    FAIL=$((FAIL + 1))
  fi
}

check_endpoint() {
  local url="$1"
  local label="$2"
  local auth_header="${3:-}"
  local curl_args=(-sf --max-time 5)
  if [[ -n "$auth_header" ]]; then
    curl_args+=(-H "$auth_header")
  fi

  if curl "${curl_args[@]}" "$url" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${label} (${url})"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} ${label} (${url})"
    FAIL=$((FAIL + 1))
  fi
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

echo "obox health check"
echo "================="
echo ""
echo "Containers:"
if [[ "${OBOX_DEV:-false}" != "true" ]]; then
  check_container "obox-caddy"
fi
check_container "obox-ollama"
check_container "obox-webui"
check_container "obox-litellm"
check_container "obox-portainer"
check_container "obox-prometheus"
check_container "obox-grafana"
check_container "obox-cadvisor"
check_container "obox-node-exporter"
check_container "obox-blackbox"
if [[ "${OBOX_GPU:-false}" == "true" ]]; then
  check_container "obox-dcgm-exporter"
fi

echo ""
echo "Endpoints:"

if [[ "${OBOX_DEV:-false}" == "true" ]]; then
  check_endpoint "http://localhost:3000/health" "Open WebUI"
  check_endpoint "http://localhost:4000/health/liveliness" "LiteLLM"
  check_endpoint "http://localhost:9000/api/status" "Portainer"
  check_endpoint "http://localhost:3001/api/health" "Grafana"
  check_endpoint "http://localhost:9090/-/healthy" "Prometheus"
  check_endpoint "http://localhost:11434" "Ollama"
else
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
  fi
  BASE_URL="$(base_url_from_domain "${OBOX_DOMAIN:-http://localhost}")"
  check_endpoint "${BASE_URL}/health" "Caddy proxy"
  check_endpoint "${BASE_URL}/grafana/api/health" "Grafana"
  if [[ -n "${LITELLM_MASTER_KEY:-}" ]]; then
    check_endpoint "${BASE_URL}/v1/models" "LiteLLM API" "Authorization: Bearer ${LITELLM_MASTER_KEY}"
  else
    check_endpoint "${BASE_URL}/litellm/health/liveliness" "LiteLLM API"
  fi
fi

echo ""
echo "================="
if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}All checks passed (${PASS}/${PASS})${NC}"
  exit 0
else
  echo -e "${RED}${FAIL} check(s) failed (${PASS} passed)${NC}"
  exit 1
fi
