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
| **PriceBuddy** | `https://pricebuddy.home.lan` | Price tracking & wishlist |
| **Apprise** | `https://apprise.home.lan` | Notification gateway |

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

1. Access AdGuard at `http://<server-ip>:3001`
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
├── portainer/        # Portainer data
├── pricebuddy/       # PriceBuddy MySQL & storage
├── prometheus/       # Prometheus metrics data
├── tailscale/        # Tailscale state
├── uptime-kuma/      # Uptime Kuma data
└── vaultwarden/      # Vaultwarden data & attachments
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

**Important directories to backup:**
- `./data/` - All service data
- `./configs/` - Service configurations
- `./.env` - Environment variables

Example backup script:
```bash
tar -czvf backup-$(date +%Y%m%d).tar.gz data/ configs/ .env
```

## Troubleshooting

### Services not accessible
1. Verify DNS resolution: `nslookup home.home.lan`
2. Check Traefik dashboard at `:8080`
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
