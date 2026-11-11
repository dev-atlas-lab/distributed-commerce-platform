#!/usr/bin/env bash
# =============================================================================
# PostgreSQL 17 Multi-Database & Least-Privilege Role Bootstrap (M1.1 / M1.2)
# Implements:
#   - ADR-0002: Database-per-Service Isolation across 8 bounded-context DBs
#   - M1.2 Phase A: Dedicated migration role (<service>_migrator) vs runtime
#     application role (<service>_svc_user) for EVERY service database.
#     Zero application roles own schemas or possess CREATE on schema public.
#   - ADR-0005 / CH-01: 4-Role Least-Privilege Model for promotion_db
#     (promotion_proc_owner [NOLOGIN], promotion_migrator, promotion_app_role,
#     promotion_dba_admin) + dedicated trusted schema promotion_private.
# =============================================================================
set -euo pipefail

psql_super() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$1"
}

create_isolated_service_db() {
    local db_name="$1"
    local app_user="$2"
    local app_pass="$3"
    local mig_user="$4"
    local mig_pass="$5"

    echo "[init-multi-db] Provisioning isolated database '${db_name}' (migrator='${mig_user}', app='${app_user}')..."

    psql_super "postgres" <<-EOSQL
        DO \$\$
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${mig_user}') THEN
                CREATE ROLE ${mig_user} WITH
                    LOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    PASSWORD '${mig_pass}';
            ELSE
                ALTER ROLE ${mig_user} WITH
                    LOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    PASSWORD '${mig_pass}';
            END IF;

            IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${app_user}') THEN
                CREATE ROLE ${app_user} WITH
                    LOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    PASSWORD '${app_pass}';
            ELSE
                ALTER ROLE ${app_user} WITH
                    LOGIN
                    NOSUPERUSER
                    NOCREATEDB
                    NOCREATEROLE
                    NOINHERIT
                    PASSWORD '${app_pass}';
            END IF;
        END
        \$\$;

        SELECT 'CREATE DATABASE ${db_name} OWNER ${mig_user}'
        WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${db_name}')\gexec

        ALTER DATABASE ${db_name} OWNER TO ${mig_user};
        REVOKE ALL ON DATABASE ${db_name} FROM PUBLIC;
        GRANT CONNECT ON DATABASE ${db_name} TO ${mig_user}, ${app_user};
EOSQL

    psql_super "${db_name}" <<-EOSQL
        ALTER SCHEMA public OWNER TO ${mig_user};
        REVOKE ALL ON SCHEMA public FROM PUBLIC;
        REVOKE ALL ON SCHEMA public FROM ${app_user};
        GRANT USAGE, CREATE ON SCHEMA public TO ${mig_user};
        GRANT USAGE ON SCHEMA public TO ${app_user};

        ALTER DEFAULT PRIVILEGES FOR ROLE ${mig_user} IN SCHEMA public
            REVOKE ALL ON TABLES FROM PUBLIC;
        ALTER DEFAULT PRIVILEGES FOR ROLE ${mig_user} IN SCHEMA public
            GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO ${app_user};
        ALTER DEFAULT PRIVILEGES FOR ROLE ${mig_user} IN SCHEMA public
            GRANT USAGE, SELECT ON SEQUENCES TO ${app_user};
        -- Note: In PostgreSQL, default PUBLIC EXECUTE on functions is a global default privilege
        -- (defaclnamespace = 0) and MUST be revoked without 'IN SCHEMA' to take effect in pg_default_acl!
        ALTER DEFAULT PRIVILEGES FOR ROLE ${mig_user}
            REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
        ALTER DEFAULT PRIVILEGES FOR ROLE ${app_user}
            REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

        -- Runtime identity guard: ensures migration role or superuser cannot be used as runtime app identity
        CREATE OR REPLACE FUNCTION public.fn_verify_runtime_app_identity()
        RETURNS BOOLEAN
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = pg_catalog, public, pg_temp
        AS \$\$
        BEGIN
            IF session_user <> '${app_user}'
               OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = session_user AND (rolsuper OR rolcreatedb OR rolcreaterole))
               OR pg_catalog.has_schema_privilege(session_user, 'public', 'CREATE') THEN
                RAISE EXCEPTION 'FORBIDDEN_RUNTIME_DB_IDENTITY: role "%" is not authorized as runtime application identity for % (expected "${app_user}")',
                    session_user, current_database()
                    USING ERRCODE = '42501';
            END IF;
            RETURN TRUE;
        END;
        \$\$;

        ALTER FUNCTION public.fn_verify_runtime_app_identity() OWNER TO ${mig_user};
        REVOKE ALL ON FUNCTION public.fn_verify_runtime_app_identity() FROM PUBLIC;
        GRANT EXECUTE ON FUNCTION public.fn_verify_runtime_app_identity() TO ${app_user}, ${mig_user};
EOSQL
}

# 1. Standard Isolated Bounded-Context Databases (ADR-0002 + M1.2 Migrator/App Role Separation)
create_isolated_service_db "${CATALOG_DB_NAME}"      "${CATALOG_DB_USER}"      "${CATALOG_DB_PASSWORD}"      "${CATALOG_MIGRATOR_USER}"      "${CATALOG_MIGRATOR_PASSWORD}"
create_isolated_service_db "${CUSTOMER_DB_NAME}"     "${CUSTOMER_DB_USER}"     "${CUSTOMER_DB_PASSWORD}"     "${CUSTOMER_MIGRATOR_USER}"     "${CUSTOMER_MIGRATOR_PASSWORD}"
create_isolated_service_db "${ORDER_DB_NAME}"        "${ORDER_DB_USER}"        "${ORDER_DB_PASSWORD}"        "${ORDER_MIGRATOR_USER}"        "${ORDER_MIGRATOR_PASSWORD}"
create_isolated_service_db "${INVENTORY_DB_NAME}"    "${INVENTORY_DB_USER}"    "${INVENTORY_DB_PASSWORD}"    "${INVENTORY_MIGRATOR_USER}"    "${INVENTORY_MIGRATOR_PASSWORD}"
create_isolated_service_db "${PAYMENT_DB_NAME}"      "${PAYMENT_DB_USER}"      "${PAYMENT_DB_PASSWORD}"      "${PAYMENT_MIGRATOR_USER}"      "${PAYMENT_MIGRATOR_PASSWORD}"
create_isolated_service_db "${NOTIFICATION_DB_NAME}" "${NOTIFICATION_DB_USER}" "${NOTIFICATION_DB_PASSWORD}" "${NOTIFICATION_MIGRATOR_USER}" "${NOTIFICATION_MIGRATOR_PASSWORD}"
create_isolated_service_db "${AI_AGENT_DB_NAME}"     "${AI_AGENT_DB_USER}"     "${AI_AGENT_DB_PASSWORD}"     "${AI_AGENT_MIGRATOR_USER}"     "${AI_AGENT_MIGRATOR_PASSWORD}"

# 2. Enable bounded-context specific extensions (ADR-0007 & ADR-0008)
echo "[init-multi-db] Enabling pg_trgm in '${CATALOG_DB_NAME}' and pgvector in '${AI_AGENT_DB_NAME}'..."
psql_super "${CATALOG_DB_NAME}" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;
EOSQL

psql_super "${AI_AGENT_DB_NAME}" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;
EOSQL

# 3. Promotion Database — 4-Role Least-Privilege Separation & Trusted Schema (ADR-0005 / CH-01 / M1.2)
#    - promotion_proc_owner : NOLOGIN NOSUPERUSER (owns promotion_db, schemas public & promotion_private,
#                             protected tables, and SECURITY DEFINER functions fn_mp01..fn_mp08)
#    - promotion_migrator   : LOGIN NOSUPERUSER NOINHERIT (CI/CD DDL migration role; member of promotion_proc_owner)
#    - promotion_app_role   : LOGIN NOSUPERUSER NOINHERIT (runtime application role; USAGE only on public schema,
#                             no CREATE on any schema, no access to promotion_private, no direct table DML)
#    - promotion_dba_admin  : LOGIN NOSUPERUSER NOINHERIT (break-glass administrative role)
echo "[init-multi-db] Provisioning '${PROMOTION_DB_NAME}' with 4-role separation and trusted schema (ADR-0005)..."
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
        ELSE
            ALTER ROLE ${PROMOTION_PROC_OWNER_ROLE} WITH
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
        ELSE
            ALTER ROLE ${PROMOTION_MIGRATOR_USER} WITH
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
        ELSE
            ALTER ROLE ${PROMOTION_APP_USER} WITH
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
        ELSE
            ALTER ROLE ${PROMOTION_DBA_ADMIN_USER} WITH
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

    ALTER DATABASE ${PROMOTION_DB_NAME} OWNER TO ${PROMOTION_PROC_OWNER_ROLE};
    REVOKE ALL ON DATABASE ${PROMOTION_DB_NAME} FROM PUBLIC;
    GRANT CONNECT, TEMP ON DATABASE ${PROMOTION_DB_NAME} TO
        ${PROMOTION_MIGRATOR_USER},
        ${PROMOTION_APP_USER},
        ${PROMOTION_DBA_ADMIN_USER};
EOSQL

psql_super "${PROMOTION_DB_NAME}" <<-EOSQL
    ALTER SCHEMA public OWNER TO ${PROMOTION_PROC_OWNER_ROLE};
    CREATE SCHEMA IF NOT EXISTS promotion_private AUTHORIZATION ${PROMOTION_PROC_OWNER_ROLE};

    REVOKE ALL ON SCHEMA public FROM PUBLIC;
    REVOKE ALL ON SCHEMA public FROM ${PROMOTION_APP_USER};
    GRANT USAGE ON SCHEMA public TO ${PROMOTION_APP_USER};
    GRANT USAGE, CREATE ON SCHEMA public TO
        ${PROMOTION_PROC_OWNER_ROLE},
        ${PROMOTION_MIGRATOR_USER},
        ${PROMOTION_DBA_ADMIN_USER};

    REVOKE ALL ON SCHEMA promotion_private FROM PUBLIC;
    REVOKE ALL ON SCHEMA promotion_private FROM ${PROMOTION_APP_USER};
    GRANT USAGE, CREATE ON SCHEMA promotion_private TO
        ${PROMOTION_PROC_OWNER_ROLE},
        ${PROMOTION_MIGRATOR_USER};
    GRANT USAGE ON SCHEMA promotion_private TO ${PROMOTION_DBA_ADMIN_USER};

    -- Default privileges in promotion_db:
    -- CRITICAL POSTGRESQL ENGINE FACT (src/backend/catalog/aclchk.c):
    -- PostgreSQL grants PUBLIC=X on functions in the GLOBAL default ACL (defaclnamespace = 0),
    -- and per-schema default ACLs are additive over global default ACLs. Therefore,
    -- 'REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC' MUST be executed globally (without 'IN SCHEMA')!
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_PROC_OWNER_ROLE}
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_MIGRATOR_USER}
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_DBA_ADMIN_USER}
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_APP_USER}
        REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;

    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_PROC_OWNER_ROLE}
        REVOKE ALL ON TABLES FROM PUBLIC;
    ALTER DEFAULT PRIVILEGES FOR ROLE ${PROMOTION_PROC_OWNER_ROLE}
        REVOKE ALL ON SEQUENCES FROM PUBLIC;

    -- Runtime identity guard for promotion_db: only promotion_app_role is valid at runtime
    CREATE OR REPLACE FUNCTION public.fn_verify_runtime_app_identity()
    RETURNS BOOLEAN
    LANGUAGE plpgsql
    SECURITY DEFINER
    SET search_path = pg_catalog, promotion_private, public, pg_temp
    AS \$\$
    BEGIN
        IF session_user <> '${PROMOTION_APP_USER}'
           OR EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = session_user AND (rolsuper OR rolcreatedb OR rolcreaterole))
           OR pg_catalog.has_schema_privilege(session_user, 'public', 'CREATE')
           OR pg_catalog.has_schema_privilege(session_user, 'promotion_private', 'CREATE')
           OR pg_catalog.pg_has_role(session_user, '${PROMOTION_PROC_OWNER_ROLE}', 'MEMBER')
           OR pg_catalog.pg_has_role(session_user, '${PROMOTION_MIGRATOR_USER}', 'MEMBER')
           OR pg_catalog.pg_has_role(session_user, '${PROMOTION_DBA_ADMIN_USER}', 'MEMBER') THEN
            RAISE EXCEPTION 'FORBIDDEN_RUNTIME_DB_IDENTITY: role "%" is not authorized as runtime application identity for promotion_db (expected "${PROMOTION_APP_USER}")',
                session_user
                USING ERRCODE = '42501';
        END IF;
        RETURN TRUE;
    END;
    \$\$;

    ALTER FUNCTION public.fn_verify_runtime_app_identity() OWNER TO ${PROMOTION_PROC_OWNER_ROLE};
    REVOKE ALL ON FUNCTION public.fn_verify_runtime_app_identity() FROM PUBLIC;
    GRANT EXECUTE ON FUNCTION public.fn_verify_runtime_app_identity() TO
        ${PROMOTION_APP_USER},
        ${PROMOTION_MIGRATOR_USER},
        ${PROMOTION_DBA_ADMIN_USER};
EOSQL

echo "[init-multi-db] All 8 isolated service databases and least-privilege roles initialized successfully."
