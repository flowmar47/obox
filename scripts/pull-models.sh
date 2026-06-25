#!/usr/bin/env bash
# obox pull-models — download LLM models into Ollama
set -euo pipefail

usage() {
  echo "Usage: $0 [model1 model2 ...]"
  echo ""
  echo "Pull one or more models into the running Ollama container."
  echo "If no models are specified, uses OLLAMA_MODELS from .env"
  echo ""
  echo "Examples:"
  echo "  $0 llama3.2:3b"
  echo "  $0 llama3.2:3b phi3:mini mistral:7b"
  echo "  $0   # pulls models from .env"
  exit 0
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

if ! docker ps --format '{{.Names}}' | grep -q "^obox-ollama$"; then
  echo "Error: obox-ollama container is not running. Start the stack first: ./scripts/setup.sh"
  exit 1
fi

if [[ $# -gt 0 ]]; then
  MODELS=("$@")
elif [[ -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  if [[ -z "${OLLAMA_MODELS:-}" ]]; then
    echo "No models specified and OLLAMA_MODELS is empty in .env"
    exit 1
  fi
  IFS=',' read -ra MODELS <<< "$OLLAMA_MODELS"
else
  echo "No models specified. Pass model names or set OLLAMA_MODELS in .env"
  exit 1
fi

for model in "${MODELS[@]}"; do
  model=$(echo "$model" | xargs)
  [[ -z "$model" ]] && continue
  echo "Pulling ${model}..."
  docker exec obox-ollama ollama pull "$model"
done

echo ""
echo "Installed models:"
docker exec obox-ollama ollama list
