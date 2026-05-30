#!/bin/bash
set -e

BACKUP_DIR="${BACKUP_DIR:-/mnt/backups}"
MAX_AGE_HOURS="${MAX_AGE_HOURS:-26}"
FORMAT="${1:---summary}"

mounted=0
if mountpoint -q "$BACKUP_DIR" 2>/dev/null; then
    mounted=1
fi

latest_name=""
if [ -d "$BACKUP_DIR" ]; then
    latest_name=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "backup-*" -printf "%f\n" 2>/dev/null | sort -r | head -1 || true)
fi

latest_path=""
backup_date=""
snapshot_epoch=""
mtime_epoch=""
age_seconds=""
fresh=0
status="critical"

if [ -n "$latest_name" ]; then
    latest_path="$BACKUP_DIR/$latest_name"
    stamp="${latest_name#backup-}"

    if [[ "$stamp" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})_([0-9]{2})-([0-9]{2})$ ]]; then
        backup_date="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-${BASH_REMATCH[3]} ${BASH_REMATCH[4]}:${BASH_REMATCH[5]}"
        snapshot_epoch=$(date -d "$backup_date" +%s 2>/dev/null || true)
    fi

    mtime_epoch=$(stat -c "%Y" "$latest_path" 2>/dev/null || true)
    if [ -z "$snapshot_epoch" ]; then
        snapshot_epoch="$mtime_epoch"
        backup_date=$(date -d "@$snapshot_epoch" "+%Y-%m-%d %H:%M" 2>/dev/null || true)
    fi

    now_epoch=$(date +%s)
    age_seconds=$((now_epoch - snapshot_epoch))
    if [ "$age_seconds" -lt 0 ]; then
        age_seconds=0
    fi

    max_age_seconds=$((MAX_AGE_HOURS * 3600))
    if [ "$mounted" -eq 1 ] && [ "$age_seconds" -le "$max_age_seconds" ]; then
        status="ok"
        fresh=1
    elif [ "$mounted" -eq 1 ]; then
        status="warning"
    fi
fi

json_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

prom_label_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

print_summary() {
    if [ -z "$latest_name" ]; then
        echo "Backup status: $status"
        echo "Mounted: $mounted"
        echo "Latest snapshot: none"
        return
    fi

    age_hours=$((age_seconds / 3600))
    echo "Backup status: $status"
    echo "Mounted: $mounted"
    echo "Latest snapshot: $latest_name"
    echo "Backup date: $backup_date"
    echo "Age: ${age_hours}h"
    echo "Fresh: $fresh"
}

print_json() {
    escaped_name=$(json_escape "$latest_name")
    escaped_path=$(json_escape "$latest_path")
    escaped_date=$(json_escape "$backup_date")

    printf "{\n"
    printf "  \"status\": \"%s\",\n" "$status"
    printf "  \"mounted\": %s,\n" "$mounted"
    printf "  \"fresh\": %s,\n" "$fresh"
    printf "  \"latest_snapshot\": \"%s\",\n" "$escaped_name"
    printf "  \"latest_path\": \"%s\",\n" "$escaped_path"
    printf "  \"backup_date\": \"%s\",\n" "$escaped_date"
    if [ -n "$age_seconds" ]; then
        printf "  \"age_seconds\": %s,\n" "$age_seconds"
    else
        printf "  \"age_seconds\": null,\n"
    fi
    printf "  \"max_age_hours\": %s\n" "$MAX_AGE_HOURS"
    printf "}\n"
}

print_prometheus() {
    escaped_name=$(prom_label_escape "$latest_name")

    echo "# HELP docker_home_backup_drive_mounted Backup drive mount state."
    echo "# TYPE docker_home_backup_drive_mounted gauge"
    echo "docker_home_backup_drive_mounted $mounted"
    echo "# HELP docker_home_backup_latest_snapshot_present Whether a dated backup snapshot exists."
    echo "# TYPE docker_home_backup_latest_snapshot_present gauge"
    if [ -n "$latest_name" ]; then
        echo "docker_home_backup_latest_snapshot_present 1"
    else
        echo "docker_home_backup_latest_snapshot_present 0"
    fi
    echo "# HELP docker_home_backup_latest_snapshot_fresh Whether the latest snapshot is within MAX_AGE_HOURS."
    echo "# TYPE docker_home_backup_latest_snapshot_fresh gauge"
    echo "docker_home_backup_latest_snapshot_fresh{snapshot=\"$escaped_name\"} $fresh"
    echo "# HELP docker_home_backup_latest_snapshot_age_seconds Age of the latest dated backup snapshot."
    echo "# TYPE docker_home_backup_latest_snapshot_age_seconds gauge"
    if [ -n "$age_seconds" ]; then
        echo "docker_home_backup_latest_snapshot_age_seconds{snapshot=\"$escaped_name\"} $age_seconds"
    else
        echo "docker_home_backup_latest_snapshot_age_seconds{snapshot=\"$escaped_name\"} -1"
    fi
}

case "$FORMAT" in
    --name)
        echo "$latest_name"
        ;;
    --json)
        print_json
        ;;
    --prometheus)
        print_prometheus
        ;;
    --summary)
        print_summary
        ;;
    --help|-h)
        echo "Usage: $0 [--summary|--name|--json|--prometheus]"
        ;;
    *)
        echo "Unknown option: $FORMAT" >&2
        echo "Usage: $0 [--summary|--name|--json|--prometheus]" >&2
        exit 1
        ;;
esac
