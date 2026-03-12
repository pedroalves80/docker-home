#!/bin/bash

# Pre-migration check script
# Run this BEFORE migrate-from-k3s.sh

echo "=========================================="
echo "Pre-Migration Checks"
echo "=========================================="
echo ""

FAIL=0

# Check 1: Docker installed
echo -n "Checking Docker... "
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | tr -d ',')
    echo "✓ Found ($DOCKER_VERSION)"
else
    echo "✗ NOT FOUND"
    echo "  Install: curl -fsSL https://get.docker.com | sudo sh"
    FAIL=1
fi

# Check 2: Docker Compose installed
echo -n "Checking Docker Compose... "
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short)
    echo "✓ Found ($COMPOSE_VERSION)"
else
    echo "✗ NOT FOUND"
    echo "  Install: sudo apt-get install -y docker-compose-plugin"
    FAIL=1
fi

# Check 3: User in docker group
echo -n "Checking docker group membership... "
if groups | grep -q docker; then
    echo "✓ User is in docker group"
else
    echo "✗ User NOT in docker group"
    echo "  Fix: sudo usermod -aG docker $USER"
    echo "  Then log out and back in"
    FAIL=1
fi

# Check 4: k3s running
echo -n "Checking k3s status... "
if sudo systemctl is-active --quiet k3s; then
    echo "✓ k3s is running"
else
    echo "⚠ k3s is NOT running (might be okay if already migrated)"
fi

# Check 5: Certificate files
echo -n "Checking certificates... "
if [ -f "configs/traefik/cert.pem" ] && [ -f "configs/traefik/key.pem" ]; then
    echo "✓ Found cert.pem and key.pem"
else
    echo "✗ Missing certificates"
    echo "  Generate with mkcert (see MIGRATION.md)"
    FAIL=1
fi

# Check 6: k3s data exists
echo -n "Checking k3s data directories... "
if sudo ls /var/lib/rancher/k3s/storage/pvc-* &> /dev/null; then
    PVC_COUNT=$(sudo ls -d /var/lib/rancher/k3s/storage/pvc-* 2>/dev/null | wc -l)
    echo "✓ Found $PVC_COUNT PVCs"
else
    echo "✗ No k3s PVCs found"
    echo "  Is k3s installed? Are services using PVCs?"
    FAIL=1
fi

# Check 7: Disk space
echo -n "Checking disk space... "
AVAILABLE_GB=$(df -BG . | tail -1 | awk '{print $4}' | tr -d 'G')
if [ "$AVAILABLE_GB" -gt 5 ]; then
    echo "✓ ${AVAILABLE_GB}GB available (need ~4GB for data)"
else
    echo "⚠ Only ${AVAILABLE_GB}GB available (need ~4GB)"
    echo "  Migration might fail due to low disk space"
    FAIL=1
fi

# Check 8: Root access
echo -n "Checking sudo access... "
if sudo -n true 2>/dev/null; then
    echo "✓ Passwordless sudo works"
else
    echo "⚠ Will need sudo password during migration"
fi

# Check 9: rsync installed
echo -n "Checking rsync... "
if command -v rsync &> /dev/null; then
    echo "✓ Found"
else
    echo "✗ NOT FOUND"
    echo "  Install: sudo apt-get install -y rsync"
    FAIL=1
fi

echo ""
echo "=========================================="
if [ $FAIL -eq 0 ]; then
    echo "✓ All checks passed!"
    echo ""
    echo "Ready to migrate. Run:"
    echo "  sudo ./migrate-from-k3s.sh"
else
    echo "✗ Some checks failed"
    echo ""
    echo "Fix the issues above, then re-run this script."
    exit 1
fi
echo "=========================================="
