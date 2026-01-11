#!/bin/bash

# docker-home setup script
# Purpose: Initialize directories, permissions, and networks for first run.

echo "🚀 Starting docker-home setup..."

# 1. Create the Docker network if it doesn't exist
if ! docker network ls | grep -q "proxy_network"; then
  echo "🌐 Creating proxy_network..."
  docker network create proxy_network
else
  echo "✅ proxy_network already exists."
fi

# 2. Ensure data directories exist
echo "📁 Creating data directories..."
mkdir -p data/adguard/work data/adguard/conf
mkdir -p data/grafana
mkdir -p data/homeassistant
mkdir -p data/model3/postgres data/model3/import
mkdir -p data/modely/postgres data/modely/import
mkdir -p data/prometheus
mkdir -p data/tailscale
mkdir -p configs/traefik # Ensure this exists for certs

# 3. Ensure the TUN device exists (required for VPNs)
if [ ! -c /dev/net/tun ]; then
  echo "🔧 Creating TUN device..."
  sudo mkdir -p /dev/net/tun
  sudo mknod /dev/net/tun c 10 200
  sudo chmod 600 /dev/net/tun
fi

# 4. Handle .env file
if [ ! -f .env ]; then
  echo "📝 .env file not found. Copying from .env.example..."
  cp .env.example .env
  echo "⚠️  REMEMBER: Edit your .env file with real passwords before starting!"
else
  echo "✅ .env file already exists."
fi

# 5. Set Permissions
echo "🔐 Setting folder permissions..."
# Grafana needs UID 472
sudo chown -R 472:472 data/grafana
# General data folder permissions
sudo chmod -R 775 data/

echo ""
echo "✨ Setup complete!"
echo "Next steps:"
echo "1. Put your cert.pem and key.pem in configs/traefik/"
echo "2. Edit the .env file"
echo "3. Run 'docker compose up -d'"
