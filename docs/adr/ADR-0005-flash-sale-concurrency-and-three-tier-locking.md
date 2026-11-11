# ADR-0005: Flash Sale Concurrency Architecture, Least-Privilege Stored Procedures & Fenced Reconciliation

- **Status:** `DESIGN_ACCEPTED` (`Q4 Option A` Accepted in `M0.1`; `CH-01`, `HD-01`, `HD-02`, `HD-03` Frozen as `DESIGN_ACCEPTED` in `M0.3`)
- **Date:** 2026-04-11
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
In our Flash Sale scenario (`100,000` users competing for `1,000` units):
1. Redis Lua (`flash_sale_claim.lua`) acts as the fast admission gate while PostgreSQL (`promotion_db`) is the authoritative system of record.
2. Under `Q4 Option A` (`ACCEPTED`), expired unpaid reservations return stock to the active Redis campaign pool, requiring strict single-transaction DB atomicity, deterministic lock serialization across all 8 mutation paths (`MP-01` through `MP-08`), atomic Lua release deduplication (`flash_sale_release.lua`), and epoch-fenced Redis failover recovery.

## 2. Options Considered
- **Option A**: Direct PostgreSQL row locking for all 100K requests without a Redis gate.
- **Option B**: Application-constructed ad-hoc SQL CTEs or triggers that acquire locks on `flash_sale_campaigns` mid-transaction (`M0.2.3`/`M0.2.4` drafts).
- **Option C (Chosen in `M0.3`)**: **3-Tier Concurrency Architecture + Least-Privilege `SECURITY DEFINER` Stored Procedures (`fn_mp01`–`fn_mp08`) Owned by Non-Superuser `promotion_proc_owner` + Canonical Lock Ordering + `FOR UPDATE` Rebuilder Barrier (`CH-01`, `HD-01`, `HD-02`, `HD-03`)**.

## 3. Decision (`DESIGN_ACCEPTED`)
1. **Accepted Baseline (`ACCEPTED`)**:
   - **Tier 1 (Flash Sale Gate)**: Redis Lua admission gate + asynchronous Kafka order materialization.
   - **Tier 2 (`Q4 Option A` Expiry)**: Expired reservations return stock to the active Redis pool while the campaign is `ACTIVE`, or reconcile to warehouse stock after `ENDED`.
   - **Tier 3 (Standard Stock)**: Conditional atomic SQL (`UPDATE stock_items ... WHERE available_qty >= :qty`) ordered by `sku_id ASC`.
   - **Tier 4 (Low-Contention Entities)**: `@Version` Optimistic Concurrency Control.
2. **Frozen `M0.3` Database Concurrency & Security Model (`CH-01`, `HD-01`, `HD-02`, `HD-03`)**:
   - **Least-Privilege Role Hierarchy (`HD-03`)**:
     - `promotion_proc_owner`: Dedicated non-login, non-superuser role (`NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE`) that owns the protected tables (`flash_sale_campaigns`, `flash_sale_claims`, `flash_sale_items`, `outbox_messages`, `idempotency_records`) and the 8 `SECURITY DEFINER` stored procedures (`fn_mp01` through `fn_mp08`).
     - `promotion_app_role`: Runtime application database login role. Direct `INSERT, UPDATE, DELETE` (and consequently `SELECT ... FOR UPDATE/SHARE`) privileges on the protected tables are **revoked** from `promotion_app_role` and `PUBLIC`. Explicit `GRANT EXECUTE ON FUNCTION ... TO promotion_app_role` is granted only on `fn_mp01`–`fn_mp08`.
     - Every `SECURITY DEFINER` function declares an immutable `SET search_path = pg_catalog, public` to prevent object-shadowing attacks.
     - Schema migration (`promotion_migrator`) and emergency break-glass DBA sessions are separated from `promotion_app_role` and must respect the canonical lock hierarchy during online operations.
   - **Canonical Lock Ordering (`HD-01`, `HD-02`)**:
     - Every stored procedure executes imperative PL/pgSQL statements in strict hierarchy order:
       `1. flash_sale_campaigns (FOR SHARE or FOR UPDATE) -> 2. flash_sale_claims (ORDER BY claim_id ASC FOR UPDATE) -> 3. flash_sale_items (ORDER BY item_id ASC FOR UPDATE) -> 4. outbox_messages -> 5. idempotency_records`.
   - **Explicit Role of the Custom GUC Witness (`promotion.locked_campaign_<uuid>`)**:
     - Statement 1 of each stored procedure calls `set_config('promotion.locked_campaign_' || v_campaign_id::text, 'true', true)`, and `BEFORE INSERT OR UPDATE OR DELETE` witness triggers (`trg_verify_claims_campaign_prelocked`, `trg_verify_items_campaign_prelocked`) check `current_setting(...) = 'true'`.
     - **Important Architectural Clarification**: Because PostgreSQL custom GUC variables are session-writable by any caller able to invoke `set_config()`, the GUC witness is documented strictly as an **accidental-bug guard for privileged maintenance scripts/functions** (catching a privileged developer script that forgot to lock the campaign row first) and **NOT** as an independent security boundary. The true security boundary is the `REVOKE INSERT, UPDATE, DELETE` privilege barrier + `SECURITY DEFINER` stored procedure encapsulation.
   - **Concurrent Writer vs. Reconciler Serialization & Redis Epoch Fencing**:
     - Writer (`fn_mp01`) and Reconciler (`fn_mp05`) serialize on `PRIMARY KEY (claim_id)` (`CLAIMED` vs `RELEASED_RECONCILED` tombstone).
     - Rebuilder (`fn_mp08`) acquires `FOR UPDATE` on `flash_sale_campaigns`, incrementing `current_epoch` and waiting for all in-flight `FOR SHARE` transactions to drain before snapshotting PostgreSQL state to rebuild Redis. `idle_in_transaction_session_timeout = 3s`, `statement_timeout = 3s`, and `pg_terminate_backend` act strictly as operational liveness bounds, never as correctness mechanisms.

## 4. Consequences & Trade-offs
- **Positive**: Provably zero oversell and zero AB-BA deadlocks across all 8 mutation paths; least-privilege DB security (`NOSUPERUSER` owner, safe `search_path`, revoked table write grants); clear honesty regarding PostgreSQL GUC semantics.
- **Negative / Cost**: All Promotion write mutations must be maintained in versioned Flyway/DbUp SQL migrations defining `fn_mp01`–`fn_mp08`.

## 5. Rejected Alternatives
- **Option B (Relying on CTE evaluation order or treating custom GUC variables as a security boundary)**: Rejected because PostgreSQL CTEs do not guarantee cross-statement lock ordering unless imperative PL/pgSQL statements are used, and custom GUCs can be set by any session via `set_config()`.
