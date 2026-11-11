-- =============================================================================
-- Migration: V001__baseline_messaging_and_idempotency.sql
-- Bounded Context: Notification Worker Service (notification_db)
-- Execution Identity: notification_migrator (NOSUPERUSER)
-- Governing Decisions: ADR-0002, ADR-0003, ADR-0010, CH-04
-- Description: Establishes transactional Outbox, Relay Shard Leases, Consumer
--              Inbox, Bounded Version-Gap Deferral Buffer, and Fenced Two-Class
--              HTTP Idempotency baseline tables.
-- =============================================================================

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
