#!/bin/bash
# Docker Home Backup Script

BACKUP_DIR="/mnt/backups"
SOURCE_DIR="$HOME/docker-home"
DATE=$(date +%Y-%m-%d_%H-%M)
KEEP_DAYS=7

# Check if backup drive is mounted
if ! mountpoint -q "$BACKUP_DIR"; then
    echo "Backup drive not mounted!"
    exit 1
fi

# Stop containers that need consistent backups
cd "$SOURCE_DIR"
docker compose stop vaultwarden teslamate_model3 teslamate_modely homeassistant

# Create backup with sudo
echo "Starting backup: $DATE"
sudo rsync -av --delete \
    --exclude "*/logs/*" \
    --exclude "*/cache/*" \
    "$SOURCE_DIR/data/" "$BACKUP_DIR/latest/"

# Copy to dated snapshot
sudo cp -al "$BACKUP_DIR/latest" "$BACKUP_DIR/backup-$DATE"

# Restart containers
docker compose start vaultwarden teslamate_model3 teslamate_modely homeassistant

# Remove old backups
sudo find "$BACKUP_DIR" -maxdepth 1 -name "backup-*" -type d -mtime +$KEEP_DAYS -exec rm -rf {} \;

echo "Backup complete: $DATE"
