#!/bin/bash
set -e

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export TZ="${TZ:-Europe/Lisbon}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR/data}"
BACKUP_DIR="${BACKUP_DIR:-/mnt/backups}"
STATE_DIR="${STORAGE_REPORT_STATE_DIR:-$DATA_DIR/report-state}"
STATE_FILE="$STATE_DIR/storage-snapshot.tsv"
TOP_N="${TOP_N:-10}"
FORMAT="telegram"
SAVE_STATE=1

while [ "$#" -gt 0 ]; do
    case "$1" in
        --telegram)
            FORMAT="telegram"
            ;;
        --telegram-html|--html)
            FORMAT="telegram_html"
            ;;
        --no-save)
            SAVE_STATE=0
            ;;
        --help|-h)
            echo "Usage: $0 [--telegram|--telegram-html] [--no-save]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--telegram|--telegram-html] [--no-save]" >&2
            exit 1
            ;;
    esac
    shift
done

mkdir -p "$STATE_DIR"
CURRENT_FILE="$(mktemp)"
trap 'rm -f "$CURRENT_FILE"' EXIT

can_sudo() {
    sudo -n true 2>/dev/null
}

human_bytes() {
    local bytes="${1:-0}"

    if command -v numfmt >/dev/null 2>&1; then
        numfmt --to=iec --suffix=B --format="%.1f" "$bytes" | sed 's/\.0//'
    else
        awk -v bytes="$bytes" '
            BEGIN {
                split("B KB MB GB TB PB", unit, " ");
                value = bytes;
                idx = 1;
                while (value >= 1024 && idx < 6) {
                    value = value / 1024;
                    idx++;
                }
                if (idx == 1) {
                    printf "%d%s", value, unit[idx];
                } else {
                    printf "%.1f%s", value, unit[idx];
                }
            }
        '
    fi
}

html_escape() {
    sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

du_bytes() {
    local path="$1"
    local kb=""

    if [ ! -e "$path" ]; then
        echo 0
        return
    fi

    if can_sudo; then
        kb="$(sudo -n du -sk "$path" 2>/dev/null | awk '{print $1}')"
    else
        kb="$(du -sk "$path" 2>/dev/null | awk '{print $1}')"
    fi

    if [ -z "$kb" ]; then
        echo 0
    else
        echo $((kb * 1024))
    fi
}

record_size() {
    local key="$1"
    local bytes="$2"

    printf "%s\t%s\n" "$key" "$bytes" >> "$CURRENT_FILE"
}

previous_bytes() {
    local key="$1"

    if [ ! -f "$STATE_FILE" ]; then
        return
    fi

    awk -F '\t' -v key="$key" '$1 == key { value = $2 } END { if (value != "") print value }' "$STATE_FILE"
}

format_delta() {
    local key="$1"
    local current="$2"
    local previous=""
    local delta=0

    previous="$(previous_bytes "$key")"
    if [ -z "$previous" ]; then
        echo "baseline"
        return
    fi

    delta=$((current - previous))
    if [ "$delta" -gt 0 ]; then
        echo "+$(human_bytes "$delta")"
    elif [ "$delta" -lt 0 ]; then
        delta=$((delta * -1))
        echo "-$(human_bytes "$delta")"
    else
        echo "0B"
    fi
}

safe_key() {
    printf "%s" "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9._/-]/-/g; s/--*/-/g; s/^-//; s/-$//'
}

print_size_line() {
    local key="$1"
    local label="$2"
    local bytes="$3"
    local delta=""

    delta="$(format_delta "$key" "$bytes")"
    printf "  - %s: %s (%s)\n" "$label" "$(human_bytes "$bytes")" "$delta"
}

print_size_row() {
    local key="$1"
    local label="$2"
    local bytes="$3"
    local delta=""

    delta="$(format_delta "$key" "$bytes")"
    printf "%-18s %8s %8s\n" "$label" "$(human_bytes "$bytes")" "$delta"
}

collect_data_sizes() {
    local path=""
    local service=""
    local bytes=0

    if [ ! -d "$DATA_DIR" ]; then
        return
    fi

    while IFS= read -r path; do
        service="$(basename "$path")"
        bytes="$(du_bytes "$path")"
        record_size "data/$service" "$bytes"
    done < <(find "$DATA_DIR" -mindepth 1 -maxdepth 1 -type d ! -name "report-state" | sort)

    bytes="$(du_bytes "$DATA_DIR")"
    record_size "total/data" "$bytes"
}

collect_backup_sizes() {
    local bytes=0

    if [ -d "$BACKUP_DIR/latest" ]; then
        bytes="$(du_bytes "$BACKUP_DIR/latest")"
        record_size "backup/latest" "$bytes"
    fi

    if [ -d "$BACKUP_DIR" ]; then
        bytes="$(du_bytes "$BACKUP_DIR")"
        record_size "backup/all" "$bytes"
    fi
}

collect_database_sizes() {
    local item=""
    local label=""
    local path=""
    local key=""
    local bytes=0

    while IFS='|' read -r label path; do
        if [ -z "$label" ] || [ -z "$path" ] || [ ! -e "$path" ]; then
            continue
        fi

        key="db/$(safe_key "$label")"
        bytes="$(du_bytes "$path")"
        record_size "$key" "$bytes"
    done << EOF
Vaultwarden DB|$DATA_DIR/vaultwarden/db.sqlite3
Home Assistant DB|$DATA_DIR/homeassistant/home-assistant_v2.db
n8n SQLite|$DATA_DIR/n8n/database.sqlite
Uptime Kuma DB|$DATA_DIR/uptime-kuma/kuma.db
Grafana DB|$DATA_DIR/grafana/grafana.db
Diun DB|$DATA_DIR/diun/diun.db
Wishlist SQLite|$DATA_DIR/wishlist/data/prod.db
PriceBuddy MySQL|$DATA_DIR/pricebuddy/mysql
TeslaMate Model 3 Postgres|$DATA_DIR/model3/postgres
TeslaMate Model Y Postgres|$DATA_DIR/modely/postgres
Prometheus TSDB|$DATA_DIR/prometheus
EOF
}

print_filesystems() {
    local path=""
    local label=""

    echo "Filesystems:"
    while IFS='|' read -r label path; do
        if [ -d "$path" ] || [ -f "$path" ]; then
            df -h -P "$path" | awk -v label="$label" 'NR == 2 { printf "  - %s: %s used (%s/%s)\n", label, $5, $3, $2 }'
        fi
    done << EOF
Root|/
Service data|$DATA_DIR
Docker engine|/var/lib/docker
Backups|$BACKUP_DIR
EOF
}

print_filesystems_table() {
    local path=""
    local label=""

    while IFS='|' read -r label path; do
        if [ -d "$path" ] || [ -f "$path" ]; then
            df -h -P "$path" | awk -v label="$label" 'NR == 2 { printf "%-14s %4s %9s/%s\n", label, $5, $3, $2 }'
        fi
    done << EOF
Root|/
Service data|$DATA_DIR
Docker engine|/var/lib/docker
Backups|$BACKUP_DIR
EOF
}

print_backup_status() {
    echo "Backup:"
    if [ -x "$SCRIPT_DIR/backup-status.sh" ]; then
        "$SCRIPT_DIR/backup-status.sh" --summary | sed 's/^/  /'
    else
        echo "  backup-status.sh not found"
    fi

    if grep -q '^backup/latest[[:space:]]' "$CURRENT_FILE"; then
        bytes="$(awk -F '\t' '$1 == "backup/latest" { print $2 }' "$CURRENT_FILE")"
        print_size_line "backup/latest" "latest backup size" "$bytes"
    fi
}

print_backup_table() {
    local size_bytes=""
    local size_delta=""

    if [ -x "$SCRIPT_DIR/backup-status.sh" ]; then
        "$SCRIPT_DIR/backup-status.sh" --summary \
            | awk -F ': ' '
                $1 == "Backup status" { printf "%-9s %s\n", "Status", $2 }
                $1 == "Mounted" { printf "%-9s %s\n", "Mounted", $2 }
                $1 == "Latest snapshot" { printf "%-9s %s\n", "Latest", $2 }
                $1 == "Backup date" { printf "%-9s %s\n", "Date", $2 }
                $1 == "Age" { printf "%-9s %s\n", "Age", $2 }
                $1 == "Fresh" { printf "%-9s %s\n", "Fresh", $2 }
            '
    else
        echo "backup-status.sh not found"
    fi

    if grep -q '^backup/latest[[:space:]]' "$CURRENT_FILE"; then
        size_bytes="$(awk -F '\t' '$1 == "backup/latest" { print $2 }' "$CURRENT_FILE")"
        size_delta="$(format_delta "backup/latest" "$size_bytes")"
        printf "%-9s %s (%s)\n" "Size" "$(human_bytes "$size_bytes")" "$size_delta"
    fi
}

print_docker_summary() {
    echo "Docker disk usage:"
    if command -v docker >/dev/null 2>&1; then
        docker system df 2>/dev/null | sed 's/^/  /' || echo "  docker system df unavailable"
    else
        echo "  docker not installed"
    fi
}

print_docker_table() {
    if command -v docker >/dev/null 2>&1; then
        docker system df 2>/dev/null || echo "docker system df unavailable"
    else
        echo "docker not installed"
    fi
}

print_top_data_dirs() {
    echo "Largest service data directories:"
    awk -F '\t' '$1 ~ /^data\// { print $2 "\t" $1 }' "$CURRENT_FILE" \
        | sort -rn \
        | head -n "$TOP_N" \
        | while IFS="$(printf '\t')" read -r bytes key; do
            label="${key#data/}"
            print_size_line "$key" "$label" "$bytes"
        done
}

print_top_data_dirs_table() {
    awk -F '\t' '$1 ~ /^data\// { print $2 "\t" $1 }' "$CURRENT_FILE" \
        | sort -rn \
        | head -n "$TOP_N" \
        | while IFS="$(printf '\t')" read -r bytes key; do
            label="${key#data/}"
            print_size_row "$key" "$label" "$bytes"
        done
}

print_database_hotspots() {
    echo "Database and storage hotspots:"
    awk -F '\t' '$1 ~ /^db\// { print $2 "\t" $1 }' "$CURRENT_FILE" \
        | sort -rn \
        | head -n "$TOP_N" \
        | while IFS="$(printf '\t')" read -r bytes key; do
            label="${key#db/}"
            label="$(printf "%s" "$label" | sed 's/-/ /g')"
            print_size_line "$key" "$label" "$bytes"
        done
}

print_database_hotspots_table() {
    awk -F '\t' '$1 ~ /^db\// { print $2 "\t" $1 }' "$CURRENT_FILE" \
        | sort -rn \
        | head -n "$TOP_N" \
        | while IFS="$(printf '\t')" read -r bytes key; do
            label="${key#db/}"
            case "$label" in
                pricebuddy-mysql)
                    label="PriceBuddy MySQL"
                    ;;
                prometheus-tsdb)
                    label="Prometheus"
                    ;;
                teslamate-model-y-postgres)
                    label="TeslaMate Y PG"
                    ;;
                teslamate-model-3-postgres)
                    label="TeslaMate 3 PG"
                    ;;
                n8n-sqlite)
                    label="n8n SQLite"
                    ;;
                uptime-kuma-db)
                    label="Uptime Kuma"
                    ;;
                grafana-db)
                    label="Grafana"
                    ;;
                home-assistant-db)
                    label="Home Assistant"
                    ;;
                diun-db)
                    label="Diun"
                    ;;
                vaultwarden-db)
                    label="Vaultwarden"
                    ;;
                *)
                    label="$(printf "%s" "$label" | sed 's/-/ /g')"
                    ;;
            esac
            print_size_row "$key" "$label" "$bytes"
        done
}

print_container_restarts() {
    echo "Container restarts:"
    if ! command -v docker >/dev/null 2>&1; then
        echo "  docker not installed"
        return
    fi

    restarts="$(
        docker ps -a --format '{{.Names}}' 2>/dev/null \
            | while IFS= read -r container; do
                count="$(docker inspect -f '{{.RestartCount}}' "$container" 2>/dev/null || echo 0)"
                if [ "$count" -gt 0 ] 2>/dev/null; then
                    printf "%s %s\n" "$count" "$container"
                fi
            done \
            | sort -rn \
            | head -n 8
    )"

    if [ -z "$restarts" ]; then
        echo "  - none"
    else
        printf "%s\n" "$restarts" | while read -r count container; do
            printf "  - %s: %s\n" "$container" "$count"
        done
    fi
}

print_container_restarts_table() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker not installed"
        return
    fi

    restarts="$(
        docker ps -a --format '{{.Names}}' 2>/dev/null \
            | while IFS= read -r container; do
                count="$(docker inspect -f '{{.RestartCount}}' "$container" 2>/dev/null || echo 0)"
                if [ "$count" -gt 0 ] 2>/dev/null; then
                    printf "%s %s\n" "$count" "$container"
                fi
            done \
            | sort -rn \
            | head -n 8
    )"

    if [ -z "$restarts" ]; then
        echo "none"
    else
        printf "%s\n" "$restarts" | while read -r count container; do
            printf "%-22s %s\n" "$container" "$count"
        done
    fi
}

print_html_section() {
    local title="$1"
    local content="$2"

    printf "<b>%s</b>\n" "$title"
    printf "<pre>%s</pre>\n\n" "$(printf "%s" "$content" | html_escape)"
}

collect_data_sizes
collect_backup_sizes
collect_database_sizes

case "$FORMAT" in
    telegram)
        echo "Weekly Homelab Storage Report"
        echo "Generated: $(date '+%Y-%m-%d %H:%M %Z')"
        echo ""
        print_filesystems
        echo ""
        print_backup_status
        echo ""
        print_docker_summary
        echo ""
        print_top_data_dirs
        echo ""
        print_database_hotspots
        echo ""
        print_container_restarts
        ;;
    telegram_html)
        echo "<b>Weekly Homelab Storage Report</b>"
        echo "<code>$(date '+%Y-%m-%d %H:%M %Z')</code>"
        echo ""
        print_html_section "Filesystems" "$(print_filesystems_table)"
        print_html_section "Backup" "$(print_backup_table)"
        print_html_section "Docker Disk Usage" "$(print_docker_table)"
        print_html_section "Largest Service Data" "$(print_top_data_dirs_table)"
        print_html_section "Database Hotspots" "$(print_database_hotspots_table)"
        print_html_section "Container Restarts" "$(print_container_restarts_table)"
        ;;
esac

if [ "$SAVE_STATE" -eq 1 ]; then
    sort "$CURRENT_FILE" > "$STATE_FILE"
fi
