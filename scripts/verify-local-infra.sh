#!/usr/bin/env bash
# =============================================================================
# M1.1 Local Infrastructure Executable Verification Suite
# Verifies:
#   1. Container health status (commerce-postgres, commerce-redis, commerce-kafka)
#   2. Named persistent volumes existence & restart durability
#   3. PostgreSQL 17 external connectivity, 8-DB isolation, extensions,
#      NOSUPERUSER enforcement, and ADR-0005 Promotion 4-role separation
#   4. Redis 7.4 authentication enforcement (NOAUTH rejection) & PING/SET/GET
#   5. Kafka 3.8+ (KRaft) external listener (localhost:9092) metadata, topic
#      creation, producer publish, and consumer read-back
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"
COMPOSE_FILE="${REPO_ROOT}/deploy/local/docker-compose.yml"

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

info() {
    echo "[INFO] $*"
}

pass() {
    echo "[PASS] $*"
}

if [[ ! -f "${ENV_FILE}" ]]; then
    fail "Missing ${ENV_FILE}. Copy .env.example to .env before running verification."
fi

# Load environment variables from .env safely
set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

command -v docker >/dev/null 2>&1 || fail "docker CLI is not installed or not in PATH."
command -v psql >/dev/null 2>&1 || fail "psql client is not installed or not in PATH."
command -v redis-cli >/dev/null 2>&1 || fail "redis-cli is not installed or not in PATH."

# -----------------------------------------------------------------------------
# 1. Verify Container Health Status
# -----------------------------------------------------------------------------
info "Checking container health statuses..."
for container in commerce-postgres commerce-redis commerce-kafka; do
    status="$(docker inspect --format '{{.State.Health.Status}}' "${container}" 2>/dev/null || echo "missing")"
    if [[ "${status}" != "healthy" ]]; then
        fail "Container '${container}' is not healthy (current status: '${status}'). Run 'docker compose --env-file .env -f deploy/local/docker-compose.yml up -d --wait'."
    fi
    pass "Container '${container}' is healthy."
done

# -----------------------------------------------------------------------------
# 2. Verify Named Persistent Volumes Exist
# -----------------------------------------------------------------------------
info "Checking named persistent Docker volumes..."
for vol in commerce_postgres_data commerce_redis_data commerce_kafka_data; do
    docker volume inspect "${vol}" >/dev/null 2>&1 || fail "Expected persistent volume '${vol}' does not exist."
    pass "Persistent volume '${vol}' exists."
done

# -----------------------------------------------------------------------------
# 3. Verify PostgreSQL 17 External Connectivity, Isolation & Role Security
# -----------------------------------------------------------------------------
info "Verifying PostgreSQL 17 external connectivity on ${POSTGRES_HOST}:${POSTGRES_PORT}..."

run_psql() {
    local user="$1"
    local password="$2"
    local db="$3"
    local query="$4"
    PGPASSWORD="${password}" psql \
        -h "${POSTGRES_HOST}" \
        -p "${POSTGRES_PORT}" \
        -U "${user}" \
        -d "${db}" \
        -v ON_ERROR_STOP=1 \
        -Atqc "${query}"
}

# 3a. Verify each bounded-context role can connect to its own database and is NOSUPERUSER
declare -a DB_CHECKS=(
    "${CATALOG_DB_NAME}:${CATALOG_DB_USER}:${CATALOG_DB_PASSWORD}"
    "${CUSTOMER_DB_NAME}:${CUSTOMER_DB_USER}:${CUSTOMER_DB_PASSWORD}"
    "${ORDER_DB_NAME}:${ORDER_DB_USER}:${ORDER_DB_PASSWORD}"
    "${INVENTORY_DB_NAME}:${INVENTORY_DB_USER}:${INVENTORY_DB_PASSWORD}"
    "${PAYMENT_DB_NAME}:${PAYMENT_DB_USER}:${PAYMENT_DB_PASSWORD}"
    "${NOTIFICATION_DB_NAME}:${NOTIFICATION_DB_USER}:${NOTIFICATION_DB_PASSWORD}"
    "${AI_AGENT_DB_NAME}:${AI_AGENT_DB_USER}:${AI_AGENT_DB_PASSWORD}"
    "${PROMOTION_DB_NAME}:${PROMOTION_APP_USER}:${PROMOTION_APP_PASSWORD}"
    "${PROMOTION_DB_NAME}:${PROMOTION_MIGRATOR_USER}:${PROMOTION_MIGRATOR_PASSWORD}"
    "${PROMOTION_DB_NAME}:${PROMOTION_DBA_ADMIN_USER}:${PROMOTION_DBA_ADMIN_PASSWORD}"
)

for entry in "${DB_CHECKS[@]}"; do
    IFS=":" read -r db_name db_user db_pass <<< "${entry}"
    is_super="$(run_psql "${db_user}" "${db_pass}" "${db_name}" "SELECT rolsuper FROM pg_roles WHERE rolname = current_user;")"
    if [[ "${is_super}" != "f" ]]; then
        fail "Role '${db_user}' must be NOSUPERUSER (got rolsuper='${is_super}')."
    fi
    pass "PostgreSQL role '${db_user}' connected to '${db_name}' and verified NOSUPERUSER."
done

# 3b. Verify promotion_proc_owner exists, is NOLOGIN and NOSUPERUSER, and owns promotion_db
proc_owner_attrs="$(run_psql "${PROMOTION_MIGRATOR_USER}" "${PROMOTION_MIGRATOR_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT rolcanlogin || ':' || rolsuper FROM pg_roles WHERE rolname = '${PROMOTION_PROC_OWNER_ROLE}';")"
if [[ "${proc_owner_attrs}" != "false:false" ]]; then
    fail "Role '${PROMOTION_PROC_OWNER_ROLE}' must be NOLOGIN and NOSUPERUSER (got '${proc_owner_attrs}')."
fi
pass "Role '${PROMOTION_PROC_OWNER_ROLE}' verified as NOLOGIN and NOSUPERUSER."

# 3c. Verify Promotion public schema lockdown (promotion_app_role MUST NOT have CREATE on public)
if run_psql "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "CREATE TABLE public._unauthorized_probe (id int);" >/dev/null 2>&1; then
    fail "SECURITY VIOLATION: '${PROMOTION_APP_USER}' was able to CREATE TABLE in schema public!"
fi
pass "Promotion public schema CREATE lockdown verified ('${PROMOTION_APP_USER}' denied DDL in public)."

# 3d. Verify Cross-Database Isolation (order_svc_user MUST NOT connect to inventory_db)
if run_psql "${ORDER_DB_USER}" "${ORDER_DB_PASSWORD}" "${INVENTORY_DB_NAME}" "SELECT 1;" >/dev/null 2>&1; then
    fail "ISOLATION VIOLATION: '${ORDER_DB_USER}' was able to connect to '${INVENTORY_DB_NAME}'!"
fi
pass "Cross-database isolation verified ('${ORDER_DB_USER}' denied access to '${INVENTORY_DB_NAME}')."

# 3e. Verify Required PostgreSQL Extensions (pg_trgm in catalog_db, vector in ai_agent_db)
trgm_ext="$(run_psql "${CATALOG_DB_USER}" "${CATALOG_DB_PASSWORD}" "${CATALOG_DB_NAME}" \
    "SELECT extname FROM pg_extension WHERE extname = 'pg_trgm';")"
[[ "${trgm_ext}" == "pg_trgm" ]] || fail "Extension 'pg_trgm' missing in '${CATALOG_DB_NAME}'."
pass "Extension 'pg_trgm' verified in '${CATALOG_DB_NAME}'."

vec_ext="$(run_psql "${AI_AGENT_DB_USER}" "${AI_AGENT_DB_PASSWORD}" "${AI_AGENT_DB_NAME}" \
    "SELECT extname FROM pg_extension WHERE extname = 'vector';")"
[[ "${vec_ext}" == "vector" ]] || fail "Extension 'vector' (pgvector) missing in '${AI_AGENT_DB_NAME}'."
pass "Extension 'vector' (pgvector) verified in '${AI_AGENT_DB_NAME}'."

# -----------------------------------------------------------------------------
# 4. Verify Redis 7.4 Authentication & Operations from Host
# -----------------------------------------------------------------------------
info "Verifying Redis 7.4 on ${REDIS_HOST}:${REDIS_PORT}..."

unauth_resp="$(redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING 2>&1 || true)"
if [[ "${unauth_resp}" != *"NOAUTH"* ]]; then
    fail "Redis allowed unauthenticated PING (response: '${unauth_resp}')."
fi
pass "Redis rejected unauthenticated PING with NOAUTH."

pong_resp="$(REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" PING)"
[[ "${pong_resp}" == "PONG" ]] || fail "Expected PONG from Redis, got '${pong_resp}'."

REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" SET "commerce:m1_1:persistence_probe" "verified" >/dev/null
redis_val="$(REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" GET "commerce:m1_1:persistence_probe")"
[[ "${redis_val}" == "verified" ]] || fail "Redis GET mismatch (got '${redis_val}')."
pass "Redis authenticated PING and SET/GET succeeded from host."

# -----------------------------------------------------------------------------
# 5. Verify Kafka 3.8+ (KRaft) External Listener (localhost:9092) Produce/Consume
# -----------------------------------------------------------------------------
info "Verifying Kafka KRaft external listener (${KAFKA_BOOTSTRAP_SERVERS})..."

TEST_TOPIC="commerce.infra.verification.v1"
TEST_MESSAGE="m1_1_kafka_verification_$(date +%s)"

# Run Kafka CLI inside an ephemeral container joined to the host network so it connects
# strictly through the EXTERNAL listener (localhost:9092) from outside commerce-kafka!
docker run --rm --network host apache/kafka:3.8.1 \
    /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVERS}" \
    --create --if-not-exists \
    --topic "${TEST_TOPIC}" \
    --partitions 1 \
    --replication-factor 1 >/dev/null

echo "${TEST_MESSAGE}" | docker run --rm -i --network host apache/kafka:3.8.1 \
    /opt/kafka/bin/kafka-console-producer.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVERS}" \
    --topic "${TEST_TOPIC}" >/dev/null

consumed_msg="$(docker run --rm --network host apache/kafka:3.8.1 \
    /opt/kafka/bin/kafka-console-consumer.sh \
    --bootstrap-server "${KAFKA_BOOTSTRAP_SERVERS}" \
    --topic "${TEST_TOPIC}" \
    --from-beginning \
    --max-messages 1 \
    --timeout-ms 10000 2>/dev/null | tail -n 1)"

if [[ -z "${consumed_msg}" ]]; then
    fail "Failed to consume message from Kafka topic '${TEST_TOPIC}' via external listener ${KAFKA_BOOTSTRAP_SERVERS}."
fi
pass "Kafka KRaft external listener (${KAFKA_BOOTSTRAP_SERVERS}) topic creation, producer publish, and consumer read-back succeeded."

# -----------------------------------------------------------------------------
# 6. Verify Persistent Volume Durability Across Container Restart
# -----------------------------------------------------------------------------
info "Verifying persistent volume durability across container restarts..."
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" restart postgres redis >/dev/null
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --wait >/dev/null

redis_persisted="$(REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" GET "commerce:m1_1:persistence_probe")"
[[ "${redis_persisted}" == "verified" ]] || fail "Redis AOF persistence failed across container restart!"
REDISCLI_AUTH="${REDIS_PASSWORD}" redis-cli -h "${REDIS_HOST}" -p "${REDIS_PORT}" DEL "commerce:m1_1:persistence_probe" >/dev/null

db_count="$(run_psql "${POSTGRES_SUPERUSER}" "${POSTGRES_SUPERUSER_PASSWORD}" "postgres" \
    "SELECT count(*) FROM pg_database WHERE datname IN ('catalog_db','customer_db','order_db','inventory_db','payment_db','promotion_db','notification_db','ai_agent_db');")"
[[ "${db_count}" == "8" ]] || fail "PostgreSQL persistent volume lost databases across restart (found ${db_count}/8)."
pass "Persistent volume durability verified across PostgreSQL and Redis restarts."

echo "============================================================================="
echo "[SUCCESS] All M1.1 local infrastructure checks passed!"
echo "============================================================================="
