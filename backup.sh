#!/bin/bash
# Docker Home Backup Script
set -e

# Set PATH for cron environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

BACKUP_DIR="/mnt/backups"
SOURCE_DIR="$HOME/docker-home"
DATE=$(date +%Y-%m-%d_%H-%M)
KEEP_DAYS=7
SNAPSHOT_DIR="$BACKUP_DIR/backup-$DATE"
REPO_BACKUP_DIR="$BACKUP_DIR/latest/_repo"
CONTAINERS_STOPPED=0

CRITICAL_CONTAINERS=(
    "vaultwarden"
    "teslamate_model3"
    "teslamate_modely"
    "homeassistant"
)

CONFIG_FILES=(
    ".env"
    ".env.example"
    "docker-compose.yml"
    "setup.sh"
    "backup.sh"
    "backup-status.sh"
    "weekly-storage-report.sh"
    "README.md"
    "AGENTS.md"
    "CLAUDE.md"
)

restart_containers() {
    if [ "$CONTAINERS_STOPPED" -eq 1 ]; then
        echo "Restarting containers..."
        docker compose start "${CRITICAL_CONTAINERS[@]}"
    fi
}

trap restart_containers EXIT

# Check if backup drive is mounted
if ! mountpoint -q "$BACKUP_DIR"; then
    echo "Backup drive not mounted!"
    exit 1
fi

# Stop containers that need consistent backups
cd "$SOURCE_DIR"
docker compose stop "${CRITICAL_CONTAINERS[@]}"
CONTAINERS_STOPPED=1

# Create backup with sudo
echo "Starting backup: $DATE"
sudo rsync -av --delete \
    --exclude "_repo/" \
    --exclude "*/logs/*" \
    --exclude "*/cache/*" \
    "$SOURCE_DIR/data/" "$BACKUP_DIR/latest/"

# Back up recovery-critical repo files separately so data restores stay unchanged.
sudo mkdir -p "$REPO_BACKUP_DIR"
sudo rsync -av --delete "$SOURCE_DIR/configs/" "$REPO_BACKUP_DIR/configs/"
for config_file in "${CONFIG_FILES[@]}"; do
    if [ -e "$SOURCE_DIR/$config_file" ]; then
        sudo rsync -av "$SOURCE_DIR/$config_file" "$REPO_BACKUP_DIR/"
    fi
done

# Copy to dated snapshot
sudo cp -al "$BACKUP_DIR/latest" "$SNAPSHOT_DIR"
sudo touch "$SNAPSHOT_DIR"

# Restart containers
docker compose start "${CRITICAL_CONTAINERS[@]}"
CONTAINERS_STOPPED=0

# Remove old backups
sudo find "$BACKUP_DIR" -maxdepth 1 -name "backup-*" -type d -mtime +$KEEP_DAYS -exec rm -rf {} \;

echo "Backup complete: $DATE"
