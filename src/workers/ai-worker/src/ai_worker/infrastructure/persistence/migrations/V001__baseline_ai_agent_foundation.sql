-- =============================================================================
-- Migration: V001__baseline_ai_agent_foundation.sql
-- Bounded Context: AI Assistant & RAG Worker (ai_agent_db)
-- Execution Identity: ai_agent_migrator (NOSUPERUSER)
-- Governing Decisions: ADR-0002, ADR-0003, ADR-0008, CH-04, CH-06, FR-AI-003
-- Description: Establishes pgvector generation-isolated index metadata table
--              (enforcing HNSW dimension ceilings <= 2000d for VECTOR_FP32 and
--              <= 4000d for HALFVEC_FP16) and Consumer Inbox / Deferral tables.
-- =============================================================================

CREATE TABLE public.embedding_index_generations (
    generation_id           UUID         NOT NULL,
    provider_name           VARCHAR(64)  NOT NULL,
    model_id                VARCHAR(128) NOT NULL,
    model_version           VARCHAR(64)  NOT NULL,
    dimensions              INTEGER      NOT NULL,
    index_storage_type      VARCHAR(32)  NOT NULL,
    distance_metric         VARCHAR(32)  NOT NULL DEFAULT 'COSINE',
    is_active_for_search    BOOLEAN      NOT NULL DEFAULT FALSE,
    created_at              TIMESTAMPTZ  NOT NULL DEFAULT pg_catalog.now(),
    activated_at            TIMESTAMPTZ  NULL,
    retired_at              TIMESTAMPTZ  NULL,
    CONSTRAINT pk_embedding_index_generations PRIMARY KEY (generation_id),
    CONSTRAINT uq_embedding_generations_model UNIQUE (provider_name, model_id, model_version, dimensions, index_storage_type),
    CONSTRAINT chk_embedding_storage_type CHECK (index_storage_type IN ('VECTOR_FP32', 'HALFVEC_FP16')),
    CONSTRAINT chk_embedding_distance_metric CHECK (distance_metric IN ('COSINE', 'L2', 'INNER_PRODUCT')),
    CONSTRAINT chk_embedding_hnsw_dimension_ceiling CHECK (
        (index_storage_type = 'VECTOR_FP32'  AND dimensions BETWEEN 1 AND 2000)
        OR
        (index_storage_type = 'HALFVEC_FP16' AND dimensions BETWEEN 1 AND 4000)
    )
);

-- At most one generation may be active for live RAG similarity queries at any time (FR-AI-003)
CREATE UNIQUE INDEX uq_embedding_single_active_generation
    ON public.embedding_index_generations (is_active_for_search)
    WHERE is_active_for_search = TRUE;

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
