# Docker Home

A comprehensive Docker-based homelab stack featuring home automation, monitoring, password management, and Tesla vehicle tracking.

## Services

| Service | URL | Description |
|---------|-----|-------------|
| **Homepage** | `https://home.home.lan` | Dashboard with service overview |
| **Traefik** | `https://traefik.home.lan` | Reverse proxy dashboard |
| **Home Assistant** | `https://homeassistant.home.lan` | Home automation platform |
| **AdGuard Home** | `https://adguard.home.lan` | DNS-level ad blocking |
| **Grafana** | `https://grafana.home.lan` | Metrics visualization |
| **Vaultwarden** | `https://vaultwarden.home.lan` | Bitwarden-compatible password manager |
| **Portainer** | `https://portainer.home.lan` | Docker management UI |
| **Uptime Kuma** | `https://uptime.home.lan` | Uptime monitoring |
| **Prometheus** | `https://prometheus.home.lan` | Metrics collection |
| **cAdvisor** | `https://cadvisor.home.lan` | Container metrics |
| **Node Exporter** | `https://node-exporter.home.lan` | System metrics |
| **TeslaMate Model 3** | `https://teslamate-model3.home.lan` | Tesla Model 3 tracking |
| **TeslaMate Model Y** | `https://teslamate-modely.home.lan` | Tesla Model Y tracking |
| **Deye MQTT** | N/A (background service) | Solar inverter metrics bridge |
| **PriceBuddy** | `https://pricebuddy.home.lan` | Price tracking & wishlist |
| **Wishlist** | `https://wishlist.home.lan` | Buy-later wishlist |
| **Paperless-ngx** | `https://paperless.home.lan` | Document archive with OCR |
| **Apprise** | `https://apprise.home.lan` | Notification gateway |
| **Dozzle** | `https://dozzle.home.lan` | Real-time container logs |
| **Authelia** | `https://auth.home.lan` | SSO & 2FA gateway |
| **Diun** | N/A (background service) | Image update notifier |
| **n8n** | `https://n8n.home.lan` | Workflow automation |

## Prerequisites

- Docker Engine 20.10+
- Docker Compose v2.0+
- A DNS server (or `/etc/hosts` entries) pointing `*.home.lan` to your server

## Quick Start

```bash
# Clone the repository
git clone <repo-url> docker-home
cd docker-home

# Run the setup script
./setup.sh

# Start all services
docker compose up -d
```

## Configuration

### 1. Environment Variables

Copy the example environment file and customize it:

```bash
cp .env.example .env
```

**Required variables to change:**

| Variable | Description |
|----------|-------------|
| `TM3_ENCRYPTION_KEY` | TeslaMate Model 3 encryption key |
| `TMY_ENCRYPTION_KEY` | TeslaMate Model Y encryption key |
| `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin password |
| `VAULTWARDEN_ADMIN_TOKEN` | Vaultwarden admin panel token |
| `TS_AUTHKEY` | Tailscale auth key (from Tailscale admin console) |
| `PRICEBUDDY_APP_KEY` | PriceBuddy Laravel app key |
| `PAPERLESS_SECRET_KEY` | Paperless session/signing secret |
| `PAPERLESS_DB_PASS` | Paperless PostgreSQL password |
| `PAPERLESS_ADMIN_PASSWORD` | Initial Paperless admin password |
| `DEYE_LOGGER_IP_ADDRESS` | Deye/Solarman logger IP or DNS name |
| `DEYE_LOGGER_SERIAL_NUMBER` | Deye/Solarman logger serial number |
| `AUTHELIA_SESSION_SECRET` | Authelia session encryption key |
| `AUTHELIA_STORAGE_ENCRYPTION_KEY` | Authelia storage encryption key |
| `HOMEPAGE_VAR_*` | API keys for Homepage integrations |

Generate secure values:
```bash
# For encryption keys and tokens
openssl rand -base64 32

# For Vaultwarden admin token (use longer)
openssl rand -base64 48

# For Laravel app key (PriceBuddy)
echo "base64:$(openssl rand -base64 32)"
```

### 2. DNS Configuration

Add DNS entries pointing to your Docker host. If using AdGuard Home as your DNS:

1. Access AdGuard at `https://adguard.home.lan`
   - If AdGuard is not serving DNS yet, temporarily add `adguard.home.lan` to your client `/etc/hosts` file pointing at the server IP.
2. Go to **Filters** > **DNS rewrites**
3. Add: `*.home.lan` -> `<server-ip>`

Or add to `/etc/hosts` on client machines:
```
192.168.1.100  home.home.lan traefik.home.lan homeassistant.home.lan grafana.home.lan ...
```

### 3. TLS Certificates

The setup script generates self-signed certificates. For production use, consider:

- Using Let's Encrypt with Traefik's ACME provider
- Using a custom CA for your home network

To regenerate certificates:
```bash
./setup.sh --regenerate-certs
```

## Architecture

```
                    Internet
                        │
                        ▼
                   ┌─────────┐
                   │Tailscale│ (VPN Access)
                   └────┬────┘
                        │
        ┌───────────────┼───────────────┐
        │               ▼               │
        │         ┌─────────┐           │
        │         │ Traefik │ :80/:443  │
        │         └────┬────┘           │
        │              │                │
   ┌────┴────┬────┬────┴────┬────┬─────┴────┐
   ▼         ▼    ▼         ▼    ▼          ▼
┌──────┐ ┌─────┐ ┌────┐ ┌──────┐ ┌────┐ ┌──────┐
│Home  │ │Graf-│ │Vaul│ │Tesla │ │Port│ │ ...  │
│Assist│ │ana  │ │twar│ │Mate  │ │ainer│       │
└──────┘ └─────┘ └────┘ └──────┘ └────┘ └──────┘
```

## Data Persistence

All persistent data is stored in the `./data/` directory:

```
data/
├── adguard/          # AdGuard Home config & work files
├── apprise/          # Apprise notification configs
├── grafana/          # Grafana dashboards & data
├── homeassistant/    # Home Assistant configuration
├── model3/postgres/  # TeslaMate Model 3 database
├── modely/postgres/  # TeslaMate Model Y database
├── paperless/        # Paperless documents, metadata, and database
├── portainer/        # Portainer data
├── pricebuddy/       # PriceBuddy MySQL & storage
├── prometheus/       # Prometheus metrics data
├── tailscale/        # Tailscale state
├── uptime-kuma/      # Uptime Kuma data
├── vaultwarden/      # Vaultwarden data & attachments
└── wishlist/         # Wishlist SQLite data & uploads
```

## Useful Commands

```bash
# Start all services
docker compose up -d

# Stop all services
docker compose down

# View logs for a specific service
docker compose logs -f <service-name>

# Restart a specific service
docker compose restart <service-name>

# Update all images
docker compose pull && docker compose up -d

# Check service status
docker compose ps
```

## Backup

Automated backups run daily at 3am to a USB drive mounted at `/mnt/backups`.

**What's backed up:**
- `./data/` - Service data, excluding live TeslaMate and Paperless PostgreSQL directories
- Recovery config under `_repo/` inside each backup:
  - `.env`
  - `docker-compose.yml`
  - `backup.sh` and `backup-status.sh`
  - `setup.sh`
  - `configs/` including Traefik certificates and Authelia users
- PostgreSQL dumps under `_db_dumps/`:
  - `teslamate_model3.sql.gz`
  - `teslamate_modely.sql.gz`
  - `paperless.sql.gz`

**Backup features:**
- Briefly stops SQLite-backed containers (Vaultwarden, Home Assistant, Wishlist) only while their own data directories are copied
- Briefly stops Paperless while its document files are copied and its PostgreSQL database is dumped
- Leaves TeslaMate running and uses PostgreSQL dumps, so active charging sessions are not split by the 3am backup
- Excludes live TeslaMate and Paperless PostgreSQL data directories from snapshots; restore them from `_db_dumps/`
- Uses rsync with hard links for space-efficient snapshots
- Keeps 7 days of backups, auto-removes older ones

**Manual backup:**
```bash
./backup.sh
```

**Check backup status:**
```bash
sudo ls -la /mnt/backups/
sudo du -sh /mnt/backups/*
./backup-status.sh --summary
./backup-status.sh --json
./backup-status.sh --prometheus
```

For n8n, use this SSH command to return only the latest dated snapshot:
```bash
/home/yikeszs/docker-home/backup-status.sh --name
```

**Weekly storage report:**
```bash
./weekly-storage-report.sh --telegram-html
```

Use this from an n8n weekly SSH node and send `stdout` to Telegram with parse mode `HTML`. The script reports filesystem usage, backup size, Docker disk usage, largest service data directories, database/storage hotspots, and container restart counts. It stores its growth baseline in `data/report-state/storage-snapshot.tsv`, so the first run establishes the baseline and later runs show deltas.

**TeslaMate charge health check:**
```bash
./teslamate-charge-health.sh --json
```

Use this from an n8n SSH node to catch charge sessions split around the 3am backup window, or stale open charging processes. Alert when the returned top-level `status` is not `ok`.

**Deye solar MQTT bridge:**
```bash
docker compose logs -f deye-mqtt
docker compose exec mosquitto mosquitto_sub -C 10 -t 'deye/#'
```

The bridge reads the Deye/Solarman logger at `DEYE_LOGGER_IP_ADDRESS` and publishes read-only metrics to Mosquitto under `DEYE_MQTT_TOPIC_PREFIX`. Control/write features are disabled in Compose; enable them only after validating the readings and inverter behavior.

**Restore from backup:**
```bash
docker compose down
sudo rsync -av --exclude '_repo/' /mnt/backups/backup-YYYY-MM-DD_HH-MM/ ~/docker-home/data/
docker compose up -d
```

To restore repo config and secrets as well:
```bash
sudo rsync -av /mnt/backups/backup-YYYY-MM-DD_HH-MM/_repo/ ~/docker-home/
```

TeslaMate and Paperless database dumps are stored in `_db_dumps/` inside each backup snapshot. Use those dumps for restores instead of relying on a live rsync copy of PostgreSQL data directories.

## Troubleshooting

### Services not accessible
1. Verify DNS resolution: `nslookup home.home.lan`
2. Check Traefik dashboard at `https://traefik.home.lan`
3. Verify container status: `docker compose ps`

### Certificate warnings
Self-signed certificates will show browser warnings. Either:
- Accept the certificate in your browser
- Import the CA certificate to your system trust store
- Set up proper certificates with Let's Encrypt

### Container won't start
```bash
# Check logs
docker compose logs <service-name>

# Check if ports are in use
sudo lsof -i :80
sudo lsof -i :443
```

### TeslaMate not connecting
1. Ensure encryption key is set in `.env`
2. Check MQTT broker is running: `docker compose logs mosquitto`
3. Verify database connectivity

## License

MIT
