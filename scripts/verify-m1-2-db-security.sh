#!/usr/bin/env bash
# =============================================================================
# M1.2 Complete Verification & Clean-Bootstrap Regression Suite
# Executes:
#   1. Idempotent role/schema reconciliation on running commerce-postgres (without
#      deleting existing development volumes)
#   2. Migration execution + idempotent re-execution on commerce-postgres
#   3. Full Promotion & Multi-DB PostgreSQL security suite on commerce-postgres
#   4. Clean-bootstrap verification on a disposable PostgreSQL 17 container
#      (commerce-postgres-clean-test on port 15432) from scratch + migration
#      execution + re-execution + security suite
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
CLEAN_CONTAINER="commerce-postgres-clean-test"
CLEAN_PORT="15432"

cleanup() {
    docker rm -f -v "${CLEAN_CONTAINER}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

chmod +x "${REPO_ROOT}/scripts/run-migrations.sh" "${REPO_ROOT}/tests/security/test-promotion-db-security.sh"

echo "============================================================================="
echo "[STEP 1/5] Reconciling M1.2 roles & schemas on running commerce-postgres..."
echo "============================================================================="
docker cp "${REPO_ROOT}/deploy/local/postgres/init-multi-db.sh" commerce-postgres:/tmp/init-multi-db.sh
docker exec -i commerce-postgres bash -c "
    set -a
    export CATALOG_MIGRATOR_USER='catalog_migrator'
    export CATALOG_MIGRATOR_PASSWORD='placeholder_catalog_migrator_replace_me'
    export CUSTOMER_MIGRATOR_USER='customer_migrator'
    export CUSTOMER_MIGRATOR_PASSWORD='placeholder_customer_migrator_replace_me'
    export ORDER_MIGRATOR_USER='order_migrator'
    export ORDER_MIGRATOR_PASSWORD='placeholder_order_migrator_replace_me'
    export INVENTORY_MIGRATOR_USER='inventory_migrator'
    export INVENTORY_MIGRATOR_PASSWORD='placeholder_inventory_migrator_replace_me'
    export PAYMENT_MIGRATOR_USER='payment_migrator'
    export PAYMENT_MIGRATOR_PASSWORD='placeholder_payment_migrator_replace_me'
    export NOTIFICATION_MIGRATOR_USER='notification_migrator'
    export NOTIFICATION_MIGRATOR_PASSWORD='placeholder_notification_migrator_replace_me'
    export AI_AGENT_MIGRATOR_USER='ai_agent_migrator'
    export AI_AGENT_MIGRATOR_PASSWORD='placeholder_ai_agent_migrator_replace_me'
    set +a
    bash /tmp/init-multi-db.sh && rm -f /tmp/init-multi-db.sh
"

echo "============================================================================="
echo "[STEP 2/5] Running migrations & idempotent re-execution on commerce-postgres..."
echo "============================================================================="
"${REPO_ROOT}/scripts/run-migrations.sh"
echo "[INFO] Re-running migrations to verify idempotent no-op and SHA-256 verification..."
"${REPO_ROOT}/scripts/run-migrations.sh"

echo "============================================================================="
echo "[STEP 3/5] Running PostgreSQL security suite on commerce-postgres..."
echo "============================================================================="
"${REPO_ROOT}/tests/security/test-promotion-db-security.sh"

echo "============================================================================="
echo "[STEP 4/5] Starting disposable clean-bootstrap container (${CLEAN_CONTAINER}:${CLEAN_PORT})..."
echo "============================================================================="
cleanup

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

docker run -d \
    --name "${CLEAN_CONTAINER}" \
    --env-file "${ENV_FILE}" \
    -e POSTGRES_USER="${POSTGRES_SUPERUSER}" \
    -e POSTGRES_PASSWORD="${POSTGRES_SUPERUSER_PASSWORD}" \
    -e POSTGRES_DB=postgres \
    -p "127.0.0.1:${CLEAN_PORT}:5432" \
    -v "${REPO_ROOT}/deploy/local/postgres/init-multi-db.sh:/docker-entrypoint-initdb.d/01-init-multi-db.sh:ro" \
    pgvector/pgvector:0.8.0-pg17 >/dev/null

echo "[INFO] Waiting for disposable clean-bootstrap PostgreSQL 17 to finish initdb..."
for _ in $(seq 1 40); do
    if PGPASSWORD="${PROMOTION_APP_PASSWORD}" psql -h localhost -p "${CLEAN_PORT}" -U "${PROMOTION_APP_USER}" -d "${PROMOTION_DB_NAME}" -Atqc "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

PGPASSWORD="${PROMOTION_APP_PASSWORD}" psql -h localhost -p "${CLEAN_PORT}" -U "${PROMOTION_APP_USER}" -d "${PROMOTION_DB_NAME}" -Atqc "SELECT 1;" >/dev/null \
    || { echo "[FAIL] Clean-bootstrap container failed to initialize." >&2; exit 1; }

echo "============================================================================="
echo "[STEP 5/5] Verifying migrations, re-execution, and security suite on clean bootstrap..."
echo "============================================================================="
PG_HOST_OVERRIDE=localhost PG_PORT_OVERRIDE="${CLEAN_PORT}" "${REPO_ROOT}/scripts/run-migrations.sh"
PG_HOST_OVERRIDE=localhost PG_PORT_OVERRIDE="${CLEAN_PORT}" "${REPO_ROOT}/scripts/run-migrations.sh"
PG_HOST_OVERRIDE=localhost PG_PORT_OVERRIDE="${CLEAN_PORT}" "${REPO_ROOT}/tests/security/test-promotion-db-security.sh"

echo "============================================================================="
echo "[SUCCESS] M1.2 Clean-Bootstrap, Migration Idempotency, and Security Suite PASSED!"
echo "============================================================================="
