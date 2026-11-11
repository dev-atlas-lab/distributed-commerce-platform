# Database Schema, Naming & Authoring Conventions (`DATABASE_CONVENTIONS.md`)

- **Document ID:** `DCP-DOC-STD-001`
- **Repository:** `dev-atlas-lab/distributed-commerce-platform`
- **Milestone:** `M1.2 — Database Foundation & Promotion Security Implementation`
- **Status:** `IMPLEMENTED`
- **Last Updated:** 2026-11-11

---

## 1. Identifier & Constraint Naming Standards

All PostgreSQL identifiers across Java (`catalog`, `inventory`, `order`, `payment`), .NET (`customer`, `promotion`, `notification`), and Python (`ai-worker`) databases MUST use lowercase `snake_case` without quoted mixed-case identifiers:

| Object Type | Pattern | Example |
| :--- | :--- | :--- |
| **Database** | `<bounded_context>_db` | `catalog_db`, `promotion_db`, `ai_agent_db` |
| **Schema** | `public` (external/tables) or `<context>_private` (internal) | `public`, `promotion_private` |
| **Table** | Plural `snake_case` noun | `flash_sale_campaigns`, `outbox_messages`, `idempotency_records` |
| **Column** | Singular `snake_case` | `campaign_id`, `created_at`, `aggregate_version` |
| **Primary Key Constraint** | `pk_<table>` | `pk_flash_sale_claims` |
| **Foreign Key Constraint** | `fk_<table>_<target>` | `fk_flash_sale_claims_campaign` |
| **Unique Constraint / Index** | `uq_<table>_<columns_or_rule>` | `uq_flash_claim_idem`, `uq_flash_active_customer_sku` |
| **Check Constraint** | `chk_<table>_<rule>` | `chk_flash_sale_claims_status`, `chk_embedding_hnsw_dimension_ceiling` |
| **Secondary Index** | `idx_<table>_<columns_or_purpose>` | `idx_outbox_messages_unpublished_head` |
| **Stored Procedure / Function** | `fn_<domain_or_mp>_<action>` | `fn_mp01_writer_claim`, `fn_verify_campaign_prelocked` |
| **Trigger** | `trg_<action_or_guard>` | `trg_verify_claims_campaign_prelocked` |

---

## 2. Canonical PostgreSQL 17 Data Types

| Semantic Concept | Mandatory PostgreSQL Type | Forbidden Types & Rationale |
| :--- | :--- | :--- |
| **Entity / Aggregate Primary Key** | `UUID` | Never use `SERIAL`/`INTEGER` for externally visible domain IDs (enumeration & sharding risk). |
| **Timestamps** | `TIMESTAMPTZ` (stored in UTC, defaulted via `pg_catalog.now()`) | Never use `TIMESTAMP WITHOUT TIME ZONE` (ambiguous across daylight saving / multi-region nodes). |
| **Monetary Amounts** | `NUMERIC(19, 4)` paired with `CHAR(3)` ISO-4217 `currency` | Never use `FLOAT` / `REAL` / `DOUBLE PRECISION` (IEEE 754 binary rounding errors) or PostgreSQL `MONEY` (locale-dependent formatting). |
| **Optimistic Concurrency / Epoch** | `BIGINT NOT NULL DEFAULT 0` (`version` / `current_epoch`) | Avoid 32-bit `INTEGER` on monotonically increasing sequence/epoch counters. |
| **State / Status Enumerations** | `VARCHAR(32)` with explicit `CHECK (status IN (...))` | Prefer `VARCHAR` + named `CHECK` constraint over `CREATE TYPE ... AS ENUM` so adding or retiring states in future migrations does not require catalog-locking `ALTER TYPE` workarounds. |
| **Structured Payloads / Headers** | `JSONB` | Never use plain `JSON` (lacks binary indexing and canonical key deduplication). |
| **Vector Embeddings (`ai_agent_db`)** | `vector(D)` (`<= 2000d`) or `halfvec(D)` (`2001d..4000d`) | Respect `pgvector` 8 KB page HNSW index limits (`CH-06`). |

---

## 3. Versioned Migration Authoring Rules

1. **Filename Format**:
   - Every migration file MUST match `^V[0-9]{3}__[a-z0-9_]+\.sql$` (e.g., `V001__baseline_messaging_and_idempotency.sql`, `V002__promotion_security_definer_procedures.sql`).
2. **Immutability & SHA-256 Verification**:
   - Once committed and applied, a migration file MUST NEVER be modified. [`scripts/run-migrations.sh`](file:///home/anhltn/projects/distributed-commerce-platform/scripts/run-migrations.sh) records the `SHA-256` hash of each script in `public.schema_migration_history` and aborts immediately (`IMMUTABILITY_VIOLATION`) if an applied script's hash changes.
3. **Execution Identity**:
   - Migrations MUST execute under the service's `<service>_migrator` role (never the runtime application role `<service>_svc_user` / `promotion_app_role` and never `postgres`).
   - In `promotion_db`, migrations MUST begin with `SET LOCAL ROLE promotion_proc_owner;` and conclude with `RESET ROLE;` so all objects are owned by `promotion_proc_owner` (`NOLOGIN NOSUPERUSER`).

---

## 4. `SECURITY DEFINER` Authoring Checklist (`ADR-0005` / `CH-01`)

Any `SECURITY DEFINER` function in PostgreSQL MUST satisfy all seven mandatory rules:
1. **Non-Login, Non-Superuser Owner**: Owned by a dedicated `NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT` role (`promotion_proc_owner`).
2. **Explicit `search_path` with `pg_temp` Last**: Declare `SET search_path = pg_catalog, promotion_private, public, pg_temp` on the function header so PostgreSQL never implicitly prepends `pg_temp` ahead of trusted schemas.
3. **Revoked Schema `CREATE`**: All schemas listed before `pg_temp` in `search_path` (`promotion_private`, `public`) MUST have `CREATE` revoked from `PUBLIC` and all untrusted/application roles.
4. **Explicit Schema & Operator Qualification**: Qualify all tables (`public.flash_sale_campaigns`), helper functions (`promotion_private.fn_set_campaign_lock_witness`), built-ins (`pg_catalog.now()`, `pg_catalog.set_config()`), and critical operators (`OPERATOR(pg_catalog.=)`).
   - *PostgreSQL Parser Note*: SQL grammar constructs (`COALESCE(...)`, `GREATEST(...)`, `LEAST(...)`, `NULLIF(...)`) are reserved syntax keywords in `gram.y`, not `pg_catalog` functions, and must be written as `COALESCE(...)` / `GREATEST(...)`.
5. **Global Default `PUBLIC` `EXECUTE` Revocation**: Execute `ALTER DEFAULT PRIVILEGES FOR ROLE <owner> REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC;` **without** `IN SCHEMA` (because PostgreSQL's built-in `PUBLIC=X` default lives in the global `defaclnamespace = 0` ACL).
6. **Explicit Per-Function `REVOKE ALL` & Least-Privilege `GRANT EXECUTE`**: Explicitly `REVOKE ALL ON FUNCTION ... FROM PUBLIC, <migrator_role>;` and `GRANT EXECUTE ON FUNCTION ... TO <app_role>;`.
7. **Canonical Lock Ordering**: In `promotion_db`, acquire table/row locks strictly in the order:
   `1. public.flash_sale_campaigns -> 2. public.flash_sale_claims (ORDER BY claim_id ASC) -> 3. public.flash_sale_items (ORDER BY sku_id ASC) -> 4. public.outbox_messages -> 5. public.idempotency_records`.
