#!/usr/bin/env bash
# =============================================================================
# M1.2 Executable PostgreSQL Role, Privilege & Stored-Procedure Security Suite
# Connects using actual PostgreSQL roles (never simulating privileges in app code)
# and verifies all 13 mandatory Phase D security controls + SPEC-CH01-T6 + SPEC-CH06-T1.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="${REPO_ROOT}/.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "[FAIL] Missing ${ENV_FILE}." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1090
source "${ENV_FILE}"
set +a

PG_HOST="${PG_HOST_OVERRIDE:-${POSTGRES_HOST:-localhost}}"
PG_PORT="${PG_PORT_OVERRIDE:-${POSTGRES_PORT:-5432}}"

PASS_COUNT=0

fail() {
    echo "[SEC-FAIL] $*" >&2
    exit 1
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "[SEC-PASS #${PASS_COUNT}] $*"
}

psql_exec() {
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

expect_sql_failure() {
    local desc="$1"
    local expected_pattern="$2"
    local user="$3"
    local pass_val="$4"
    local db="$5"
    local sql="$6"

    local out
    if out="$(PGPASSWORD="${pass_val}" psql -h "${PG_HOST}" -p "${PG_PORT}" -U "${user}" -d "${db}" -v ON_ERROR_STOP=1 -Atqc "${sql}" 2>&1)"; then
        fail "${desc} — Expected SQL failure matching '${expected_pattern}', but command SUCCEEDED with output: ${out}"
    fi
    if ! printf '%s' "${out}" | grep -Eq "${expected_pattern}"; then
        fail "${desc} — Command failed as expected, but output '${out}' did not match expected pattern '${expected_pattern}'."
    fi
    pass "${desc}"
}

echo "============================================================================="
echo "Running M1.2 PostgreSQL Security & Privilege Verification on ${PG_HOST}:${PG_PORT}"
echo "============================================================================="

# -----------------------------------------------------------------------------
# TEST 1: promotion_proc_owner cannot log in (NOLOGIN NOSUPERUSER)
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 1a: promotion_proc_owner login attempt rejected by PostgreSQL" \
    "(not permitted to log in|password authentication failed for user \"${PROMOTION_PROC_OWNER_ROLE}\")" \
    "${PROMOTION_PROC_OWNER_ROLE}" \
    "any_password" \
    "${PROMOTION_DB_NAME}" \
    "SELECT 1;"

proc_owner_flags="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT rolcanlogin || ':' || rolsuper || ':' || rolcreatedb || ':' || rolcreaterole || ':' || rolinherit FROM pg_catalog.pg_roles WHERE rolname = '${PROMOTION_PROC_OWNER_ROLE}';")"
[[ "${proc_owner_flags}" == "false:false:false:false:false" ]] \
    || fail "Test 1b: Expected false:false:false:false:false for ${PROMOTION_PROC_OWNER_ROLE}, got ${proc_owner_flags}"
pass "Test 1b: promotion_proc_owner verified NOLOGIN, NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOINHERIT"

# -----------------------------------------------------------------------------
# TEST 2: Application role is not a superuser and cannot assume privileged roles
# -----------------------------------------------------------------------------
app_role_flags="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT rolsuper || ':' || rolcreatedb || ':' || rolcreaterole || ':' || rolreplication || ':' || rolbypassrls || ':' || rolinherit FROM pg_catalog.pg_roles WHERE rolname = '${PROMOTION_APP_USER}';")"
[[ "${app_role_flags}" == "false:false:false:false:false:false" ]] \
    || fail "Test 2a: Unexpected flags for ${PROMOTION_APP_USER}: ${app_role_flags}"
pass "Test 2a: promotion_app_role verified NOSUPERUSER, NOCREATEDB, NOCREATEROLE, NOREPLICATION, NOBYPASSRLS, NOINHERIT"

for target_role in "${PROMOTION_PROC_OWNER_ROLE}" "${PROMOTION_MIGRATOR_USER}" "${PROMOTION_DBA_ADMIN_USER}" "${POSTGRES_SUPERUSER}"; do
    expect_sql_failure \
        "Test 2b: promotion_app_role denied SET ROLE ${target_role}" \
        "permission denied to set role" \
        "${PROMOTION_APP_USER}" \
        "${PROMOTION_APP_PASSWORD}" \
        "${PROMOTION_DB_NAME}" \
        "SET ROLE ${target_role};"
done

# -----------------------------------------------------------------------------
# TEST 3: Application role cannot directly mutate or lock protected tables
# -----------------------------------------------------------------------------
declare -a PROTECTED_TABLES=(
    "public.flash_sale_campaigns"
    "public.flash_sale_claims"
    "public.flash_sale_items"
    "public.outbox_messages"
    "public.idempotency_records"
    "public.schema_migration_history"
)

for tbl in "${PROTECTED_TABLES[@]}"; do
    expect_sql_failure \
        "Test 3: promotion_app_role denied direct DELETE on ${tbl}" \
        "permission denied for table" \
        "${PROMOTION_APP_USER}" \
        "${PROMOTION_APP_PASSWORD}" \
        "${PROMOTION_DB_NAME}" \
        "DELETE FROM ${tbl};"

    expect_sql_failure \
        "Test 3: promotion_app_role denied direct TRUNCATE on ${tbl}" \
        "permission denied for table" \
        "${PROMOTION_APP_USER}" \
        "${PROMOTION_APP_PASSWORD}" \
        "${PROMOTION_DB_NAME}" \
        "TRUNCATE TABLE ${tbl};"

    expect_sql_failure \
        "Test 3: promotion_app_role denied direct SELECT FOR UPDATE on ${tbl}" \
        "permission denied for table" \
        "${PROMOTION_APP_USER}" \
        "${PROMOTION_APP_PASSWORD}" \
        "${PROMOTION_DB_NAME}" \
        "SELECT * FROM ${tbl} FOR UPDATE;"

    expect_sql_failure \
        "Test 3: promotion_app_role denied direct SELECT FOR SHARE on ${tbl}" \
        "permission denied for table" \
        "${PROMOTION_APP_USER}" \
        "${PROMOTION_APP_PASSWORD}" \
        "${PROMOTION_DB_NAME}" \
        "SELECT * FROM ${tbl} FOR SHARE;"
done

expect_sql_failure \
    "Test 3: promotion_app_role denied direct INSERT on public.flash_sale_campaigns" \
    "permission denied for table flash_sale_campaigns" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "INSERT INTO public.flash_sale_campaigns (campaign_id, name, status, current_epoch, starts_at, ends_at) VALUES (gen_random_uuid(), 'rogue', 'DRAFT', 1, now(), now() + interval '1 hour');"

expect_sql_failure \
    "Test 3: promotion_app_role denied direct UPDATE on public.flash_sale_campaigns" \
    "permission denied for table flash_sale_campaigns" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "UPDATE public.flash_sale_campaigns SET status = 'ACTIVE';"

expect_sql_failure \
    "Test 3: promotion_app_role denied direct INSERT on public.flash_sale_claims" \
    "permission denied for table flash_sale_claims" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "INSERT INTO public.flash_sale_claims (claim_id, campaign_id, campaign_epoch, sku_id, customer_id, idempotency_key, quantity, status, intent_lease_expires_at, payment_expires_at) VALUES (gen_random_uuid(), gen_random_uuid(), 1, gen_random_uuid(), gen_random_uuid(), 'k', 1, 'CLAIMED_RESERVED', now(), now());"

expect_sql_failure \
    "Test 3: promotion_app_role denied direct UPDATE on public.flash_sale_items" \
    "permission denied for table flash_sale_items" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "UPDATE public.flash_sale_items SET claimed_count = 0;"

expect_sql_failure \
    "Test 3: promotion_app_role denied direct INSERT on public.outbox_messages" \
    "permission denied for table outbox_messages" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "INSERT INTO public.outbox_messages (event_id, aggregate_type, aggregate_id, aggregate_version, event_type, topic, partition_key, payload) VALUES (gen_random_uuid(), 'X', '1', 1, 'evt', 't', '1', '{}'::jsonb);"

expect_sql_failure \
    "Test 3: promotion_app_role denied direct INSERT on public.idempotency_records" \
    "permission denied for table idempotency_records" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "INSERT INTO public.idempotency_records (scope_owner_id, endpoint_id, idempotency_key, payload_hash, status, lease_expires_at) VALUES (gen_random_uuid(), 'ep', 'k', 'h', 'STARTED', now());"

# -----------------------------------------------------------------------------
# TEST 4: Application roles cannot create or replace objects in trusted schemas
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 4a: promotion_app_role denied CREATE TABLE in schema public" \
    "permission denied for schema public" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "CREATE TABLE public.rogue_table (id int);"

expect_sql_failure \
    "Test 4b: promotion_app_role denied CREATE TABLE in schema promotion_private" \
    "permission denied for schema promotion_private" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "CREATE TABLE promotion_private.rogue_table (id int);"

expect_sql_failure \
    "Test 4c: promotion_app_role denied CREATE OR REPLACE FUNCTION in schema public" \
    "permission denied for schema public" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "CREATE OR REPLACE FUNCTION public.fn_mp08_campaign_lifecycle(uuid, bigint, varchar) RETURNS bigint LANGUAGE sql AS 'SELECT 1::bigint';"

expect_sql_failure \
    "Test 4d: promotion_app_role denied CREATE OR REPLACE FUNCTION in schema promotion_private" \
    "permission denied for schema promotion_private" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "CREATE OR REPLACE FUNCTION promotion_private.fn_set_campaign_lock_witness(uuid, bigint) RETURNS void LANGUAGE sql AS 'SELECT 1';"

declare -a STANDARD_APP_DBS=(
    "${CATALOG_DB_NAME}:${CATALOG_DB_USER}:${CATALOG_DB_PASSWORD}"
    "${CUSTOMER_DB_NAME}:${CUSTOMER_DB_USER}:${CUSTOMER_DB_PASSWORD}"
    "${ORDER_DB_NAME}:${ORDER_DB_USER}:${ORDER_DB_PASSWORD}"
    "${INVENTORY_DB_NAME}:${INVENTORY_DB_USER}:${INVENTORY_DB_PASSWORD}"
    "${PAYMENT_DB_NAME}:${PAYMENT_DB_USER}:${PAYMENT_DB_PASSWORD}"
    "${NOTIFICATION_DB_NAME}:${NOTIFICATION_DB_USER}:${NOTIFICATION_DB_PASSWORD}"
    "${AI_AGENT_DB_NAME}:${AI_AGENT_DB_USER}:${AI_AGENT_DB_PASSWORD}"
)

for entry in "${STANDARD_APP_DBS[@]}"; do
    IFS=":" read -r s_db s_user s_pass <<< "${entry}"
    expect_sql_failure \
        "Test 4e: Runtime app role '${s_user}' denied CREATE TABLE in '${s_db}.public'" \
        "permission denied for schema public" \
        "${s_user}" \
        "${s_pass}" \
        "${s_db}" \
        "CREATE TABLE public.rogue_ddl_probe (id int);"
done

# -----------------------------------------------------------------------------
# TEST 5: Application role cannot execute unauthorized internal/DBA functions
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 5a: promotion_app_role denied execution of promotion_private.fn_set_campaign_lock_witness" \
    "permission denied for schema promotion_private" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT promotion_private.fn_set_campaign_lock_witness(gen_random_uuid(), 1);"

expect_sql_failure \
    "Test 5b: promotion_app_role denied execution of DBA-only promotion_private.fn_admin_inspect_campaign_locks" \
    "permission denied for schema promotion_private" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT * FROM promotion_private.fn_admin_inspect_campaign_locks(gen_random_uuid());"

# Verify promotion_dba_admin CAN execute the DBA-only function
dba_inspect_res="$(psql_exec "${PROMOTION_DBA_ADMIN_USER}" "${PROMOTION_DBA_ADMIN_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT count(*) FROM promotion_private.fn_admin_inspect_campaign_locks(gen_random_uuid());")"
[[ "${dba_inspect_res}" == "0" ]] || fail "Test 5c: Expected promotion_dba_admin to execute fn_admin_inspect_campaign_locks"
pass "Test 5c: promotion_dba_admin authorized to execute promotion_private.fn_admin_inspect_campaign_locks"

# -----------------------------------------------------------------------------
# TEST 6: Application role CAN execute explicitly authorized procedures (fn_mp01..fn_mp08)
# -----------------------------------------------------------------------------
CAMP_ID="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
SKU_ID="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CUST_1="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CUST_2="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CUST_3="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CLAIM_1="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CLAIM_2="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"
CLAIM_3="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "SELECT gen_random_uuid();")"

# 6a. fn_mp08 (0 -> DRAFT) & fn_mp06 (configure item quota = 5) & fn_mp08 (DRAFT -> APPROVED -> WARMED -> ACTIVE)
ep_draft="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 0, 'DRAFT');")"
[[ "${ep_draft}" == "1" ]] || fail "Test 6a: Expected epoch 1 on DRAFT creation, got ${ep_draft}"

psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp06_admin_configure_item('${CAMP_ID}', '${SKU_ID}', 5);" >/dev/null

psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 1, 'APPROVED');
     SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 1, 'WARMED');
     SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 1, 'ACTIVE');" >/dev/null
pass "Test 6a: fn_mp08_campaign_lifecycle and fn_mp06_admin_configure_item executed by promotion_app_role"

# Verify fn_mp06 rejects quota edits when campaign is ACTIVE
expect_sql_failure \
    "Test 6b: fn_mp06_admin_configure_item rejects quota change while campaign is ACTIVE" \
    "QUOTA_EDIT_FORBIDDEN_IN_STATUS: ACTIVE" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp06_admin_configure_item('${CAMP_ID}', '${SKU_ID}', 10);"

# 6c. fn_mp01_writer_claim: Claim qty=2 for Customer 1
mp01_res="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT outcome_code || ':' || http_status || ':' || existing_status
      FROM public.fn_mp01_writer_claim(
          '${CLAIM_1}', '${CAMP_ID}', 1, '${SKU_ID}', '${CUST_1}', 'idem-c1',
          2, now() + interval '30 seconds', now() + interval '10 minutes',
          gen_random_uuid(), '{\"qty\":2}'::jsonb, '{}'::jsonb, '{\"status\":\"CLAIMED\"}'::jsonb, 1
      );
")"
[[ "${mp01_res}" == "CLAIMED_NEW:202:CLAIMED_RESERVED" ]] || fail "Test 6c: Unexpected fn_mp01 result: ${mp01_res}"
pass "Test 6c: fn_mp01_writer_claim atomically persisted claim, incremented item quota, emitted outbox, and completed idempotency"

# 6d. fn_mp01 idempotent retry with same claim_id returns IDEMPOTENT_ALREADY_CLAIMED
mp01_idem="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT outcome_code || ':' || http_status || ':' || existing_status
      FROM public.fn_mp01_writer_claim(
          '${CLAIM_1}', '${CAMP_ID}', 1, '${SKU_ID}', '${CUST_1}', 'idem-c1',
          2, now() + interval '30 seconds', now() + interval '10 minutes',
          gen_random_uuid(), '{\"qty\":2}'::jsonb, '{}'::jsonb, '{\"status\":\"CLAIMED\"}'::jsonb, 1
      );
")"
[[ "${mp01_idem}" == "IDEMPOTENT_ALREADY_CLAIMED:202:CLAIMED_RESERVED" ]] || fail "Test 6d: Unexpected idempotent retry result: ${mp01_idem}"
pass "Test 6d: fn_mp01_writer_claim idempotent replay returned IDEMPOTENT_ALREADY_CLAIMED without double-counting"

# 6e. fn_mp02_reconcile_fenced fences unacknowledged CLAIM_2 -> late fn_mp01 Writer fails with P0002 (CLAIM_LEASE_EXPIRED_FENCED)
mp02_res="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT fenced_created || ':' || current_status || ':' || release_epoch
      FROM public.fn_mp02_reconcile_fenced(
          '${CLAIM_2}', '${CAMP_ID}', 1, '${SKU_ID}', '${CUST_2}', 'idem-c2',
          1, now() - interval '5 seconds'
      );
")"
[[ "${mp02_res}" == "true:ABANDONED_FENCED:1" ]] || fail "Test 6e: Unexpected fn_mp02 result: ${mp02_res}"

expect_sql_failure \
    "Test 6e: Delayed fn_mp01_writer_claim rejected with CLAIM_LEASE_EXPIRED_FENCED (P0002) after fn_mp02 tombstone" \
    "CLAIM_LEASE_EXPIRED_FENCED" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT * FROM public.fn_mp01_writer_claim(
        '${CLAIM_2}', '${CAMP_ID}', 1, '${SKU_ID}', '${CUST_2}', 'idem-c2',
        1, now() + interval '30 seconds', now() + interval '10 minutes',
        gen_random_uuid(), '{\"qty\":1}'::jsonb, '{}'::jsonb, '{}'::jsonb, 1
    );"

# 6f. fn_mp05_order_payment_progress advances CLAIM_1 -> ORDER_MATERIALIZED -> PAYMENT_CONFIRMED
mp05_step1="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp05_order_payment_progress('${CLAIM_1}', '${CAMP_ID}', 'CLAIMED_RESERVED', 'ORDER_MATERIALIZED');")"
mp05_step2="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp05_order_payment_progress('${CLAIM_1}', '${CAMP_ID}', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED');")"
[[ "${mp05_step1}:${mp05_step2}" == "t:t" ]] || fail "Test 6f: fn_mp05 transitions failed (${mp05_step1}:${mp05_step2})"
pass "Test 6f: fn_mp05_order_payment_progress transitioned CLAIM_1 through ORDER_MATERIALIZED to PAYMENT_CONFIRMED"

# 6g. fn_mp03_expire_or_cancel & fn_mp04_restock_finalize on CLAIM_3
psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT * FROM public.fn_mp01_writer_claim(
        '${CLAIM_3}', '${CAMP_ID}', 1, '${SKU_ID}', '${CUST_3}', 'idem-c3',
        2, now() + interval '30 seconds', now() + interval '10 minutes',
        gen_random_uuid(), '{\"qty\":2}'::jsonb, '{}'::jsonb, '{}'::jsonb, 1
    );
" >/dev/null

mp03_res="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT transitioned || ':' || quantity || ':' || release_epoch
      FROM public.fn_mp03_expire_or_cancel(
          '${CLAIM_3}', '${CAMP_ID}', 'EXPIRED', gen_random_uuid(), '{\"reason\":\"timeout\"}'::jsonb, '{}'::jsonb
      );
")"
[[ "${mp03_res}" == "true:2:1" ]] || fail "Test 6g: Unexpected fn_mp03 result: ${mp03_res}"

mp04_first="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp04_restock_finalize('${CLAIM_3}', '${CAMP_ID}', 1);")"
mp04_dup="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp04_restock_finalize('${CLAIM_3}', '${CAMP_ID}', 1);")"
[[ "${mp04_first}:${mp04_dup}" == "t:f" ]] || fail "Test 6g: Expected fn_mp04 first=t, duplicate=f, got ${mp04_first}:${mp04_dup}"
pass "Test 6g: fn_mp03_expire_or_cancel and fn_mp04_restock_finalize executed with duplicate-release protection"

# 6h. fn_mp07_rebuilder_fence_and_snapshot & fn_mp08 reactivation
mp07_res="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT new_epoch || ':' || allocated_quota || ':' || claimed_count || ':' || remaining_stock
      FROM public.fn_mp07_rebuilder_fence_and_snapshot('${CAMP_ID}');
")"
[[ "${mp07_res}" == "2:5:2:3" ]] || fail "Test 6h: Expected 2:5:2:3 from fn_mp07, got ${mp07_res}"

ep_reactivated="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 2, 'ACTIVE');")"
ep_ended="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 2, 'ENDED');")"
[[ "${ep_reactivated}:${ep_ended}" == "2:3" ]] || fail "Test 6h: Unexpected epoch progression ${ep_reactivated}:${ep_ended}"
pass "Test 6h: fn_mp07_rebuilder_fence_and_snapshot and fn_mp08_campaign_lifecycle verified"

# -----------------------------------------------------------------------------
# TEST 7: Unauthorized roles cannot execute privileged procedures
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 7a: promotion_migrator (without SET ROLE) denied EXECUTE on fn_mp08_campaign_lifecycle" \
    "permission denied for function fn_mp08_campaign_lifecycle" \
    "${PROMOTION_MIGRATOR_USER}" \
    "${PROMOTION_MIGRATOR_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_mp08_campaign_lifecycle('${CAMP_ID}', 3, 'RECONCILED');"

expect_sql_failure \
    "Test 7b: promotion_migrator (without SET ROLE) denied EXECUTE on fn_mp01_writer_claim" \
    "permission denied for function fn_mp01_writer_claim" \
    "${PROMOTION_MIGRATOR_USER}" \
    "${PROMOTION_MIGRATOR_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT * FROM public.fn_mp01_writer_claim(gen_random_uuid(), '${CAMP_ID}', 3, '${SKU_ID}', '${CUST_1}', 'k', 1, now(), now(), gen_random_uuid(), '{}'::jsonb, '{}'::jsonb, '{}'::jsonb, 1);"

# -----------------------------------------------------------------------------
# TEST 8: Function ownership is promotion_proc_owner and search_path is safe
# -----------------------------------------------------------------------------
non_owner_funcs="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT count(*)
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
      JOIN pg_catalog.pg_roles r ON r.oid = p.proowner
     WHERE (n.nspname = 'promotion_private' OR (n.nspname = 'public' AND p.proname LIKE 'fn_%'))
       AND r.rolname <> '${PROMOTION_PROC_OWNER_ROLE}';
")"
[[ "${non_owner_funcs}" == "0" ]] || fail "Test 8a: Found ${non_owner_funcs} Promotion functions not owned by ${PROMOTION_PROC_OWNER_ROLE}"

secdef_count="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT count(*)
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname ~ '^fn_mp0[1-8]_'
       AND p.prosecdef = TRUE
       AND array_to_string(p.proconfig, '|') LIKE '%search_path=pg_catalog, promotion_private, public, pg_temp%';
")"
[[ "${secdef_count}" == "8" ]] || fail "Test 8b: Expected all 8 fn_mp01..fn_mp08 to have prosecdef=TRUE and safe search_path (got ${secdef_count}/8)"
pass "Test 8: All Promotion stored procedures and internal functions are owned by promotion_proc_owner with prosecdef=TRUE and 'search_path=pg_catalog, promotion_private, public, pg_temp'"

# -----------------------------------------------------------------------------
# TEST 9: Function EXECUTE privileges are not accidentally granted to PUBLIC
# -----------------------------------------------------------------------------
public_exec_funcs="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    SELECT count(*)
      FROM pg_catalog.pg_proc p
      JOIN pg_catalog.pg_namespace n ON n.oid = p.pronamespace
     WHERE (n.nspname = 'promotion_private' OR (n.nspname = 'public' AND p.proname LIKE 'fn_%'))
       AND pg_catalog.has_function_privilege('public', p.oid, 'EXECUTE');
")"
[[ "${public_exec_funcs}" == "0" ]] || fail "Test 9: Found ${public_exec_funcs} functions granting EXECUTE to PUBLIC!"
pass "Test 9: Zero functions in public or promotion_private grant EXECUTE to PUBLIC"

# -----------------------------------------------------------------------------
# TEST 10: Default privileges remain secure for subsequently created functions
# -----------------------------------------------------------------------------
default_priv_probe="$(psql_exec "${PROMOTION_MIGRATOR_USER}" "${PROMOTION_MIGRATOR_PASSWORD}" "${PROMOTION_DB_NAME}" "
    BEGIN;
    SET LOCAL ROLE ${PROMOTION_PROC_OWNER_ROLE};
    CREATE FUNCTION public.fn_temp_default_acl_probe() RETURNS integer LANGUAGE sql AS \$\$ SELECT 1; \$\$;
    CREATE FUNCTION promotion_private.fn_temp_default_acl_probe_priv() RETURNS integer LANGUAGE sql AS \$\$ SELECT 1; \$\$;
    SELECT pg_catalog.has_function_privilege('public', 'public.fn_temp_default_acl_probe()', 'EXECUTE')
        || ':' || pg_catalog.has_function_privilege('${PROMOTION_APP_USER}', 'public.fn_temp_default_acl_probe()', 'EXECUTE')
        || ':' || pg_catalog.has_function_privilege('public', 'promotion_private.fn_temp_default_acl_probe_priv()', 'EXECUTE')
        || ':' || pg_catalog.has_function_privilege('${PROMOTION_APP_USER}', 'promotion_private.fn_temp_default_acl_probe_priv()', 'EXECUTE');
    ROLLBACK;
" | tail -n 1)"
[[ "${default_priv_probe}" == "false:false:false:false" ]] \
    || fail "Test 10: Newly created functions leaked default EXECUTE privileges (${default_priv_probe})"
pass "Test 10: Default privileges automatically revoke PUBLIC and promotion_app_role EXECUTE on newly created functions in public and promotion_private"

# -----------------------------------------------------------------------------
# TEST 11: Temporary object shadowing (pg_temp) cannot alter privileged function behavior
# -----------------------------------------------------------------------------
shadow_test_out="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" "
    BEGIN;
    -- 1. Create a decoy temporary table shadowing flash_sale_campaigns in pg_temp
    CREATE TEMP TABLE flash_sale_campaigns (LIKE public.flash_sale_campaigns);
    CREATE OR REPLACE FUNCTION pg_temp.fn_poison_trigger() RETURNS trigger LANGUAGE plpgsql AS \$\$
    BEGIN
        RAISE EXCEPTION 'SHADOW_HIJACK_TABLE_TRIGGER_FIRED';
    END;
    \$\$;
    CREATE TRIGGER trg_poison BEFORE INSERT OR UPDATE ON pg_temp.flash_sale_campaigns
        FOR EACH ROW EXECUTE FUNCTION pg_temp.fn_poison_trigger();

    -- 2. Create decoy temporary functions shadowing built-ins in pg_temp
    CREATE OR REPLACE FUNCTION pg_temp.now() RETURNS timestamptz LANGUAGE plpgsql AS \$\$
    BEGIN
        RAISE EXCEPTION 'SHADOW_HIJACK_NOW_FIRED';
    END;
    \$\$;
    CREATE OR REPLACE FUNCTION pg_temp.set_config(text, text, boolean) RETURNS text LANGUAGE plpgsql AS \$\$
    BEGIN
        RAISE EXCEPTION 'SHADOW_HIJACK_SET_CONFIG_FIRED';
    END;
    \$\$;

    -- 3. Invoke SECURITY DEFINER procedure fn_mp08_campaign_lifecycle in the same session,
    --    then query pg_temp vs public in the next SQL statement (after CommandCounterIncrement)
    SELECT public.fn_mp08_campaign_lifecycle('00000000-0000-0000-0000-000000000999'::uuid, 0, 'DRAFT');
    SELECT (SELECT count(*) FROM pg_temp.flash_sale_campaigns)
        || ':' || (SELECT count(*) FROM public.flash_sale_campaigns WHERE campaign_id = '00000000-0000-0000-0000-000000000999'::uuid);
    ROLLBACK;
" | tail -n 1)"
[[ "${shadow_test_out}" == "0:1" ]] \
    || fail "Test 11: Temporary object shadowing test unexpected output: ${shadow_test_out}"
pass "Test 11: pg_temp table and function shadowing completely neutralized by 'search_path = pg_catalog, promotion_private, public, pg_temp' and explicit schema qualification"

# -----------------------------------------------------------------------------
# TEST 12: Migration role and DBA role cannot be used as runtime application identity
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 12a: promotion_migrator rejected by public.fn_verify_runtime_app_identity()" \
    "FORBIDDEN_RUNTIME_DB_IDENTITY" \
    "${PROMOTION_MIGRATOR_USER}" \
    "${PROMOTION_MIGRATOR_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_verify_runtime_app_identity();"

expect_sql_failure \
    "Test 12b: promotion_dba_admin rejected by public.fn_verify_runtime_app_identity()" \
    "FORBIDDEN_RUNTIME_DB_IDENTITY" \
    "${PROMOTION_DBA_ADMIN_USER}" \
    "${PROMOTION_DBA_ADMIN_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_verify_runtime_app_identity();"

expect_sql_failure \
    "Test 12c: promotion_migrator denied runtime SELECT on public.flash_sale_campaigns" \
    "permission denied for table flash_sale_campaigns" \
    "${PROMOTION_MIGRATOR_USER}" \
    "${PROMOTION_MIGRATOR_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT * FROM public.flash_sale_campaigns;"

runtime_app_ok="$(psql_exec "${PROMOTION_APP_USER}" "${PROMOTION_APP_PASSWORD}" "${PROMOTION_DB_NAME}" \
    "SELECT public.fn_verify_runtime_app_identity();")"
[[ "${runtime_app_ok}" == "t" ]] || fail "Test 12d: promotion_app_role failed fn_verify_runtime_app_identity()"
pass "Test 12d: promotion_app_role accepted as valid runtime application identity"

declare -a MIGRATOR_CHECKS=(
    "${CATALOG_DB_NAME}:${CATALOG_MIGRATOR_USER}:${CATALOG_MIGRATOR_PASSWORD}:${CATALOG_DB_USER}:${CATALOG_DB_PASSWORD}"
    "${CUSTOMER_DB_NAME}:${CUSTOMER_MIGRATOR_USER}:${CUSTOMER_MIGRATOR_PASSWORD}:${CUSTOMER_DB_USER}:${CUSTOMER_DB_PASSWORD}"
    "${ORDER_DB_NAME}:${ORDER_MIGRATOR_USER}:${ORDER_MIGRATOR_PASSWORD}:${ORDER_DB_USER}:${ORDER_DB_PASSWORD}"
    "${INVENTORY_DB_NAME}:${INVENTORY_MIGRATOR_USER}:${INVENTORY_MIGRATOR_PASSWORD}:${INVENTORY_DB_USER}:${INVENTORY_DB_PASSWORD}"
    "${PAYMENT_DB_NAME}:${PAYMENT_MIGRATOR_USER}:${PAYMENT_MIGRATOR_PASSWORD}:${PAYMENT_DB_USER}:${PAYMENT_DB_PASSWORD}"
    "${NOTIFICATION_DB_NAME}:${NOTIFICATION_MIGRATOR_USER}:${NOTIFICATION_MIGRATOR_PASSWORD}:${NOTIFICATION_DB_USER}:${NOTIFICATION_DB_PASSWORD}"
    "${AI_AGENT_DB_NAME}:${AI_AGENT_MIGRATOR_USER}:${AI_AGENT_MIGRATOR_PASSWORD}:${AI_AGENT_DB_USER}:${AI_AGENT_DB_PASSWORD}"
)

for entry in "${MIGRATOR_CHECKS[@]}"; do
    IFS=":" read -r m_db m_user m_pass a_user a_pass <<< "${entry}"
    expect_sql_failure \
        "Test 12e: Migration role '${m_user}' rejected as runtime identity on '${m_db}'" \
        "FORBIDDEN_RUNTIME_DB_IDENTITY" \
        "${m_user}" \
        "${m_pass}" \
        "${m_db}" \
        "SELECT public.fn_verify_runtime_app_identity();"

    a_ok="$(psql_exec "${a_user}" "${a_pass}" "${m_db}" "SELECT public.fn_verify_runtime_app_identity();")"
    [[ "${a_ok}" == "t" ]] || fail "Test 12e: Runtime role '${a_user}' failed runtime identity check on '${m_db}'"
done
pass "Test 12e: All 7 standard service runtime roles accepted and all 7 migration roles rejected as runtime identities"

# -----------------------------------------------------------------------------
# TEST 13: Cross-database access remains denied across all roles
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 13a: promotion_app_role denied connection to order_db" \
    "permission denied for database" \
    "${PROMOTION_APP_USER}" \
    "${PROMOTION_APP_PASSWORD}" \
    "${ORDER_DB_NAME}" \
    "SELECT 1;"

expect_sql_failure \
    "Test 13b: order_svc_user denied connection to promotion_db" \
    "permission denied for database" \
    "${ORDER_DB_USER}" \
    "${ORDER_DB_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "SELECT 1;"

expect_sql_failure \
    "Test 13c: ai_agent_svc_user denied connection to customer_db (FR-AI-002)" \
    "permission denied for database" \
    "${AI_AGENT_DB_USER}" \
    "${AI_AGENT_DB_PASSWORD}" \
    "${CUSTOMER_DB_NAME}" \
    "SELECT 1;"

expect_sql_failure \
    "Test 13d: catalog_migrator denied connection to inventory_db" \
    "permission denied for database" \
    "${CATALOG_MIGRATOR_USER}" \
    "${CATALOG_MIGRATOR_PASSWORD}" \
    "${INVENTORY_DB_NAME}" \
    "SELECT 1;"

# -----------------------------------------------------------------------------
# TEST 14: Pre-Lock Witness Trigger Guard (SPEC-CH01-T6) & pgvector Ceiling (SPEC-CH06-T1)
# -----------------------------------------------------------------------------
expect_sql_failure \
    "Test 14a (SPEC-CH01-T6): Direct privileged DBA UPDATE on flash_sale_items without locking flash_sale_campaigns first is blocked by trg_verify_items_campaign_prelocked (P0004)" \
    "LOCK_ORDER_VIOLATION" \
    "${PROMOTION_DBA_ADMIN_USER}" \
    "${PROMOTION_DBA_ADMIN_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "UPDATE public.flash_sale_items SET allocated_quota = 99 WHERE campaign_id = '${CAMP_ID}';"

expect_sql_failure \
    "Test 14b (SPEC-CH01-T6): Direct privileged DBA UPDATE on flash_sale_claims without locking flash_sale_campaigns first is blocked by trg_verify_claims_campaign_prelocked (P0004)" \
    "LOCK_ORDER_VIOLATION" \
    "${PROMOTION_DBA_ADMIN_USER}" \
    "${PROMOTION_DBA_ADMIN_PASSWORD}" \
    "${PROMOTION_DB_NAME}" \
    "UPDATE public.flash_sale_claims SET status = 'CANCELLED' WHERE claim_id = '${CLAIM_1}';"

expect_sql_failure \
    "Test 14c (SPEC-CH06-T1): embedding_index_generations rejects 3072d VECTOR_FP32 (> 2000d HNSW ceiling)" \
    "chk_embedding_hnsw_dimension_ceiling" \
    "${AI_AGENT_DB_USER}" \
    "${AI_AGENT_DB_PASSWORD}" \
    "${AI_AGENT_DB_NAME}" \
    "INSERT INTO public.embedding_index_generations (generation_id, provider_name, model_id, model_version, dimensions, index_storage_type) VALUES (gen_random_uuid(), 'openai', 'text-embedding-3-large', 'v1', 3072, 'VECTOR_FP32');"

psql_exec "${AI_AGENT_DB_USER}" "${AI_AGENT_DB_PASSWORD}" "${AI_AGENT_DB_NAME}" "
    BEGIN;
    INSERT INTO public.embedding_index_generations (generation_id, provider_name, model_id, model_version, dimensions, index_storage_type)
    VALUES (gen_random_uuid(), 'openai', 'text-embedding-3-large', 'v1', 3072, 'HALFVEC_FP16');
    ROLLBACK;
" >/dev/null
pass "Test 14d (SPEC-CH06-T1): embedding_index_generations accepts 3072d HALFVEC_FP16 (<= 4000d HNSW ceiling)"

echo "============================================================================="
echo "[SUCCESS] All ${PASS_COUNT} M1.2 PostgreSQL security and privilege checks PASSED!"
echo "============================================================================="
