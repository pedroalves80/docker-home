#!/bin/bash
set -e
set -o pipefail

export PATH="/usr/local/bin:/usr/bin:/bin:/usr/local/sbin:/usr/sbin:/sbin"
export TZ="${TZ:-Europe/Lisbon}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMAT="json"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)
            FORMAT="json"
            ;;
        --help|-h)
            echo "Usage: $0 [--json]"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--json]" >&2
            exit 1
            ;;
    esac
    shift
done

cd "$SCRIPT_DIR"

json_escape() {
    printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

is_service_running() {
    local service_name="$1"

    docker compose ps --status running --services | grep -qx "$service_name"
}

run_db_check() {
    local service_name="$1"

    if ! is_service_running "$service_name"; then
        printf '{"status":"error","problem_count":1,"split_candidates":0,"stale_open_processes":0,"error":"service not running"}'
        return
    fi

    docker compose exec -T "$service_name" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 -t -A' <<'SQL' | tr -d '\n'
WITH split_pairs AS (
    SELECT
        a.id AS first_id,
        b.id AS second_id,
        COALESCE(g.name, 'unknown') AS geofence,
        a.start_date AS first_start_utc,
        first_sample.last_date AS backup_cut_utc,
        b.start_date AS second_start_utc,
        b.end_date AS second_end_utc,
        first_energy.added AS first_added,
        second_energy.added AS second_added
    FROM charging_processes a
    JOIN charging_processes b ON b.id = a.id + 1
    LEFT JOIN geofences g ON g.id = a.geofence_id
    CROSS JOIN LATERAL (
        SELECT max(date) AS last_date
        FROM charges
        WHERE charging_process_id = a.id
    ) first_sample
    CROSS JOIN LATERAL (
        SELECT round((max(charge_energy_added) - min(charge_energy_added))::numeric, 2) AS added
        FROM charges
        WHERE charging_process_id = a.id
    ) first_energy
    CROSS JOIN LATERAL (
        SELECT round((max(charge_energy_added) - min(charge_energy_added))::numeric, 2) AS added
        FROM charges
        WHERE charging_process_id = b.id
    ) second_energy
    WHERE a.end_date IS NULL
      AND b.end_date IS NOT NULL
      AND a.car_id = b.car_id
      AND a.geofence_id IS NOT DISTINCT FROM b.geofence_id
      AND first_sample.last_date IS NOT NULL
      AND b.start_date BETWEEN first_sample.last_date AND first_sample.last_date + interval '10 minutes'
      AND EXTRACT(HOUR FROM (first_sample.last_date AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon')) = 2
      AND EXTRACT(MINUTE FROM (first_sample.last_date AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon')) >= 55
),
stale_open AS (
    SELECT
        cp.id,
        COALESCE(g.name, 'unknown') AS geofence,
        cp.start_date,
        round(EXTRACT(EPOCH FROM ((now() AT TIME ZONE 'UTC') - cp.start_date)) / 3600.0, 1) AS age_hours
    FROM charging_processes cp
    LEFT JOIN geofences g ON g.id = cp.geofence_id
    WHERE cp.end_date IS NULL
      AND cp.start_date < (now() AT TIME ZONE 'UTC') - interval '12 hours'
      AND cp.start_date >= (now() AT TIME ZONE 'UTC') - interval '7 days'
),
counts AS (
    SELECT
        (SELECT count(*) FROM split_pairs) AS split_count,
        (SELECT count(*) FROM stale_open) AS stale_count
)
SELECT json_build_object(
    'status', CASE WHEN counts.split_count + counts.stale_count > 0 THEN 'alert' ELSE 'ok' END,
    'problem_count', counts.split_count + counts.stale_count,
    'split_candidates', counts.split_count,
    'stale_open_processes', counts.stale_count,
    'split_details', COALESCE((
        SELECT json_agg(json_build_object(
            'first_id', first_id,
            'second_id', second_id,
            'geofence', geofence,
            'first_start', to_char(first_start_utc AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
            'backup_cut', to_char(backup_cut_utc AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
            'second_start', to_char(second_start_utc AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
            'second_end', to_char(second_end_utc AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
            'first_added', first_added,
            'second_added', second_added,
            'combined_added', first_added + second_added
        ) ORDER BY first_start_utc DESC)
        FROM (
            SELECT *
            FROM split_pairs
            ORDER BY first_start_utc DESC
            LIMIT 5
        ) latest_splits
    ), '[]'::json),
    'stale_open_details', COALESCE((
        SELECT json_agg(json_build_object(
            'id', id,
            'geofence', geofence,
            'start', to_char(start_date AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
            'age_hours', age_hours
        ) ORDER BY start_date DESC)
        FROM (
            SELECT *
            FROM stale_open
            ORDER BY start_date DESC
            LIMIT 5
        ) latest_open
    ), '[]'::json)
)::text
FROM counts;
SQL
}

extract_problem_count() {
    printf "%s" "$1" | sed -n 's/.*"problem_count"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

car_json() {
    local car_name="$1"
    local service_name="$2"
    local check_json="$3"
    local body="${check_json#\{}"

    body="${body%\}}"
    printf '{"name":"%s","service":"%s",%s}' "$(json_escape "$car_name")" "$(json_escape "$service_name")" "$body"
}

if [ "$FORMAT" = "json" ]; then
    model3_check="$(run_db_check "teslamate_model3_db")"
    modely_check="$(run_db_check "teslamate_modely_db")"
    model3_problem_count="$(extract_problem_count "$model3_check")"
    modely_problem_count="$(extract_problem_count "$modely_check")"
    model3_problem_count="${model3_problem_count:-1}"
    modely_problem_count="${modely_problem_count:-1}"

    if [ $((model3_problem_count + modely_problem_count)) -gt 0 ]; then
        status="alert"
    else
        status="ok"
    fi

    printf '{"status":"%s","checked_at":"%s","cars":[%s,%s]}\n' \
        "$status" \
        "$(json_escape "$(date -Iseconds)")" \
        "$(car_json "Model 3" "teslamate_model3_db" "$model3_check")" \
        "$(car_json "Model Y" "teslamate_modely_db" "$modely_check")"
fi
