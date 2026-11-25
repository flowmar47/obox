#!/usr/bin/env bash
# obox validate — offline configuration and script validation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR"

usage() {
  cat <<EOF
Usage: $0 [-h|--help]

Run offline validation checks across scripts, configs, JSON/YAML files,
Caddyfile routing, and Docker Compose overrides without requiring a running daemon.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

FAILURES=0

pass() { echo "[PASS] $*"; }
fail() { echo "[FAIL] $*" >&2; FAILURES=$((FAILURES + 1)); }

echo "Running obox offline validation..."

# 1. Bash syntax
if bash -n scripts/*.sh; then
  pass "bash -n scripts/*.sh"
else
  fail "bash -n scripts/*.sh"
fi

# 2. ShellCheck
if command -v shellcheck &>/dev/null; then
  if shellcheck scripts/*.sh; then
    pass "shellcheck scripts/*.sh"
  else
    fail "shellcheck scripts/*.sh"
  fi
else
  fail "shellcheck not installed"
fi

# 3. JSON, YAML, and Caddyfile checks via Python stdlib (plus PyYAML if available)
if command -v python3 &>/dev/null; then
  if python3 - <<'PY'
import json
import pathlib
import sys

errors = []

# Validate Grafana dashboard JSON
for p in pathlib.Path("config/grafana/dashboards").glob("*.json"):
    try:
        json.loads(p.read_text(encoding="utf-8"))
    except Exception as exc:
        errors.append(f"Invalid JSON {p}: {exc}")

# Validate YAML files if PyYAML is available, otherwise basic checks
yaml_files = [
    "docker-compose.yml",
    "docker-compose.dev.yml",
    "docker-compose.gpu.yml",
    "config/litellm/config.yaml",
    "config/prometheus/prometheus.yml",
    "config/prometheus/alerts.yml",
    "config/prometheus/blackbox.yml",
    "config/grafana/provisioning/datasources/datasources.yml",
    "config/grafana/provisioning/dashboards/dashboards.yml",
]
try:
    import yaml  # type: ignore
except ImportError:
    yaml = None

for yf in yaml_files:
    p = pathlib.Path(yf)
    if not p.is_file():
        errors.append(f"Missing YAML file: {yf}")
        continue
    text = p.read_text(encoding="utf-8")
    if "\t" in text:
        errors.append(f"Tab character found in YAML file: {yf}")
    if yaml is not None:
        try:
            yaml.safe_load(text)
        except Exception as exc:
            errors.append(f"Invalid YAML {yf}: {exc}")

# Caddyfile structural checks
caddy_text = pathlib.Path("config/caddy/Caddyfile").read_text(encoding="utf-8")
if "{$OBOX_DOMAIN:http://localhost}" not in caddy_text:
    errors.append("Caddyfile missing {$OBOX_DOMAIN:http://localhost} site block")
if "\nhandle {" not in caddy_text and "\thandle {" not in caddy_text:
    errors.append("Caddyfile missing fallback 'handle {' block")
if "\nhandle / {" in caddy_text or "\thandle / {" in caddy_text:
    errors.append("Caddyfile still contains broken exact 'handle / {' block")
if "\n:80 {" in caddy_text:
    errors.append("Caddyfile still contains conflicting ':80 {' block")

if errors:
    for err in errors:
        print(err, file=sys.stderr)
    sys.exit(1)
PY
  then
    pass "JSON/YAML/Caddyfile structural checks"
  else
    fail "JSON/YAML/Caddyfile structural checks"
  fi
else
  fail "python3 not installed"
fi

# 4. Optional Caddy native validation
if command -v caddy &>/dev/null; then
  if caddy validate --config config/caddy/Caddyfile --adapter caddyfile &>/dev/null; then
    pass "caddy validate"
  else
    fail "caddy validate"
  fi
fi

# 5. Docker Compose config checks across all 4 modes
if command -v docker &>/dev/null && docker compose version &>/dev/null; then
  modes=(
    "base:-f docker-compose.yml"
    "dev:-f docker-compose.yml -f docker-compose.dev.yml"
    "gpu:-f docker-compose.yml -f docker-compose.gpu.yml"
    "dev+gpu:-f docker-compose.yml -f docker-compose.dev.yml -f docker-compose.gpu.yml"
  )
  for entry in "${modes[@]}"; do
    label="${entry%%:*}"
    flags="${entry#*:}"
    read -ra flag_arr <<< "$flags"
    if docker compose --env-file .env.example "${flag_arr[@]}" config -q; then
      pass "docker compose config (${label})"
    else
      fail "docker compose config (${label})"
    fi
  done
else
  fail "docker compose v2 not installed"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  echo "Validation failed with ${FAILURES} error(s)." >&2
  exit 1
fi

echo "All validation checks passed."
