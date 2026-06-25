# Security

Security considerations for deploying obox in production.

## Threat Model

obox exposes AI inference and container management over the network. Key risks:

- **Unauthorized API access** — attackers using your LLMs and consuming GPU/CPU resources
- **Data exposure** — chat history and uploaded documents in Open WebUI
- **Container escape via Portainer** — full Docker control if Portainer is compromised
- **Model poisoning** — malicious models affecting inference output

## Authentication

### Open WebUI

- Set `WEBUI_ENABLE_SIGNUP=false` in production
- Use strong admin credentials
- Create individual accounts for each user rather than sharing credentials
- Enable OAuth/SSO if available in your Open WebUI version (Settings → Authentication)

### LiteLLM API

- Always set a strong `LITELLM_MASTER_KEY` (32+ random characters)
- Never commit `.env` to version control
- Rotate the key periodically
- Use per-client keys if you add multiple consumers (configure in `config/litellm/config.yaml`)

### Portainer

- Create a strong admin password on first login
- Do not expose Portainer to the public internet without additional protection
- Consider restricting `/portainer` to internal IPs via firewall

## Network Hardening

### Firewall Rules

Only expose ports 80 and 443:

```bash
sudo ufw default deny incoming
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### Restrict Portainer Access

Add IP allowlisting in the Caddyfile for production:

```
handle /portainer/* {
    @blocked not remote_ip 10.0.0.0/8 192.168.0.0/16 YOUR_OFFICE_IP
    respond @blocked "Forbidden" 403
    uri strip_prefix /portainer
    reverse_proxy portainer:9000
}
```

### VPN Access

For maximum security, do not expose obox publicly. Instead:

1. Run obox on a private network
2. Access via VPN (WireGuard, Tailscale) or SSH tunnel
3. Use `OBOX_DEV=true` with SSH port forwarding

## TLS

Caddy handles TLS automatically when `OBOX_DOMAIN` is a real domain. Ensure:

- DNS A record points to your server
- Port 80 is open (required for ACME HTTP-01 challenge)
- `OBOX_ACME_EMAIL` is set for certificate expiry notifications

For custom certificates, mount them into the Caddy container and update the Caddyfile.

## Secrets Management

### Generate Secure Values

```bash
# WebUI secret key
openssl rand -hex 32

# LiteLLM API key
echo "sk-obox-$(openssl rand -hex 16)"

# Strong password
openssl rand -base64 24
```

### Do Not

- Commit `.env` to git (it is in `.gitignore`)
- Use default passwords from `.env.example`
- Share API keys in chat logs or issue trackers
- Expose Ollama port (11434) directly to the internet

## Container Security

### Run as Non-Root (Future)

The current images run as root inside containers. For hardened deployments, consider:

- Custom Dockerfiles with non-root users
- Read-only root filesystems where supported
- Dropping unnecessary capabilities

### Docker Socket

Portainer mounts `/var/run/docker.sock`, which grants full Docker control. This is necessary for Portainer's functionality but represents a significant privilege. Mitigations:

- Restrict Portainer access (see above)
- Use Portainer's RBAC to limit what team members can do
- Consider Portainer Agent on a separate management host

### Image Pinning

The compose file uses `:latest` tags for convenience. For production, pin to specific versions:

```yaml
image: ollama/ollama:0.5.4
image: ghcr.io/open-webui/open-webui:v0.5.4
image: portainer/portainer-ce:2.21.4
```

## Model Security

- Only pull models from trusted sources (Ollama library)
- Verify model checksums when possible
- Be aware that LLM outputs can contain hallucinations — do not use for safety-critical decisions without verification
- Uploaded documents in Open WebUI are stored in the `webui_data` volume — encrypt at rest if handling sensitive data

## Monitoring

### Log Review

```bash
# Failed auth attempts in Open WebUI
docker compose logs open-webui | grep -i "auth\|login\|fail"

# API usage in LiteLLM
docker compose logs litellm | grep -i "error\|unauthorized"
```

### Resource Monitoring

Use Portainer's built-in stats or add Prometheus/Grafana for:

- CPU and memory usage per container
- GPU utilization
- API request rates
- Disk usage (model weights grow over time)

## Incident Response

If you suspect compromise:

1. Rotate all secrets in `.env` (API keys, passwords, secret keys)
2. Restart the stack: `./scripts/stop.sh && ./scripts/setup.sh`
3. Review Portainer audit logs
4. Check for unauthorized models: `docker exec obox-ollama ollama list`
5. Review Open WebUI user accounts

## Checklist

Before going to production:

- [ ] `.env` configured with unique secrets (not defaults)
- [ ] `WEBUI_ENABLE_SIGNUP=false`
- [ ] Strong admin passwords set
- [ ] DNS and TLS working
- [ ] Firewall allows only 80, 443, and SSH
- [ ] Portainer access restricted or VPN-only
- [ ] Image versions pinned
- [ ] Backups configured for `webui_data` and `ollama_data` volumes
- [ ] Monitoring in place
