#!/usr/bin/env bash
# obox stop — gracefully stop the stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

compose_files=("-f" "docker-compose.yml")
[[ "${OBOX_GPU:-false}" == "true" ]] && compose_files+=("-f" "docker-compose.gpu.yml")
[[ "${OBOX_DEV:-false}" == "true" ]] && compose_files+=("-f" "docker-compose.dev.yml")

echo "Stopping obox stack..."
# shellcheck disable=SC2046
docker compose "${compose_files[@]}" down

echo "obox stopped."
