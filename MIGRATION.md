# K3s to Docker Migration Guide

## Overview
This guide migrates your Raspberry Pi from k3s to Docker Compose while preserving all data.

**Total data to migrate: ~3.8GB**
- AdGuard: 2.1GB
- TeslaMate Model Y DB: 329MB
- TeslaMate Model 3 DB: 321MB
- TeslaMate backups: 1.1GB
- Grafana: 52MB
- Home Assistant: 7.8MB

---

## Pre-Migration Checklist

### 1. Install Docker & Docker Compose on your Pi

```bash
# Remove any old Docker packages
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to docker group
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt-get install -y docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

**Log out and back in** for group changes to take effect.

---

### 2. Generate HTTPS Certificates (mkcert)

On your **desktop/laptop** (not the Pi):

```bash
# Install mkcert (macOS example)
brew install mkcert

# Or on Linux:
# curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
# chmod +x mkcert-v*-linux-amd64
# sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

# Install root CA
mkcert -install

# Generate certificates
mkcert -cert-file cert.pem -key-file key.pem \
  traefik.local.lan \
  adguard.local.lan \
  grafana.local.lan \
  teslamate-model3.local.lan \
  teslamate-modely.local.lan \
  homeassistant.local.lan \
  vaultwarden.local.lan \
  prometheus.local.lan \
  cadvisor.local.lan
```

Copy `cert.pem` and `key.pem` to your Pi at `~/docker-home/configs/traefik/`

---

### 3. Clone This Repo on Your Pi

```bash
cd ~
git clone <your-repo-url> docker-home
cd docker-home
```

---

## Migration Steps

### Step 1: Run Migration Script

```bash
cd ~/docker-home
chmod +x migrate-from-k3s.sh
sudo ./migrate-from-k3s.sh
```

This will:
1. Stop k3s
2. Copy all data from k3s PVs to `data/` directories
3. Create `.env` file with your k3s credentials
4. Set correct permissions

**Duration: ~5-10 minutes** (mostly AdGuard copy)

---

### Step 2: Review & Edit .env

```bash
nano .env
```

**IMPORTANT:** Generate a new Vaultwarden admin token:

```bash
openssl rand -base64 48
```

Replace `CHANGEME_GENERATE_WITH_openssl_rand_base64_48` with the output.

---

### Step 3: Verify Certificate Files

```bash
ls -lh configs/traefik/
# Should show:
#   cert.pem
#   key.pem
#   traefik.yml
```

If missing, go back to **Pre-Migration Step 2**.

---

### Step 4: Create Docker Network

```bash
docker network create proxy_network
```

---

### Step 5: Start Docker Stack

```bash
cd ~/docker-home
docker compose up -d
```

---

### Step 6: Verify Services

Check all containers are running:

```bash
docker compose ps
```

**Expected output:** All services show "Up" status.

Test URLs (from any device using AdGuard DNS):
- https://traefik.local.lan (Traefik dashboard)
- https://adguard.local.lan (AdGuard Home)
- https://grafana.local.lan (Grafana)
- https://teslamate-modely.local.lan (TeslaMate Model Y)
- https://teslamate-model3.local.lan (TeslaMate Model 3)
- https://homeassistant.local.lan (Home Assistant)
- https://vaultwarden.local.lan (Vaultwarden)

---

### Step 7: Verify Data Integrity

#### Check TeslaMate Databases

```bash
# Model Y
docker exec teslamate_modely_db psql -U teslamate -d teslamate_modely -c "SELECT COUNT(*) FROM drives;"

# Model 3
docker exec teslamate_model3_db psql -U teslamate -d teslamate_model3 -c "SELECT COUNT(*) FROM drives;"
```

Should show your historical drive counts.

#### Check Grafana Dashboards

1. Go to https://grafana.local.lan
2. Login: `admin` / `admin` (change on first login)
3. Check that TeslaMate dashboards are loaded

#### Check Home Assistant

1. Go to https://homeassistant.local.lan
2. Verify your config is loaded (devices, automations, etc.)

#### Check AdGuard

1. Go to https://adguard.local.lan
2. Verify DNS rewrites are still configured
3. Check query logs show historical data

---

### Step 8: Update DNS (if using AdGuard LoadBalancer IP)

Your k3s AdGuard was at `10.10.99.242`. Now it's on the Pi's main IP.

**Update your router's DHCP settings** to point DNS to your Pi's IP (10.10.99.10).

**Or** keep using `10.10.99.242` by adding a static IP to your Pi's interface.

---

### Step 9: Only After Everything Works - Uninstall k3s

**DO NOT DO THIS UNTIL YOU'VE VERIFIED DOCKER STACK FOR AT LEAST 24 HOURS**

```bash
# Disable k3s service
sudo systemctl disable k3s --now

# Uninstall k3s
/usr/local/bin/k3s-uninstall.sh

# (Optional) Remove old PV data
sudo rm -rf /var/lib/rancher/k3s/storage/pvc-*
```

---

## Rollback Plan (If Something Goes Wrong)

If the Docker stack doesn't work, you can restart k3s:

```bash
sudo systemctl start k3s
kubectl get pods --all-namespaces
```

Your k3s data is still intact at `/var/lib/rancher/k3s/storage/`

---

## Differences from k3s Setup

| Feature | k3s | Docker |
|---------|-----|--------|
| Reverse Proxy | k3s Traefik (broken) | Traefik v2.10 |
| LoadBalancer | MetalLB | Host ports (80, 443, 53, 8123, etc.) |
| DNS IPs | 10.10.99.242 (AdGuard) | Pi IP (10.10.99.10) |
| Monitoring | Prometheus Operator | Prometheus + cAdvisor |
| Storage | k3s local-path PVCs | Docker bind mounts (`./data/`) |
| Grafana | 2 instances (1 broken) | 1 instance (TeslaMate) |

---

## Post-Migration Tasks

1. **Setup Tailscale VPN:**
   ```bash
   docker exec -it tailscale tailscale up
   # Follow the link to authenticate
   ```

2. **Configure AdGuard DNS Rewrites:**
   - Go to Filters → DNS Rewrites
   - Add entries pointing `*.local.lan` to your Pi's IP

3. **Backup Strategy:**
   - Your `data/` directory contains everything
   - Backup with: `tar -czf backup.tar.gz data/ configs/ .env`
   - Store off-Pi (NAS, cloud, etc.)

4. **Commit your config to git:**
   ```bash
   cd ~/docker-home
   git add .env configs/ docker-compose.yml
   git commit -m "Production config from k3s migration"
   git push
   ```

---

## Troubleshooting

### Containers won't start
```bash
docker compose logs <service-name>
```

### Permission errors (Grafana, PostgreSQL)
```bash
sudo chown -R 472:472 data/grafana
sudo chown -R 70:70 data/model3/postgres data/modely/postgres
```

### Port conflicts
```bash
# Check what's using a port
sudo netstat -tulpn | grep :80
sudo netstat -tulpn | grep :53
```

### Database connection errors
Check credentials in `.env` match what you extracted from k3s.

---

## Support

- **TeslaMate:** https://docs.teslamate.org
- **Traefik:** https://doc.traefik.io/traefik/
- **AdGuard Home:** https://github.com/AdguardTeam/AdGuardHome/wiki
- **Home Assistant:** https://www.home-assistant.io/docs/
