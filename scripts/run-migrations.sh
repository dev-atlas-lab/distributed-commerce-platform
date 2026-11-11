#!/usr/bin/env bash
# =============================================================================
# Polyglot Database Migration Runner (M1.2)
# Executes versioned, immutable SQL migrations across all 8 isolated service
# databases using each database's dedicated least-privilege migration role
# (<service>_migrator).
#
# Features:
#   - Deterministic lexicographical version ordering (V001__*, V002__*, ...)
#   - SHA-256 checksum calculation and immutability verification on re-runs
#   - Single-transaction atomic execution per migration (--single-transaction)
#   - Fail-fast behavior (ON_ERROR_STOP=1)
#   - History tracking in public.schema_migration_history (read-only to app role)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "[FAIL] Missing ${ENV_FILE}. Copy .env.example to .env first." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

PG_HOST="${PG_HOST_OVERRIDE:-${POSTGRES_HOST:-localhost}}"
PG_PORT="${PG_PORT_OVERRIDE:-${POSTGRES_PORT:-5432}}"

fail() {
    echo "[MIGRATION-FAIL] $*" >&2
    exit 1
}

info() {
    echo "[MIGRATION-INFO] $*"
}

pass() {
    echo "[MIGRATION-PASS] $*"
}

run_psql_as() {
    local user="$1"
    local pass_val="$2"
    local db="$3"
    local sql="$4"
    PGPASSWORD="${pass_val}" psql \
        -h "${PG_HOST}" \
        -p "${PG_PORT}" \
        -U "${user}" \
        -d "${db}" \
        -v ON_ERROR_STOP=1 \
        -Atq <<< "${sql}"
}

ensure_history_table() {
    local db_name="$1"
    local mig_user="$2"
    local mig_pass="$3"
    local app_user="$4"
    local owner_role="$5"

    local role_switch_prefix=""
    local role_switch_suffix=""
    local revoke_targets="PUBLIC, ${app_user}"
    local extra_grant=""

    if [[ "${owner_role}" != "${mig_user}" ]]; then
        role_switch_prefix="SET LOCAL ROLE ${owner_role};"
        role_switch_suffix="RESET ROLE;"
        revoke_targets="PUBLIC, ${app_user}, ${mig_user}"
        extra_grant="GRANT SELECT ON TABLE public.schema_migration_history TO ${PROMOTION_DBA_ADMIN_USER};"
    fi

    run_psql_as "${mig_user}" "${mig_pass}" "${db_name}" "
        BEGIN;
        ${role_switch_prefix}
        CREATE TABLE IF NOT EXISTS public.schema_migration_history (
            installed_rank      SERIAL       NOT NULL,
            version             VARCHAR(32)  NOT NULL,
            description         VARCHAR(256) NOT NULL,
            script_name         VARCHAR(256) NOT NULL,
            checksum_sha256     CHAR(64)     NOT NULL,
            installed_by        VARCHAR(64)  NOT NULL,
            installed_on        TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
            execution_time_ms   INTEGER      NOT NULL DEFAULT 0,
            success             BOOLEAN      NOT NULL DEFAULT TRUE,
            CONSTRAINT pk_schema_migration_history PRIMARY KEY (version),
            CONSTRAINT uq_schema_migration_script UNIQUE (script_name)
        );
        ALTER TABLE public.schema_migration_history OWNER TO ${owner_role};
        REVOKE ALL ON TABLE public.schema_migration_history FROM ${revoke_targets};
        REVOKE ALL ON SEQUENCE public.schema_migration_history_installed_rank_seq FROM ${revoke_targets};
        GRANT SELECT, INSERT, UPDATE ON TABLE public.schema_migration_history TO ${owner_role};
        GRANT USAGE, SELECT ON SEQUENCE public.schema_migration_history_installed_rank_seq TO ${owner_role};
        GRANT SELECT ON TABLE public.schema_migration_history TO ${app_user};
        ${extra_grant}
        ${role_switch_suffix}
        COMMIT;
    " >/dev/null
}

apply_service_migrations() {
    local service_label="$1"
    local db_name="$2"
    local mig_user="$3"
    local mig_pass="$4"
    local app_user="$5"
    local owner_role="$6"
    local mig_dir="$7"

    if [[ ! -d "${mig_dir}" ]]; then
        fail "Migration directory does not exist for ${service_label}: ${mig_dir}"
    fi

    info "Checking migrations for ${service_label} (db='${db_name}', migrator='${mig_user}', owner='${owner_role}')..."
    ensure_history_table "${db_name}" "${mig_user}" "${mig_pass}" "${app_user}" "${owner_role}"

    mapfile -t scripts < <(find "${mig_dir}" -maxdepth 1 -type f -name 'V[0-9][0-9][0-9]__*.sql' | LC_ALL=C sort)
    if [[ "${#scripts[@]}" -eq 0 ]]; then
        fail "No versioned migration scripts (V001__*.sql) found in ${mig_dir}"
    fi

    local applied_count=0
    local skipped_count=0

    for script_path in "${scripts[@]}"; do
        local script_name
        script_name="$(basename "${script_path}")"

        if [[ ! "${script_name}" =~ ^V([0-9]{3})__([a-z0-9_]+)\.sql$ ]]; then
            fail "Invalid migration filename '${script_name}' in ${mig_dir}. Expected V<3-digit-version>__<snake_case_description>.sql"
        fi

        local version="${BASH_REMATCH[1]}"
        local raw_desc="${BASH_REMATCH[2]}"
        local description="${raw_desc//_/ }"
        local checksum
        checksum="$(sha256sum "${script_path}" | awk '{print $1}')"

        local role_switch_prefix=""
        if [[ "${owner_role}" != "${mig_user}" ]]; then
            role_switch_prefix="SET LOCAL ROLE ${owner_role};"
        fi

        local existing_checksum
        existing_checksum="$(run_psql_as "${mig_user}" "${mig_pass}" "${db_name}" "
            BEGIN;
            ${role_switch_prefix}
            SELECT checksum_sha256 FROM public.schema_migration_history WHERE version = '${version}';
        " | tail -n 1)"

        if [[ -n "${existing_checksum}" && "${existing_checksum}" != "BEGIN" ]]; then
            if [[ "${existing_checksum}" != "${checksum}" ]]; then
                fail "IMMUTABILITY_VIOLATION on ${db_name}: Migration ${script_name} (version ${version}) was modified after application! Expected SHA-256 ${existing_checksum}, found ${checksum}."
            fi
            info "  [SKIP] ${db_name}: ${script_name} (v${version} already applied, SHA-256 verified)"
            skipped_count=$((skipped_count + 1))
            continue
        fi

        local start_ms
        start_ms="$(date +%s%3N)"

        local tmp_sql
        tmp_sql="$(mktemp)"
        {
            if [[ "${owner_role}" != "${mig_user}" ]]; then
                echo "SET LOCAL ROLE ${owner_role};"
            fi
            cat "${script_path}"
            echo ""
            if [[ "${owner_role}" != "${mig_user}" ]]; then
                echo "SET LOCAL ROLE ${owner_role};"
            fi
            cat <<EOSQL
INSERT INTO public.schema_migration_history (
    version, description, script_name, checksum_sha256, installed_by, execution_time_ms, success
) VALUES (
    '${version}', '${description}', '${script_name}', '${checksum}', '${mig_user}', 0, TRUE
);
EOSQL
            if [[ "${owner_role}" != "${mig_user}" ]]; then
                echo "RESET ROLE;"
            fi
        } > "${tmp_sql}"

        if ! PGPASSWORD="${mig_pass}" psql \
            -h "${PG_HOST}" \
            -p "${PG_PORT}" \
            -U "${mig_user}" \
            -d "${db_name}" \
            --single-transaction \
            -v ON_ERROR_STOP=1 \
            -q -f "${tmp_sql}"; then
            rm -f "${tmp_sql}"
            fail "Failed to apply migration ${script_name} on ${db_name} (rolled back atomically)."
        fi
        rm -f "${tmp_sql}"

        local end_ms
        end_ms="$(date +%s%3N)"
        local elapsed_ms=$((end_ms - start_ms))

        run_psql_as "${mig_user}" "${mig_pass}" "${db_name}" "
            BEGIN;
            ${role_switch_prefix}
            UPDATE public.schema_migration_history
               SET execution_time_ms = ${elapsed_ms}
             WHERE version = '${version}';
            COMMIT;
        " >/dev/null

        pass "  [APPLIED] ${db_name}: ${script_name} (v${version}, ${elapsed_ms}ms, sha256=${checksum:0:12}...)"
        applied_count=$((applied_count + 1))
    done

    pass "${service_label} (${db_name}): ${applied_count} applied, ${skipped_count} already up-to-date."
}

apply_service_migrations \
    "catalog-service (Java/Flyway)" \
    "${CATALOG_DB_NAME}" \
    "${CATALOG_MIGRATOR_USER}" \
    "${CATALOG_MIGRATOR_PASSWORD}" \
    "${CATALOG_DB_USER}" \
    "${CATALOG_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/catalog/src/main/resources/db/migration"

apply_service_migrations \
    "inventory-service (Java/Flyway)" \
    "${INVENTORY_DB_NAME}" \
    "${INVENTORY_MIGRATOR_USER}" \
    "${INVENTORY_MIGRATOR_PASSWORD}" \
    "${INVENTORY_DB_USER}" \
    "${INVENTORY_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/inventory/src/main/resources/db/migration"

apply_service_migrations \
    "order-service (Java/Flyway)" \
    "${ORDER_DB_NAME}" \
    "${ORDER_MIGRATOR_USER}" \
    "${ORDER_MIGRATOR_PASSWORD}" \
    "${ORDER_DB_USER}" \
    "${ORDER_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/order/src/main/resources/db/migration"

apply_service_migrations \
    "payment-service (Java/Flyway)" \
    "${PAYMENT_DB_NAME}" \
    "${PAYMENT_MIGRATOR_USER}" \
    "${PAYMENT_MIGRATOR_PASSWORD}" \
    "${PAYMENT_DB_USER}" \
    "${PAYMENT_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/payment/src/main/resources/db/migration"

apply_service_migrations \
    "customer-service (.NET/DbUp)" \
    "${CUSTOMER_DB_NAME}" \
    "${CUSTOMER_MIGRATOR_USER}" \
    "${CUSTOMER_MIGRATOR_PASSWORD}" \
    "${CUSTOMER_DB_USER}" \
    "${CUSTOMER_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/customer/Commerce.Customer.Api/Infrastructure/Persistence/Migrations"

apply_service_migrations \
    "promotion-service (.NET/DbUp — CH-01 4-Role Model)" \
    "${PROMOTION_DB_NAME}" \
    "${PROMOTION_MIGRATOR_USER}" \
    "${PROMOTION_MIGRATOR_PASSWORD}" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_PROC_OWNER_ROLE}" \
    "${REPO_ROOT}/src/services/promotion/Commerce.Promotion.Api/Infrastructure/Persistence/Migrations"

apply_service_migrations \
    "notification-service (.NET/DbUp)" \
    "${NOTIFICATION_DB_NAME}" \
    "${NOTIFICATION_MIGRATOR_USER}" \
    "${NOTIFICATION_MIGRATOR_PASSWORD}" \
    "${NOTIFICATION_DB_USER}" \
    "${NOTIFICATION_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/services/notification/Commerce.Notification.Api/Infrastructure/Persistence/Migrations"

apply_service_migrations \
    "ai-worker (Python/Alembic SQL)" \
    "${AI_AGENT_DB_NAME}" \
    "${AI_AGENT_MIGRATOR_USER}" \
    "${AI_AGENT_MIGRATOR_PASSWORD}" \
    "${AI_AGENT_DB_USER}" \
    "${AI_AGENT_MIGRATOR_USER}" \
    "${REPO_ROOT}/src/workers/ai-worker/src/ai_worker/infrastructure/persistence/migrations"

echo "============================================================================="
echo "[SUCCESS] All 8 service database migrations verified and up to date."
echo "============================================================================="
