#!/usr/bin/env bash
# obox stop — gracefully stop the stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

COMPOSE_FILES=("-f" "docker-compose.yml")
if [[ "${OBOX_GPU:-false}" == "true" ]]; then
  COMPOSE_FILES+=("-f" "docker-compose.gpu.yml")
fi
if [[ "${OBOX_DEV:-false}" == "true" ]]; then
  COMPOSE_FILES+=("-f" "docker-compose.dev.yml")
fi

echo "Stopping obox stack..."
docker compose "${COMPOSE_FILES[@]}" down

echo "obox stopped."
