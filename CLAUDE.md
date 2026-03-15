# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Docker-based homelab stack with ~20 self-hosted services: home automation (Home Assistant), monitoring (Grafana/Prometheus), password management (Vaultwarden), Tesla tracking (TeslaMate), and more.

## Commands

```bash
# Initial setup (creates directories, .env, certs)
./setup.sh

# Regenerate TLS certificates
./setup.sh --regenerate-certs

# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs for specific service
docker compose logs -f <service-name>

# Update all images
docker compose pull && docker compose up -d

# Manual backup to /mnt/backups
./backup.sh
```

## Architecture

**Networking**: All services on `proxy_network` Docker bridge. Traefik routes `*.home.lan` requests to containers via Docker labels.

**Authentication**: Authelia provides SSO with policy tiers:
- `bypass`: Services with own auth (Vaultwarden, Home Assistant, n8n)
- `one_factor`: Dashboard services (Homepage, Grafana, Uptime Kuma)
- `two_factor`: Admin/sensitive services (Portainer, Traefik, TeslaMate)

**TLS**: Self-signed wildcard certificate for `*.home.lan` in `configs/traefik/`.

## File Structure

- `docker-compose.yml` - All service definitions with Traefik labels
- `.env` / `.env.example` - Secrets and configuration (encryption keys, passwords, API keys)
- `configs/` - Static configuration files (Traefik, Prometheus, Homepage, Authelia, Diun)
- `data/` - Persistent service data (databases, state files) - gitignored except `traefik/acme.json`
- `setup.sh` - First-run setup script
- `backup.sh` - Backup script (stops critical containers, rsync to USB drive)

## Service Patterns

When adding a new service to `docker-compose.yml`:
1. Add to `proxy` network
2. Set `traefik.enable=true` label
3. Configure router rule: `Host(\`servicename.home.lan\`)`
4. Set entrypoints to `websecure` with `tls=true`
5. Add `authelia@docker` middleware if SSO protection needed
6. Update `configs/authelia/configuration.yml` access_control rules if needed

## Key Integrations

- **Mosquitto**: MQTT broker shared by both TeslaMate instances
- **Diun**: Monitors all containers for image updates, notifies via Telegram
- **Tailscale**: VPN with subnet routing (10.10.99.0/24) and exit node
- **Apprise**: Notification gateway for services like PriceBuddy
