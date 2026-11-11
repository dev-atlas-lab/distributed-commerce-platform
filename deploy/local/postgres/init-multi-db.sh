#!/usr/bin/env bash
# =============================================================================
# PostgreSQL 17 Multi-Database & Least-Privilege Role Bootstrap (M1.1)
# Implements ADR-0002 (Database-per-Service Isolation) and ADR-0005 (Promotion
# 4-Role Separation Foundation).
# =============================================================================
set -euo pipefail

psql_super() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$1"
}

create_isolated_service_db() {
    local db_name="$1"
    local db_user="$2"
    local db_pass="$3"

    echo "[init-multi-db] Provisioning isolated database '${db_name}' and role '${db_user}'..."

    psql_super "postgres" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${db_user}') THEN
                CREATE ROLE ${db_user} WITH
                    LOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    PASSWORD '${db_pass}';
            END IF;
        END
        \$\$;

        SELECT 'CREATE DATABASE ${db_name} OWNER ${db_user}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec

        REVOKE ALL ON DATABASE ${db_name} FROM PUBLIC;
        GRANT CONNECT ON DATABASE ${db_name} TO ${db_user};
EOSQL

    psql_super "${db_name}" <<-EOSQL
        REVOKE CREATE ON SCHEMA public FROM PUBLIC;
        GRANT USAGE, CREATE ON SCHEMA public TO ${db_user};
EOSQL
}

# 1. Standard Isolated Bounded-Context Databases (ADR-0002)
create_isolated_service_db "${CATALOG_DB_NAME}"      "${CATALOG_DB_USER}"      "${CATALOG_DB_PASSWORD}"
create_isolated_service_db "${CUSTOMER_DB_NAME}"     "${CUSTOMER_DB_USER}"     "${CUSTOMER_DB_PASSWORD}"
create_isolated_service_db "${ORDER_DB_NAME}"        "${ORDER_DB_USER}"        "${ORDER_DB_PASSWORD}"
create_isolated_service_db "${INVENTORY_DB_NAME}"    "${INVENTORY_DB_USER}"    "${INVENTORY_DB_PASSWORD}"
create_isolated_service_db "${PAYMENT_DB_NAME}"      "${PAYMENT_DB_USER}"      "${PAYMENT_DB_PASSWORD}"
create_isolated_service_db "${NOTIFICATION_DB_NAME}" "${NOTIFICATION_DB_USER}" "${NOTIFICATION_DB_PASSWORD}"
create_isolated_service_db "${AI_AGENT_DB_NAME}"     "${AI_AGENT_DB_USER}"     "${AI_AGENT_DB_PASSWORD}"

# 2. Enable bounded-context specific extensions (ADR-0007 & ADR-0008)
echo "[init-multi-db] Enabling pg_trgm in '${CATALOG_DB_NAME}' and pgvector in '${AI_AGENT_DB_NAME}'..."
psql_super "${CATALOG_DB_NAME}" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
EOSQL

psql_super "${AI_AGENT_DB_NAME}" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector;
EOSQL

# 3. Promotion Database — 4-Role Least-Privilege Separation (ADR-0005 / CH-01 / M0.3.1)
#    - promotion_proc_owner : NOLOGIN NOSUPERUSER (will own protected tables & SECURITY DEFINER functions in M1.2)
#    - promotion_migrator   : LOGIN NOSUPERUSER (CI/CD DDL migration role; member of promotion_proc_owner)
#    - promotion_app_role   : LOGIN NOSUPERUSER (runtime application role; USAGE only on public schema, no CREATE)
#    - promotion_dba_admin  : LOGIN NOSUPERUSER (break-glass administrative role)
echo "[init-multi-db] Provisioning '${PROMOTION_DB_NAME}' with 4-role separation (ADR-0005)..."
psql_super "postgres" <<-EOSQL
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${PROMOTION_PROC_OWNER_ROLE}') THEN
            CREATE ROLE ${PROMOTION_PROC_OWNER_ROLE} WITH
                NOLOGIN
                NOSUPERUSER
                NOCREATEDB
                NOCREATEROLE
                NOINHERIT;
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${PROMOTION_MIGRATOR_USER}') THEN
            CREATE ROLE ${PROMOTION_MIGRATOR_USER} WITH
                LOGIN
                NOSUPERUSER
                NOCREATEDB
                NOCREATEROLE
                NOINHERIT
                PASSWORD '${PROMOTION_MIGRATOR_PASSWORD}';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${PROMOTION_APP_USER}') THEN
            CREATE ROLE ${PROMOTION_APP_USER} WITH
                LOGIN
                NOSUPERUSER
                NOCREATEDB
                NOCREATEROLE
                NOINHERIT
                PASSWORD '${PROMOTION_APP_PASSWORD}';
        END IF;

        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${PROMOTION_DBA_ADMIN_USER}') THEN
            CREATE ROLE ${PROMOTION_DBA_ADMIN_USER} WITH
                LOGIN
                NOSUPERUSER
                NOCREATEDB
                NOCREATEROLE
                NOINHERIT
                PASSWORD '${PROMOTION_DBA_ADMIN_PASSWORD}';
        END IF;
    END
    \$\$;

    GRANT ${PROMOTION_PROC_OWNER_ROLE} TO ${PROMOTION_MIGRATOR_USER};

    SELECT 'CREATE DATABASE ${PROMOTION_DB_NAME} OWNER ${PROMOTION_PROC_OWNER_ROLE}'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${PROMOTION_DB_NAME}')\gexec

    REVOKE ALL ON DATABASE ${PROMOTION_DB_NAME} FROM PUBLIC;
    GRANT CONNECT ON DATABASE ${PROMOTION_DB_NAME} TO
        ${PROMOTION_MIGRATOR_USER},
        ${PROMOTION_APP_USER},
        ${PROMOTION_DBA_ADMIN_USER};
EOSQL

psql_super "${PROMOTION_DB_NAME}" <<-EOSQL
    REVOKE CREATE ON SCHEMA public FROM PUBLIC;
    REVOKE ALL ON SCHEMA public FROM ${PROMOTION_APP_USER};
    GRANT USAGE ON SCHEMA public TO ${PROMOTION_APP_USER};
    GRANT USAGE, CREATE ON SCHEMA public TO
        ${PROMOTION_PROC_OWNER_ROLE},
        ${PROMOTION_MIGRATOR_USER},
        ${PROMOTION_DBA_ADMIN_USER};

    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_PROC_OWNER_ROLE} IN SCHEMA public
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_MIGRATOR_USER} IN SCHEMA public
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
EOSQL

echo "[init-multi-db] All 8 isolated service databases and least-privilege roles initialized successfully."
