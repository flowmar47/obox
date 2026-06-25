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
    status=$(docker inspect --format='{{.State.Health.Status}}' "$name" 2>/dev/null || echo "running")
    if [[ "$status" == "healthy" || "$status" == "running" || "$status" == "<no value>" ]]; then
      echo -e "  ${GREEN}✓${NC} ${name} (${status})"
      PASS=$((PASS + 1))
    else
      echo -e "  ${YELLOW}~${NC} ${name} (${status})"
      PASS=$((PASS + 1))
    fi
  else
    echo -e "  ${RED}✗${NC} ${name} (not running)"
    FAIL=$((FAIL + 1))
  fi
}

check_endpoint() {
  local url="$1"
  local label="$2"
  if curl -sf --max-time 5 "$url" &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} ${label} (${url})"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} ${label} (${url})"
    FAIL=$((FAIL + 1))
  fi
}

echo "obox health check"
echo "================="
echo ""
echo "Containers:"
check_container "obox-caddy"
check_container "obox-ollama"
check_container "obox-webui"
check_container "obox-litellm"
check_container "obox-portainer"

echo ""
echo "Endpoints:"

if [[ "${OBOX_DEV:-false}" == "true" ]]; then
  check_endpoint "http://localhost:3000/health" "Open WebUI"
  check_endpoint "http://localhost:4000/health/liveliness" "LiteLLM"
  check_endpoint "http://localhost:9000/api/status" "Portainer"
  check_endpoint "http://localhost:11434" "Ollama"
else
  if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    source .env
  fi
  DOMAIN="${OBOX_DOMAIN:-localhost}"
  check_endpoint "http://${DOMAIN}/health" "Caddy proxy"
  check_endpoint "http://${DOMAIN}/v1/models" "LiteLLM API" || true
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
