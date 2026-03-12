#!/bin/bash
set -e

# K3s to Docker Migration Script
# This script migrates data from k3s PVs to docker-home structure

echo "=========================================="
echo "K3s → Docker Migration Script"
echo "=========================================="
echo ""
echo "This will:"
echo "  1. Stop k3s services"
echo "  2. Copy data from k3s PVs to docker-home/data/"
echo "  3. Create .env file with your k3s credentials"
echo "  4. Set proper permissions"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# Get the directory where this script lives
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo ""
echo "==> Stopping k3s..."
sudo systemctl stop k3s

echo ""
echo "==> Creating data directories..."
mkdir -p data/{adguard/{work,conf},grafana,homeassistant,model3/postgres,modely/postgres,vaultwarden,prometheus,tailscale}
mkdir -p configs/mosquitto

echo ""
echo "==> Copying AdGuard data (2.1GB - this may take a minute)..."
sudo rsync -av --info=progress2 \
  /var/lib/rancher/k3s/storage/pvc-6469919a-fa9a-4d19-a4be-098c434aa845_adguard_adguard-storage/ \
  data/adguard/

echo ""
echo "==> Copying Home Assistant data (7.8MB)..."
sudo rsync -av \
  /var/lib/rancher/k3s/storage/pvc-9e07535c-abd1-42d5-ac85-a942d51e34d9_default_home-assistant-config/ \
  data/homeassistant/

echo ""
echo "==> Copying TeslaMate Model Y DB (329MB)..."
sudo rsync -av --info=progress2 \
  /var/lib/rancher/k3s/storage/pvc-68c8677b-59d4-418c-b90e-bb66054e3d2d_teslamate_teslamate-db/ \
  data/modely/postgres/

echo ""
echo "==> Copying TeslaMate Model 3 DB (321MB)..."
sudo rsync -av --info=progress2 \
  /var/lib/rancher/k3s/storage/pvc-1fa7864e-9d60-4e9a-8845-62bd0aa550c6_tesla-m3_m3-postgres-db/ \
  data/model3/postgres/

echo ""
echo "==> Copying Grafana data (52MB)..."
sudo rsync -av \
  /var/lib/rancher/k3s/storage/pvc-9ffd1880-61da-4006-8307-c6b00652aa4f_teslamate_grafana-storage/ \
  data/grafana/

echo ""
echo "==> Copying TeslaMate backups (1.1GB)..."
sudo rsync -av --info=progress2 \
  /var/lib/rancher/k3s/storage/pvc-e5794c92-1268-40e3-867a-de4f5dace63d_teslamate_teslamate-backup/ \
  data/modely/backups/

echo ""
echo "==> Creating mosquitto config..."
cat > configs/mosquitto/mosquitto.conf <<'EOF'
# Listen on all interfaces
listener 1883 0.0.0.0
allow_anonymous true

# WebSockets (optional, if you need it)
listener 9001 0.0.0.0
protocol websockets
EOF

echo ""
echo "==> Creating .env file with your k3s credentials..."
cat > .env <<'EOF'
# Model 3 instance
TM3_DB_USER=teslamate
TM3_DB_PASS=[teslamatedb]
TM3_DB_NAME=teslamate_model3
TM3_ENCRYPTION_KEY=qCXGKw1Kw1YtOZD/opMuDGLIFxNw457jDfmD9qKlf28=

# Model Y instance
TMY_DB_USER=teslamate
TMY_DB_PASS=teslamatepass
TMY_DB_NAME=teslamate_modely
TMY_ENCRYPTION_KEY=qCXGKw1Kw1YtOZD/opMuDGLIFxNw457jDfmD9qKlf28=

# Grafana
GF_SECURITY_ADMIN_PASSWORD=admin

# Vaultwarden (Password Manager)
VAULTWARDEN_ADMIN_TOKEN=CHANGEME_GENERATE_WITH_openssl_rand_base64_48

# Global
TZ=Europe/Lisbon
EOF

echo ""
echo "==> Fixing ownership (grafana needs UID 472)..."
sudo chown -R 472:472 data/grafana
sudo chown -R 70:70 data/model3/postgres data/modely/postgres

echo ""
echo "==> Setting permissions..."
sudo chmod -R 755 data/

echo ""
echo "=========================================="
echo "Migration Complete!"
echo "=========================================="
echo ""
echo "Data locations:"
echo "  AdGuard:         $(du -sh data/adguard 2>/dev/null | cut -f1)"
echo "  Home Assistant:  $(du -sh data/homeassistant 2>/dev/null | cut -f1)"
echo "  Model Y DB:      $(du -sh data/modely/postgres 2>/dev/null | cut -f1)"
echo "  Model 3 DB:      $(du -sh data/model3/postgres 2>/dev/null | cut -f1)"
echo "  Grafana:         $(du -sh data/grafana 2>/dev/null | cut -f1)"
echo ""
echo "Next steps:"
echo "  1. Review .env file (especially VAULTWARDEN_ADMIN_TOKEN)"
echo "  2. Generate mkcert certificates (see README.md)"
echo "  3. Run: docker compose up -d"
echo "  4. Verify all services work"
echo "  5. ONLY THEN: sudo systemctl disable k3s --now"
echo "  6. ONLY THEN: /usr/local/bin/k3s-uninstall.sh"
echo ""
echo "IMPORTANT: Keep k3s around until you verify Docker stack works!"
echo ""
