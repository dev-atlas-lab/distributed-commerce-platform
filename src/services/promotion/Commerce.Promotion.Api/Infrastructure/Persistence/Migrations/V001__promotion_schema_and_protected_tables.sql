-- =============================================================================
-- Migration: V001__promotion_schema_and_protected_tables.sql
-- Bounded Context: Promotion & Flash Sale Service (promotion_db)
-- Execution Identity: promotion_migrator assuming promotion_proc_owner
-- Governing Decisions: ADR-0003, ADR-0005, CH-01, CH-03, CH-04, FR-PRO-002, NFR-SEC-003
-- Description:
--   1. Establishes dedicated trusted schema `promotion_private` owned by
--      `promotion_proc_owner` (NOLOGIN NOSUPERUSER).
--   2. Enforces strict schema ACLs and default privilege revocations across
--      both `public` and `promotion_private`.
--   3. Creates the protected Flash Sale tables (`flash_sale_campaigns`,
--      `flash_sale_items`, `flash_sale_claims`, `outbox_messages`,
--      `outbox_relay_shards`, `idempotency_records`, `inbox_messages`,
--      `inbox_deferred_events`) owned by `promotion_proc_owner`.
--   4. Revokes direct INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
--      from `PUBLIC`, `promotion_app_role`, and `promotion_migrator` so all
--      Flash Sale writes must pass through `fn_mp01`..`fn_mp08`.
-- =============================================================================

-- Execute DDL as the non-login, non-superuser owner role
SET LOCAL ROLE promotion_proc_owner;

CREATE SCHEMA IF NOT EXISTS promotion_private AUTHORIZATION promotion_proc_owner;

-- 1. Schema Privilege Hardening
REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM promotion_app_role;
GRANT USAGE ON SCHEMA public TO promotion_app_role;
GRANT USAGE, CREATE ON SCHEMA public TO
    promotion_proc_owner,
    promotion_migrator,
    promotion_dba_admin;

REVOKE ALL ON SCHEMA promotion_private FROM PUBLIC;
REVOKE ALL ON SCHEMA promotion_private FROM promotion_app_role;
REVOKE ALL ON SCHEMA promotion_private FROM promotion_migrator;
GRANT USAGE, CREATE ON SCHEMA promotion_private TO promotion_proc_owner;
GRANT USAGE ON SCHEMA promotion_private TO promotion_dba_admin;

-- 2. Default Privilege Hardening (future objects never leak PUBLIC privileges)
-- CRITICAL POSTGRESQL ENGINE FACT (src/backend/catalog/aclchk.c):
-- PostgreSQL's built-in default 'EXECUTE ON FUNCTIONS TO PUBLIC' lives in the GLOBAL
-- default ACL (defaclnamespace = 0). Per-schema default ACLs ('IN SCHEMA ...') are
-- additive over global defaults and cannot revoke a global default privilege.
-- Therefore, REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC must be executed without 'IN SCHEMA'!
ALTER DEFAULT PRIVILEGES FOR ROLE promotion_proc_owner
    REVOKE ALL ON TABLES FROM PUBLIC, promotion_app_role, promotion_migrator;
ALTER DEFAULT PRIVILEGES FOR ROLE promotion_proc_owner
    REVOKE ALL ON SEQUENCES FROM PUBLIC, promotion_app_role, promotion_migrator;
ALTER DEFAULT PRIVILEGES FOR ROLE promotion_proc_owner
    REVOKE EXECUTE ON FUNCTIONS FROM PUBLIC, promotion_app_role, promotion_migrator;

-- 3. Protected Table 1: flash_sale_campaigns (Lock Hierarchy Level 1)
CREATE TABLE public.flash_sale_campaigns (
    campaign_id             UUID         NOT NULL,
    name                    VARCHAR(128) NOT NULL,
    status                  VARCHAR(32)  NOT NULL,
    current_epoch           BIGINT       NOT NULL DEFAULT 1,
    starts_at               TIMESTAMPTZ  NOT NULL,
    ends_at                 TIMESTAMPTZ  NOT NULL,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_flash_sale_campaigns PRIMARY KEY (campaign_id),
    CONSTRAINT chk_flash_sale_campaigns_status CHECK (status IN (
        'DRAFT',
        'APPROVED',
        'WARMED',
        'ACTIVE',
        'REBUILDING_GATE',
        'ENDED',
        'RECONCILED'
    )),
    CONSTRAINT chk_flash_sale_campaigns_epoch CHECK (current_epoch >= 1),
    CONSTRAINT chk_flash_sale_campaigns_window CHECK (ends_at > starts_at)
);

-- 4. Protected Table 2: flash_sale_claims (Lock Hierarchy Level 2 — ordered by claim_id ASC)
CREATE TABLE public.flash_sale_claims (
    claim_id                UUID         NOT NULL,
    campaign_id             UUID         NOT NULL,
    campaign_epoch          BIGINT       NOT NULL,
    release_epoch           BIGINT       NULL,
    sku_id                  UUID         NOT NULL,
    customer_id             UUID         NOT NULL,
    idempotency_key         VARCHAR(128) NOT NULL,
    quantity                INTEGER      NOT NULL,
    status                  VARCHAR(32)  NOT NULL,
    intent_lease_expires_at TIMESTAMPTZ  NOT NULL,
    payment_expires_at      TIMESTAMPTZ  NOT NULL,
    stock_returned_to_redis BOOLEAN      NOT NULL DEFAULT FALSE,
    version                 BIGINT       NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_flash_sale_claims PRIMARY KEY (claim_id),
    CONSTRAINT fk_flash_sale_claims_campaign FOREIGN KEY (campaign_id)
        REFERENCES public.flash_sale_campaigns (campaign_id),
    CONSTRAINT uq_flash_claim_idem UNIQUE (campaign_id, customer_id, idempotency_key),
    CONSTRAINT chk_flash_sale_claims_quantity CHECK (quantity > 0),
    CONSTRAINT chk_flash_sale_claims_epoch CHECK (campaign_epoch >= 1),
    CONSTRAINT chk_flash_sale_claims_status CHECK (status IN (
        'CLAIMED_RESERVED',
        'ORDER_MATERIALIZED',
        'PAYMENT_CONFIRMED',
        'CANCELLED',
        'EXPIRED',
        'ABANDONED_FENCED'
    )),
    CONSTRAINT chk_flash_sale_claims_version CHECK (version >= 0)
);

CREATE UNIQUE INDEX uq_flash_active_customer_sku
    ON public.flash_sale_claims (campaign_id, sku_id, customer_id)
    WHERE status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED');

CREATE INDEX idx_flash_sale_claims_campaign_status
    ON public.flash_sale_claims (campaign_id, status, claim_id ASC);

-- 5. Protected Table 3: flash_sale_items (Lock Hierarchy Level 3 — ordered by sku_id ASC)
CREATE TABLE public.flash_sale_items (
    campaign_id             UUID         NOT NULL,
    sku_id                  UUID         NOT NULL,
    allocated_quota         INTEGER      NOT NULL,
    claimed_count           INTEGER      NOT NULL DEFAULT 0,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_flash_sale_items PRIMARY KEY (campaign_id, sku_id),
    CONSTRAINT fk_flash_sale_items_campaign FOREIGN KEY (campaign_id)
        REFERENCES public.flash_sale_campaigns (campaign_id),
    CONSTRAINT chk_flash_sale_items_quota CHECK (allocated_quota >= 0),
    CONSTRAINT chk_flash_sale_items_claimed_bounds CHECK (
        claimed_count >= 0 AND claimed_count <= allocated_quota
    )
);

-- 6. Protected Table 4: outbox_messages (Lock Hierarchy Level 4)
CREATE TABLE public.outbox_messages (
    outbox_sequence     BIGSERIAL    NOT NULL,
    event_id            UUID         NOT NULL,
    shard_id            INTEGER      NOT NULL DEFAULT 0,
    aggregate_type      VARCHAR(64)  NOT NULL,
    aggregate_id        VARCHAR(128) NOT NULL,
    aggregate_version   BIGINT       NOT NULL,
    event_type          VARCHAR(128) NOT NULL,
    topic               VARCHAR(128) NOT NULL,
    partition_key       VARCHAR(128) NOT NULL,
    payload             JSONB        NOT NULL,
    headers             JSONB        NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    published_at        TIMESTAMPTZ  NULL,
    retry_count         INTEGER      NOT NULL DEFAULT 0,
    last_error          TEXT         NULL,
    CONSTRAINT pk_outbox_messages PRIMARY KEY (event_id),
    CONSTRAINT uq_outbox_messages_sequence UNIQUE (outbox_sequence),
    CONSTRAINT chk_outbox_messages_shard_range CHECK (shard_id BETWEEN 0 AND 15),
    CONSTRAINT chk_outbox_messages_version_positive CHECK (aggregate_version >= 1),
    CONSTRAINT chk_outbox_messages_retry_nonnegative CHECK (retry_count >= 0)
);

CREATE INDEX idx_outbox_messages_unpublished_head
    ON public.outbox_messages (shard_id, aggregate_id, aggregate_version ASC, outbox_sequence ASC)
    WHERE published_at IS NULL;

-- 7. Protected Table 5: idempotency_records (Lock Hierarchy Level 5)
CREATE TABLE public.idempotency_records (
    scope_owner_id          UUID         NOT NULL,
    endpoint_id             VARCHAR(128) NOT NULL,
    idempotency_key         VARCHAR(128) NOT NULL,
    payload_hash            VARCHAR(64)  NOT NULL,
    status                  VARCHAR(32)  NOT NULL,
    lease_generation        BIGINT       NOT NULL DEFAULT 1,
    downstream_operation_id UUID         NULL,
    http_status_code        INTEGER      NULL,
    response_payload        JSONB        NULL,
    lease_expires_at        TIMESTAMPTZ  NOT NULL,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    updated_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_idempotency_records PRIMARY KEY (scope_owner_id, endpoint_id, idempotency_key),
    CONSTRAINT chk_idempotency_records_status CHECK (status IN (
        'STARTED',
        'RECONCILING',
        'COMPLETED_SUCCESS',
        'COMPLETED_RETRYABLE_ERROR',
        'COMPLETED_TERMINAL_ERROR',
        'MANUAL_INTERVENTION_REQUIRED'
    )),
    CONSTRAINT chk_idempotency_records_lease_gen CHECK (lease_generation >= 1)
);

-- 8. Relay Coordination & Consumer Inbox Tables
CREATE TABLE public.outbox_relay_shards (
    shard_id            INTEGER      NOT NULL,
    owner_id            VARCHAR(128) NULL,
    lease_epoch         BIGINT       NOT NULL DEFAULT 0,
    lease_expires_at    TIMESTAMPTZ  NOT NULL DEFAULT '-infinity'::timestamptz,
    updated_at          TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_outbox_relay_shards PRIMARY KEY (shard_id),
    CONSTRAINT chk_outbox_relay_shards_range CHECK (shard_id BETWEEN 0 AND 15),
    CONSTRAINT chk_outbox_relay_shards_epoch CHECK (lease_epoch >= 0)
);

CREATE TABLE public.inbox_messages (
    event_id            UUID         NOT NULL,
    consumer_group      VARCHAR(128) NOT NULL,
    event_type          VARCHAR(128) NOT NULL,
    aggregate_type      VARCHAR(64)  NOT NULL,
    aggregate_id        VARCHAR(128) NOT NULL,
    aggregate_version   BIGINT       NOT NULL,
    outcome             VARCHAR(32)  NOT NULL DEFAULT 'APPLIED',
    processed_at        TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    CONSTRAINT pk_inbox_messages PRIMARY KEY (event_id, consumer_group),
    CONSTRAINT chk_inbox_messages_outcome CHECK (outcome IN ('APPLIED', 'IGNORED_STALE')),
    CONSTRAINT chk_inbox_messages_version_positive CHECK (aggregate_version >= 1)
);

CREATE TABLE public.inbox_deferred_events (
    consumer_group      VARCHAR(128) NOT NULL,
    aggregate_type      VARCHAR(64)  NOT NULL,
    aggregate_id        VARCHAR(128) NOT NULL,
    aggregate_version   BIGINT       NOT NULL,
    event_id            UUID         NOT NULL,
    topic               VARCHAR(128) NOT NULL,
    payload             JSONB        NOT NULL,
    headers             JSONB        NOT NULL DEFAULT '{}'::jsonb,
    first_seen_at       TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    last_checked_at     TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    retry_count         INTEGER      NOT NULL DEFAULT 0,
    status              VARCHAR(32)  NOT NULL DEFAULT 'DEFERRED',
    CONSTRAINT pk_inbox_deferred_events PRIMARY KEY (consumer_group, aggregate_type, aggregate_id, aggregate_version),
    CONSTRAINT chk_inbox_deferred_events_status CHECK (status IN ('DEFERRED', 'APPLIED', 'EXPIRED_QUARANTINED')),
    CONSTRAINT chk_inbox_deferred_events_version CHECK (aggregate_version >= 1),
    CONSTRAINT chk_inbox_deferred_events_retries CHECK (retry_count >= 0)
);

CREATE INDEX idx_inbox_deferred_events_sweeper
    ON public.inbox_deferred_events (first_seen_at ASC)
    WHERE status = 'DEFERRED';

-- 9. Explicit Ownership & Least-Privilege Table ACLs (ADR-0005 / NFR-SEC-003)
ALTER TABLE public.flash_sale_campaigns  OWNER TO promotion_proc_owner;
ALTER TABLE public.flash_sale_claims     OWNER TO promotion_proc_owner;
ALTER TABLE public.flash_sale_items      OWNER TO promotion_proc_owner;
ALTER TABLE public.outbox_messages       OWNER TO promotion_proc_owner;
ALTER TABLE public.idempotency_records   OWNER TO promotion_proc_owner;
ALTER TABLE public.outbox_relay_shards   OWNER TO promotion_proc_owner;
ALTER TABLE public.inbox_messages        OWNER TO promotion_proc_owner;
ALTER TABLE public.inbox_deferred_events OWNER TO promotion_proc_owner;

REVOKE ALL ON TABLE
    public.flash_sale_campaigns,
    public.flash_sale_claims,
    public.flash_sale_items,
    public.outbox_messages,
    public.idempotency_records,
    public.outbox_relay_shards,
    public.inbox_messages,
    public.inbox_deferred_events
FROM PUBLIC, promotion_app_role, promotion_migrator;

REVOKE ALL ON SEQUENCE public.outbox_messages_outbox_sequence_seq
FROM PUBLIC, promotion_app_role, promotion_migrator;

-- Grant read-only SELECT to runtime application role and break-glass DBA role.
-- Because UPDATE privilege is revoked, promotion_app_role is also blocked by PostgreSQL
-- from executing direct SELECT ... FOR UPDATE / FOR SHARE on protected tables!
GRANT SELECT ON TABLE
    public.flash_sale_campaigns,
    public.flash_sale_claims,
    public.flash_sale_items,
    public.outbox_messages,
    public.idempotency_records,
    public.outbox_relay_shards,
    public.inbox_messages,
    public.inbox_deferred_events
TO promotion_app_role, promotion_dba_admin;

-- Allow break-glass DBA role to run audited emergency maintenance while still guarded
-- by the pre-lock witness triggers on flash_sale_claims and flash_sale_items
GRANT INSERT, UPDATE, DELETE ON TABLE
    public.flash_sale_campaigns,
    public.flash_sale_claims,
    public.flash_sale_items
TO promotion_dba_admin;

RESET ROLE;
