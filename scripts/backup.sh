#!/usr/bin/env bash
# obox backup — archive persistent Docker volumes to compressed tarballs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

BACKUP_BASE="${ROOT_DIR}/backups"
VOLUMES=("webui_data" "grafana_data" "portainer_data")
PROJECT_NAME="obox"

usage() {
  cat <<EOF
Usage: $0 [--dir PATH] [-h|--help]

Back up obox persistent Docker volumes (webui_data, grafana_data, portainer_data)
to compressed .tar.gz archives inside a timestamped subdirectory.

Options:
  --dir PATH    Target backup root directory (default: ./backups)
  -h, --help    Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "Error: --dir requires a path argument" >&2
        exit 1
      fi
      BACKUP_BASE="$2"
      shift 2
      ;;
    --dir=*)
      BACKUP_BASE="${1#--dir=}"
      if [[ -z "$BACKUP_BASE" ]]; then
        echo "Error: --dir requires a non-empty path" >&2
        exit 1
      fi
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if ! command -v docker &>/dev/null; then
  echo "Error: Docker is not installed." >&2
  exit 1
fi

if ! docker info &>/dev/null; then
  echo "Error: Docker daemon is not running." >&2
  exit 1
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_BASE"
BACKUP_BASE_ABS="$(cd "$BACKUP_BASE" && pwd)"
OUT_DIR="${BACKUP_BASE_ABS}/${TIMESTAMP}"
mkdir -p "$OUT_DIR"

echo "Backing up obox volumes to ${OUT_DIR}..."

BACKED_UP=0
for vol in "${VOLUMES[@]}"; do
  full_vol="${PROJECT_NAME}_${vol}"
  if docker volume inspect "$full_vol" &>/dev/null; then
    echo "  Archiving ${full_vol} -> ${vol}.tar.gz"
    docker run --rm \
      -v "${full_vol}:/source:ro" \
      -v "${OUT_DIR}:/backup" \
      alpine:3.20 \
      tar czf "/backup/${vol}.tar.gz" -C /source .
    BACKED_UP=$((BACKED_UP + 1))
  else
    echo "  Skipping ${full_vol} (volume does not exist)"
  fi
done

if [[ "$BACKED_UP" -eq 0 ]]; then
  echo "Warning: No matching obox volumes were found to back up." >&2
  rmdir "$OUT_DIR" 2>/dev/null || true
  exit 1
fi

echo "Backup complete (${BACKED_UP} volume(s)): ${OUT_DIR}"
