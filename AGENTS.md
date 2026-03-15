# AGENTS.md

This file provides guidance for AI coding agents working with this Docker homelab infrastructure.

## Project Overview

Docker-based homelab with ~20 self-hosted services including Traefik reverse proxy, Authelia SSO, Home Assistant, TeslaMate (dual instances), monitoring stack (Grafana/Prometheus), Vaultwarden, and more. All services route through Traefik on `*.home.lan` domains with TLS and optional Authelia authentication.

## Commands

### Setup & Initialization
```bash
# First-time setup (creates dirs, .env, certs)
./setup.sh

# Regenerate TLS certificates only
./setup.sh --regenerate-certs
```

### Docker Compose Operations
```bash
# Start all services
docker compose up -d

# Start specific service
docker compose up -d <service-name>

# Stop all services
docker compose down

# Restart specific service
docker compose restart <service-name>

# Update all images and recreate containers
docker compose pull && docker compose up -d

# View logs (all services)
docker compose logs -f

# View logs (single service)
docker compose logs -f <service-name>

# Check container status
docker compose ps

# Remove stopped containers and orphaned volumes
docker compose down -v
```

### Backup & Maintenance
```bash
# Manual backup to /mnt/backups
./backup.sh

# Check Docker disk usage
docker system df

# Prune unused resources (careful!)
docker system prune -a
```

### Debugging
```bash
# Inspect container
docker inspect <container-name>

# Shell into running container
docker exec -it <container-name> /bin/sh

# Check network connectivity
docker network inspect proxy_network

# Validate compose file syntax
docker compose config
```

## Code Style Guidelines

### Shell Scripts (Bash)

**Formatting:**
- 4-space indentation (not tabs)
- `#!/bin/bash` shebang with `set -e` for error handling
- UPPER_CASE for constants/env vars, lower_case for local vars
- Use functions for reusability: `function_name() { ... }`

**Error Handling:**
- Always use `set -e` at script start
- Check command existence: `command -v <cmd> &> /dev/null`
- Print colored output for user feedback (RED/GREEN/YELLOW/BLUE)
- Exit with non-zero status on errors

**Style:**
```bash
#!/bin/bash
set -e

# Constants
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="/mnt/backups"

# Functions use snake_case
check_prerequisites() {
    if ! command -v docker &> /dev/null; then
        echo "Docker not installed"
        exit 1
    fi
}
```

### Docker Compose

**Service Definition Pattern:**
```yaml
service-name:
  image: vendor/image:version
  container_name: service-name
  networks:
    - proxy
  restart: unless-stopped
  volumes:
    - ./data/service:/container/path
    - ./configs/service:/config:ro
  environment:
    - TZ=${TZ:-UTC}
    - SERVICE_VAR=${ENV_VAR}
  labels:
    - "traefik.enable=true"
    - "traefik.http.routers.service.rule=Host(`service.home.lan`)"
    - "traefik.http.services.service.loadbalancer.server.port=8080"
    - "traefik.http.routers.service.entrypoints=websecure"
    - "traefik.http.routers.service.tls=true"
    # Add for SSO protection:
    - "traefik.http.routers.service.middlewares=authelia@docker"
```

**Naming Conventions:**
- Container names: lowercase with hyphens (e.g., `teslamate-model3`)
- Service names in compose: match container names
- Volume paths: `./data/<service>/<subdir>` or `./configs/<service>/`
- Network: all services use `proxy` network
- Environment vars: UPPER_CASE with service prefix (e.g., `TM3_DB_USER`)

**Labels (Traefik):**
- Always set `traefik.enable=true` explicitly
- Router rule: `Host(\`servicename.home.lan\`)`
- Use backticks inside Host() for proper escaping
- Entrypoint: always `websecure` with `tls=true`
- Service port: specify container's internal port
- Add `authelia@docker` middleware for SSO (based on access_control policy)

### YAML Configuration Files

**Style:**
- 2-space indentation (Prometheus, Traefik, Homepage)
- Keys: lowercase with underscores (e.g., `scrape_interval`)
- Boolean values: `true`/`false` (not yes/no)
- Strings: unquoted unless containing special chars
- Comments: use `#` with space, explain WHY not WHAT

**Example (Prometheus):**
```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

scrape_configs:
  - job_name: 'service-name'
    static_configs:
      - targets: ['service:9090']
```

### Environment Variables

**Secrets Management:**
- NEVER commit `.env` file (gitignored)
- Update `.env.example` with new variable names (use placeholder values)
- Document secret generation in comments:
  ```bash
  # Generate with: openssl rand -hex 32
  AUTHELIA_SESSION_SECRET=changeme_session_secret_64chars
  ```

**Naming:**
- Service-specific vars: `<SERVICE>_<PROPERTY>` (e.g., `TM3_DB_USER`)
- Global vars: descriptive names (e.g., `TZ`, `BACKUP_DIR`)
- Use defaults in compose: `${VAR:-default_value}`

### File Organization

```
docker-home/
├── docker-compose.yml        # All service definitions
├── .env                       # Secrets (gitignored)
├── .env.example               # Template with placeholders
├── setup.sh                   # First-run setup script
├── backup.sh                  # Backup automation
├── configs/                   # Static config files (some gitignored)
│   ├── traefik/
│   │   ├── traefik.yml
│   │   ├── cert.pem          # gitignored
│   │   └── key.pem           # gitignored
│   ├── authelia/
│   ├── prometheus/
│   ├── homepage/
│   └── mosquitto/
└── data/                      # Persistent data (gitignored)
    ├── service1/
    ├── service2/
    └── ...
```

## Architecture Patterns

### Adding a New Service

1. **Add to docker-compose.yml:**
   - Define service with image, container_name, network, restart policy
   - Mount volumes: `./data/<service>` and `./configs/<service>`
   - Set environment variables (reference `.env`)
   - Add Traefik labels (see pattern above)

2. **Update configs:**
   - Add directory creation to `setup.sh` `directories` array
   - If needs config file, add default generation to `create_default_configs()`
   - Update `configs/homepage/services.yaml` for dashboard

3. **Update .env.example:**
   - Add any new environment variables with placeholder values
   - Document secret generation commands in comments

4. **Authelia access control:**
   - Edit `configs/authelia/configuration.yml` to set policy:
     - `bypass`: services with own auth (Vaultwarden, Home Assistant)
     - `one_factor`: dashboard services (Grafana, Homepage)
     - `two_factor`: admin/sensitive (Portainer, Traefik, TeslaMate)

### Networking

- All services on `proxy_network` Docker bridge
- Traefik handles routing via Docker provider (reads labels)
- Internal DNS: containers communicate by service name (e.g., `http://authelia:9091`)
- External access: `https://<service>.home.lan` (DNS must point to host)

### TLS Certificates

- Self-signed wildcard cert for `*.home.lan`
- Generated by `setup.sh`, stored in `configs/traefik/`
- Regenerate with: `./setup.sh --regenerate-certs`
- Valid for 10 years (3650 days)

### Backup Strategy

- `backup.sh` stops critical containers before backup (data consistency)
- Uses `rsync --delete` to `/mnt/backups/latest/`
- Creates hard-linked snapshots: `backup-YYYY-MM-DD_HH-MM`
- Retains last 7 days of backups
- Automatically prunes old backups

## Safety & Best Practices

**Security:**
- Never commit `.env` file or TLS private keys
- Use strong random secrets (generate with `openssl rand -hex 32`)
- Review Authelia policies before exposing services
- Keep images updated: `docker compose pull` regularly

**Testing Changes:**
- Validate compose syntax: `docker compose config`
- Test single service: `docker compose up <service>`
- Check logs after changes: `docker compose logs -f <service>`
- Verify Traefik routing: check `https://traefik.home.lan` dashboard

**Maintenance:**
- Monitor Diun notifications for image updates
- Check disk usage: `docker system df`
- Review logs periodically for errors
- Test backup/restore process

**Git Workflow:**
- Commit config changes to track history
- Never commit secrets or generated certs
- Update `.env.example` when adding variables
- Document breaking changes in commit messages

## Common Tasks

**Add Environment Variable:**
1. Add to `.env.example` with placeholder
2. Reference in `docker-compose.yml`: `${VAR_NAME}`
3. Update actual `.env` with real value
4. Restart affected service: `docker compose up -d <service>`

**Update Service Image:**
1. Edit `image:` tag in `docker-compose.yml`
2. Pull new image: `docker compose pull <service>`
3. Recreate container: `docker compose up -d <service>`
4. Check logs: `docker compose logs -f <service>`

**Troubleshoot Service:**
1. Check status: `docker compose ps <service>`
2. View logs: `docker compose logs -f <service>`
3. Inspect config: `docker inspect <container-name>`
4. Test connectivity: `docker exec -it <service> /bin/sh`
5. Verify Traefik routing: check dashboard at `https://traefik.home.lan`

**Migrate to New Host:**
1. Backup data: `./backup.sh`
2. Copy `docker-home/` directory to new host
3. Copy `.env` file (contains secrets)
4. Run `./setup.sh` on new host
5. Start services: `docker compose up -d`

## Service-Specific Notes

**Grafana:**
- Runs as UID 472, needs proper permissions (`setup.sh` handles this)
- Data in `data/grafana/`
- Admin password: `GF_SECURITY_ADMIN_PASSWORD` in `.env`

**TeslaMate (dual instances):**
- Model 3 and Model Y each have separate database + app containers
- Share MQTT broker (Mosquitto)
- Separate encryption keys and DB credentials

**Authelia:**
- SSO/2FA provider for all services
- Middleware: `authelia@docker` in Traefik labels
- Access policies in `configs/authelia/configuration.yml`

**Tailscale:**
- VPN with subnet routing (10.10.99.0/24)
- Exit node capability
- Auth key in `.env`: `TS_AUTHKEY`
