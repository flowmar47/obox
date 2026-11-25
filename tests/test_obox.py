"""Stdlib unittest suite for obox configuration, scripts, and Compose modes."""

from __future__ import annotations

import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"
SECRET_KEYS = (
    "WEBUI_SECRET_KEY",
    "LITELLM_MASTER_KEY",
    "GRAFANA_ADMIN_PASSWORD",
    "WEBUI_ADMIN_PASSWORD",
    "PORTAINER_ADMIN_PASSWORD",
)


def parse_env_file(path: pathlib.Path) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, val = line.split("=", 1)
        values[key.strip()] = val.strip()
    return values


class TestOboxConfiguration(unittest.TestCase):
    def test_scripts_bash_syntax(self) -> None:
        scripts = sorted(SCRIPTS_DIR.glob("*.sh"))
        self.assertGreaterEqual(len(scripts), 6)
        for script in scripts:
            with self.subTest(script=script.name):
                res = subprocess.run(
                    ["bash", "-n", str(script)],
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(res.returncode, 0, res.stderr)

    def test_scripts_shellcheck(self) -> None:
        shellcheck = shutil.which("shellcheck")
        if shellcheck is None:
            self.fail("shellcheck is required on PATH")
        scripts = sorted(str(p) for p in SCRIPTS_DIR.glob("*.sh"))
        res = subprocess.run(
            [shellcheck, *scripts],
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

    def test_setup_env_generates_unique_secrets_and_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tmp_root = pathlib.Path(tmp)
            tmp_scripts = tmp_root / "scripts"
            tmp_scripts.mkdir()
            shutil.copy2(SCRIPTS_DIR / "setup.sh", tmp_scripts / "setup.sh")
            shutil.copy2(REPO_ROOT / ".env.example", tmp_root / ".env.example")

            res = subprocess.run(
                ["bash", str(tmp_scripts / "setup.sh"), "--env-only"],
                cwd=tmp_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

            env_path = tmp_root / ".env"
            self.assertTrue(env_path.is_file())
            mode = stat.S_IMODE(os.stat(env_path).st_mode)
            self.assertEqual(mode, 0o600)

            parsed = parse_env_file(env_path)
            generated: list[str] = []
            for key in SECRET_KEYS:
                self.assertIn(key, parsed)
                val = parsed[key]
                self.assertTrue(val, f"{key} must not be empty")
                self.assertNotIn("change-me", val.lower(), f"{key} kept placeholder")
                self.assertGreaterEqual(len(val), 24, f"{key} too short")
                generated.append(val)

            self.assertEqual(len(set(generated)), len(SECRET_KEYS), "Secrets must be unique")
            self.assertTrue(parsed["LITELLM_MASTER_KEY"].startswith("sk-obox-"))

            # Running again must preserve existing .env
            first_contents = env_path.read_text(encoding="utf-8")
            res2 = subprocess.run(
                ["bash", str(tmp_scripts / "setup.sh"), "--env-only"],
                cwd=tmp_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(res2.returncode, 0, res2.stdout + res2.stderr)
            self.assertEqual(env_path.read_text(encoding="utf-8"), first_contents)

    def test_setup_compose_files_and_urls(self) -> None:
        bash_probe = """
        source ./scripts/setup.sh
        OBOX_GPU=true OBOX_DEV=true compose_files >/dev/null
        printf '%s\\n' "${COMPOSE_FILES[@]}"
        echo "---"
        base_url_from_domain "http://localhost"
        echo ""
        base_url_from_domain "localhost"
        echo ""
        base_url_from_domain "llm.example.com"
        echo ""
        """
        res = subprocess.run(
            ["bash", "-c", bash_probe],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(res.returncode, 0, res.stderr)
        files_part, urls_part = res.stdout.split("---\n", 1)
        self.assertEqual(
            files_part.strip().splitlines(),
            [
                "-f",
                "docker-compose.yml",
                "-f",
                "docker-compose.gpu.yml",
                "-f",
                "docker-compose.dev.yml",
            ],
        )
        self.assertEqual(
            urls_part.strip().splitlines(),
            ["http://localhost", "http://localhost", "https://llm.example.com"],
        )

    def test_script_help_flags(self) -> None:
        for name in ("setup.sh", "pull-models.sh", "backup.sh", "validate.sh"):
            with self.subTest(script=name):
                res = subprocess.run(
                    ["bash", str(SCRIPTS_DIR / name), "--help"],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(res.returncode, 0, res.stderr)
                self.assertIn("Usage:", res.stdout)

    def test_caddyfile_routing_and_headers(self) -> None:
        text = (REPO_ROOT / "config" / "caddy" / "Caddyfile").read_text(encoding="utf-8")
        self.assertIn("{$OBOX_DOMAIN:http://localhost}", text)
        self.assertNotRegex(text, r"(?m)^\s*handle\s+/\s*\{")
        self.assertNotRegex(text, r"(?m)^:80\s*\{")

        for header in (
            "X-Content-Type-Options nosniff",
            "X-Frame-Options SAMEORIGIN",
            "Referrer-Policy strict-origin-when-cross-origin",
        ):
            self.assertIn(header, text)

        required_order = [
            "handle /health",
            "handle /v1/*",
            "handle_path /litellm/*",
            "redir /portainer /portainer/ 308",
            "handle_path /portainer/*",
            "handle /grafana*",
            "handle {",
        ]
        positions = [text.index(token) for token in required_order]
        self.assertEqual(positions, sorted(positions), "Caddy handlers must precede fallback handle")
        self.assertIn("reverse_proxy open-webui:8080", text[positions[-1]:])

    def test_grafana_dashboard_json_valid(self) -> None:
        dashboards = list((REPO_ROOT / "config" / "grafana" / "dashboards").glob("*.json"))
        self.assertTrue(dashboards)
        for dash in dashboards:
            with self.subTest(dashboard=dash.name):
                data = json.loads(dash.read_text(encoding="utf-8"))
                self.assertIsInstance(data, dict)
                self.assertIn("panels", data)
                self.assertGreater(len(data["panels"]), 0)

    def test_prometheus_and_alerts_config(self) -> None:
        prom = (REPO_ROOT / "config" / "prometheus" / "prometheus.yml").read_text(encoding="utf-8")
        alerts = (REPO_ROOT / "config" / "prometheus" / "alerts.yml").read_text(encoding="utf-8")

        self.assertIn("/etc/prometheus/alerts.yml", prom)
        self.assertNotIn("Drop target when exporter is not deployed", prom)

        for alert_name in ("ServiceDown", "HighHostMemory", "HighDiskUsage", "HighGPUMemory"):
            self.assertIn(f"alert: {alert_name}", alerts)

    def test_yaml_files_well_formed(self) -> None:
        yaml_paths = [
            REPO_ROOT / "docker-compose.yml",
            REPO_ROOT / "docker-compose.dev.yml",
            REPO_ROOT / "docker-compose.gpu.yml",
            REPO_ROOT / "config" / "litellm" / "config.yaml",
            REPO_ROOT / "config" / "prometheus" / "prometheus.yml",
            REPO_ROOT / "config" / "prometheus" / "alerts.yml",
            REPO_ROOT / "config" / "prometheus" / "blackbox.yml",
            REPO_ROOT / "config" / "grafana" / "provisioning" / "datasources" / "datasources.yml",
            REPO_ROOT / "config" / "grafana" / "provisioning" / "dashboards" / "dashboards.yml",
            REPO_ROOT / ".github" / "workflows" / "ci.yml",
        ]
        try:
            import yaml  # type: ignore
        except ImportError:
            yaml = None

        for path in yaml_paths:
            with self.subTest(file=str(path.relative_to(REPO_ROOT))):
                self.assertTrue(path.is_file())
                content = path.read_text(encoding="utf-8")
                self.assertNotIn("\t", content)
                if yaml is not None:
                    loaded = yaml.safe_load(content)
                    self.assertIsNotNone(loaded)

    def test_dev_compose_binds_localhost_only(self) -> None:
        dev_text = (REPO_ROOT / "docker-compose.dev.yml").read_text(encoding="utf-8")
        port_lines = re.findall(r'^\s*-\s*"([^"]+)"', dev_text, flags=re.MULTILINE)
        self.assertGreaterEqual(len(port_lines), 6)
        for mapping in port_lines:
            self.assertTrue(
                mapping.startswith("127.0.0.1:"),
                f"Dev port mapping must bind to 127.0.0.1: {mapping}",
            )

    def test_docker_compose_config_all_modes(self) -> None:
        modes = {
            "base": ["-f", "docker-compose.yml"],
            "dev": ["-f", "docker-compose.yml", "-f", "docker-compose.dev.yml"],
            "gpu": ["-f", "docker-compose.yml", "-f", "docker-compose.gpu.yml"],
            "dev+gpu": [
                "-f",
                "docker-compose.yml",
                "-f",
                "docker-compose.dev.yml",
                "-f",
                "docker-compose.gpu.yml",
            ],
        }
        for name, flags in modes.items():
            with self.subTest(mode=name):
                res = subprocess.run(
                    ["docker", "compose", "--env-file", ".env.example", *flags, "config", "-q"],
                    cwd=REPO_ROOT,
                    capture_output=True,
                    text=True,
                    check=False,
                )
                self.assertEqual(res.returncode, 0, res.stdout + res.stderr)

        # Verify alerts.yml mount and OBOX_DOMAIN default in rendered base config
        rendered = subprocess.run(
            ["docker", "compose", "--env-file", ".env.example", "-f", "docker-compose.yml", "config"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=True,
        ).stdout
        self.assertIn("/etc/prometheus/alerts.yml", rendered)
        self.assertIn("OBOX_DOMAIN: http://localhost", rendered)


if __name__ == "__main__":
    unittest.main()
