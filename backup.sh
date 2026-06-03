#!/bin/bash
# Docker Home Backup Script
set -e
set -o pipefail

# Set PATH for cron environment
export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"

BACKUP_DIR="/mnt/backups"
SOURCE_DIR="$HOME/docker-home"
DATE=$(date +%Y-%m-%d_%H-%M)
KEEP_DAYS=7
SNAPSHOT_DIR="$BACKUP_DIR/backup-$DATE"
REPO_BACKUP_DIR="$BACKUP_DIR/latest/_repo"
DB_DUMP_DIR="$BACKUP_DIR/latest/_db_dumps"
CONTAINERS_STOPPED=0

CRITICAL_CONTAINERS=(
    "vaultwarden"
    "homeassistant"
    "wishlist"
)

POSTGRES_DUMPS=(
    "teslamate_model3_db:teslamate_model3.sql.gz"
    "teslamate_modely_db:teslamate_modely.sql.gz"
)

LIVE_POSTGRES_BACKUP_DIRS=(
    "model3/postgres"
    "modely/postgres"
)

STOPPED_DATA_DIRS=(
    "homeassistant"
    "vaultwarden"
    "wishlist"
)

CONFIG_FILES=(
    ".env"
    ".env.example"
    "docker-compose.yml"
    "setup.sh"
    "backup.sh"
    "backup-status.sh"
    "teslamate-charge-health.sh"
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

is_service_running() {
    local service_name="$1"

    docker compose ps --status running --services | grep -qx "$service_name"
}

dump_postgres_db() {
    local service_name="$1"
    local dump_file="$2"
    local target_file="$DB_DUMP_DIR/$dump_file"
    local temp_file="$target_file.tmp"

    if ! is_service_running "$service_name"; then
        echo "Skipping PostgreSQL dump for $service_name; service is not running."
        return
    fi

    echo "Dumping PostgreSQL database: $service_name"
    sudo rm -f "$temp_file"
    docker compose exec -T "$service_name" sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' \
        | gzip \
        | sudo tee "$temp_file" > /dev/null
    sudo mv "$temp_file" "$target_file"
}

remove_live_postgres_backups() {
    local backup_path=""

    for backup_path in "${LIVE_POSTGRES_BACKUP_DIRS[@]}"; do
        sudo rm -rf "$BACKUP_DIR/latest/$backup_path"
    done
}

sync_stopped_data_dirs() {
    local data_path=""

    for data_path in "${STOPPED_DATA_DIRS[@]}"; do
        sudo mkdir -p "$BACKUP_DIR/latest/$data_path"
        sudo rsync -av --delete "$SOURCE_DIR/data/$data_path/" "$BACKUP_DIR/latest/$data_path/"
    done
}

trap restart_containers EXIT

# Check if backup drive is mounted
if ! mountpoint -q "$BACKUP_DIR"; then
    echo "Backup drive not mounted!"
    exit 1
fi

cd "$SOURCE_DIR"

echo "Starting backup: $DATE"

# Copy data that can be backed up while services continue running.
sudo rsync -av --delete \
    --exclude "_repo/" \
    --exclude "_db_dumps/" \
    --exclude "homeassistant/" \
    --exclude "vaultwarden/" \
    --exclude "wishlist/" \
    --exclude "model3/postgres/" \
    --exclude "modely/postgres/" \
    --exclude "*/logs/*" \
    --exclude "*/cache/*" \
    "$SOURCE_DIR/data/" "$BACKUP_DIR/latest/"

# Excludes are protected from --delete, so remove old live PostgreSQL copies.
remove_live_postgres_backups

# Stop SQLite-backed services only long enough to copy their own data dirs.
docker compose stop "${CRITICAL_CONTAINERS[@]}"
CONTAINERS_STOPPED=1
sync_stopped_data_dirs
docker compose start "${CRITICAL_CONTAINERS[@]}"
CONTAINERS_STOPPED=0

# Keep consistent database exports for services backed by live PostgreSQL.
sudo mkdir -p "$DB_DUMP_DIR"
for dump_config in "${POSTGRES_DUMPS[@]}"; do
    dump_postgres_db "${dump_config%%:*}" "${dump_config#*:}"
done

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

# Remove old backups
sudo find "$BACKUP_DIR" -maxdepth 1 -name "backup-*" -type d -mtime +$KEEP_DAYS -exec rm -rf {} \;

echo "Backup complete: $DATE"
