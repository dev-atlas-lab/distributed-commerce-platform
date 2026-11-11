-- =============================================================================
-- Migration: V002__promotion_security_definer_procedures.sql
-- Bounded Context: Promotion & Flash Sale Service (promotion_db)
-- Execution Identity: promotion_migrator assuming promotion_proc_owner
-- Governing Decisions: ADR-0005, CH-01, HD-01, HD-03, FR-PRO-002..005, NFR-SEC-003
-- Description:
--   1. Implements internal witness & DBA functions inside trusted schema
--      `promotion_private` owned by `promotion_proc_owner` (NOLOGIN NOSUPERUSER).
--   2. Attaches non-locking pre-lock witness triggers (`trg_verify_claims_campaign_prelocked`
--      and `trg_verify_items_campaign_prelocked`) as accidental-bug guards.
--   3. Implements all 8 imperative PL/pgSQL SECURITY DEFINER procedures
--      (`fn_mp01` through `fn_mp08`) with safe `SET search_path = pg_catalog, promotion_private, public, pg_temp`
--      and schema-qualified object/function references.
--   4. Enforces strict ownership (`promotion_proc_owner`), revokes PUBLIC and
--      migrator EXECUTE privileges, and grants EXECUTE strictly to authorized roles.
-- =============================================================================

SET LOCAL ROLE promotion_proc_owner;

-- =============================================================================
-- PART 1: Internal Trusted Functions & Witness Triggers in `promotion_private`
-- =============================================================================

CREATE OR REPLACE FUNCTION promotion_private.fn_set_campaign_lock_witness(
    p_campaign_id UUID,
    p_epoch       BIGINT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
BEGIN
    PERFORM pg_catalog.set_config(
        'promotion.locked_campaign_' || pg_catalog.replace(p_campaign_id::text, '-', ''),
        p_epoch::text,
        true
    );
END;
$$;

ALTER FUNCTION promotion_private.fn_set_campaign_lock_witness(UUID, BIGINT)
    OWNER TO promotion_proc_owner;
REVOKE ALL ON FUNCTION promotion_private.fn_set_campaign_lock_witness(UUID, BIGINT)
    FROM PUBLIC, promotion_app_role, promotion_migrator;

-- Non-locking pre-lock witness trigger function (ADR-0005 Section 3.2):
-- Catches accidental lock-order bugs in privileged functions or DBA maintenance scripts
-- without acquiring any reverse Table 2/3 -> Table 1 lock edge.
CREATE OR REPLACE FUNCTION promotion_private.fn_verify_campaign_prelocked()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_campaign_id  UUID := COALESCE(NEW.campaign_id, OLD.campaign_id);
    v_locked_epoch TEXT;
BEGIN
    v_locked_epoch := pg_catalog.current_setting(
        'promotion.locked_campaign_' || pg_catalog.replace(v_campaign_id::text, '-', ''),
        true
    );

    IF v_locked_epoch IS NULL OR v_locked_epoch OPERATOR(pg_catalog.=) '' THEN
        RAISE EXCEPTION 'LOCK_ORDER_VIOLATION: flash_sale_campaigns(%) must be locked before mutating %',
            v_campaign_id, TG_TABLE_NAME
            USING ERRCODE = 'P0004';
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$$;

ALTER FUNCTION promotion_private.fn_verify_campaign_prelocked()
    OWNER TO promotion_proc_owner;
REVOKE ALL ON FUNCTION promotion_private.fn_verify_campaign_prelocked()
    FROM PUBLIC, promotion_app_role, promotion_migrator;

DROP TRIGGER IF EXISTS trg_verify_claims_campaign_prelocked ON public.flash_sale_claims;
CREATE TRIGGER trg_verify_claims_campaign_prelocked
BEFORE INSERT OR UPDATE OR DELETE ON public.flash_sale_claims
FOR EACH ROW EXECUTE FUNCTION promotion_private.fn_verify_campaign_prelocked();

DROP TRIGGER IF EXISTS trg_verify_items_campaign_prelocked ON public.flash_sale_items;
CREATE TRIGGER trg_verify_items_campaign_prelocked
BEFORE INSERT OR UPDATE OR DELETE ON public.flash_sale_items
FOR EACH ROW EXECUTE FUNCTION promotion_private.fn_verify_campaign_prelocked();

-- DBA-only diagnostic function in `promotion_private` (verifies promotion_app_role
-- cannot execute unauthorized functions in promotion_private)
CREATE OR REPLACE FUNCTION promotion_private.fn_admin_inspect_campaign_locks(
    p_campaign_id UUID
) RETURNS TABLE (
    campaign_id   UUID,
    status        VARCHAR(32),
    current_epoch BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT c.campaign_id, c.status, c.current_epoch
      FROM public.flash_sale_campaigns c
     WHERE c.campaign_id OPERATOR(pg_catalog.=) p_campaign_id;
END;
$$;

ALTER FUNCTION promotion_private.fn_admin_inspect_campaign_locks(UUID)
    OWNER TO promotion_proc_owner;
REVOKE ALL ON FUNCTION promotion_private.fn_admin_inspect_campaign_locks(UUID)
    FROM PUBLIC, promotion_app_role, promotion_migrator;
GRANT EXECUTE ON FUNCTION promotion_private.fn_admin_inspect_campaign_locks(UUID)
    TO promotion_dba_admin;

-- =============================================================================
-- PART 2: CH-01 Imperative SECURITY DEFINER Stored Procedures (fn_mp01..fn_mp08)
-- Canonical Lock Hierarchy:
--   1. public.flash_sale_campaigns (FOR SHARE or FOR UPDATE)
--   2. public.flash_sale_claims    (ORDER BY claim_id ASC)
--   3. public.flash_sale_items     (ORDER BY sku_id ASC)
--   4. public.outbox_messages
--   5. public.idempotency_records
-- =============================================================================

-- -----------------------------------------------------------------------------
-- MP-01: Writer Claim Persistence (REDIS_INTENT_LEASED -> CLAIMED_RESERVED)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp01_writer_claim(
    p_claim_id           UUID,
    p_campaign_id        UUID,
    p_redis_claim_epoch  BIGINT,
    p_sku_id             UUID,
    p_customer_id        UUID,
    p_idempotency_key    VARCHAR(128),
    p_qty                INTEGER,
    p_intent_expires_at  TIMESTAMPTZ,
    p_payment_expires_at TIMESTAMPTZ,
    p_event_id           UUID,
    p_payload_jsonb      JSONB,
    p_headers_jsonb      JSONB,
    p_response_jsonb     JSONB,
    p_expected_lease_gen BIGINT
) RETURNS TABLE (
    outcome_code    VARCHAR(64),
    http_status     INTEGER,
    existing_status VARCHAR(32)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
    v_inserted_status VARCHAR(32);
    v_existing_status VARCHAR(32);
    v_rows_updated    INTEGER;
BEGIN
    -- STEP 1 (Table 1: public.flash_sale_campaigns): Acquire FOR SHARE lock FIRST
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR SHARE;

    IF NOT FOUND
       OR v_campaign_status OPERATOR(pg_catalog.<>) 'ACTIVE'
       OR v_current_epoch OPERATOR(pg_catalog.<>) p_redis_claim_epoch THEN
        RAISE EXCEPTION 'CAMPAIGN_EPOCH_OR_STATE_FENCED' USING ERRCODE = 'P0001';
    END IF;

    -- Set transaction-local pre-lock witness for Table 1
    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 2: public.flash_sale_claims): Attempt insert or detect prior row
    INSERT INTO public.flash_sale_claims (
        claim_id, campaign_id, campaign_epoch, sku_id, customer_id, idempotency_key,
        quantity, status, intent_lease_expires_at, payment_expires_at,
        created_at, updated_at
    ) VALUES (
        p_claim_id, p_campaign_id, v_current_epoch, p_sku_id, p_customer_id, p_idempotency_key,
        p_qty, 'CLAIMED_RESERVED', p_intent_expires_at, p_payment_expires_at,
        pg_catalog.now(), pg_catalog.now()
    )
    ON CONFLICT (claim_id) DO NOTHING
    RETURNING status INTO v_inserted_status;

    IF v_inserted_status IS NULL THEN
        SELECT fsc.status
          INTO v_existing_status
          FROM public.flash_sale_claims fsc
         WHERE fsc.claim_id OPERATOR(pg_catalog.=) p_claim_id;

        IF v_existing_status OPERATOR(pg_catalog.=) 'ABANDONED_FENCED' THEN
            RAISE EXCEPTION 'CLAIM_LEASE_EXPIRED_FENCED' USING ERRCODE = 'P0002';
        END IF;

        -- Prior retry already committed CLAIMED_RESERVED / ORDER_MATERIALIZED / PAYMENT_CONFIRMED
        RETURN QUERY SELECT 'IDEMPOTENT_ALREADY_CLAIMED'::VARCHAR(64), 202, v_existing_status;
        RETURN;
    END IF;

    -- STEP 3 (Table 3: public.flash_sale_items): Increment claimed_count within allocated_quota
    UPDATE public.flash_sale_items fsi
       SET claimed_count = fsi.claimed_count + p_qty,
           updated_at = pg_catalog.now()
     WHERE fsi.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND fsi.sku_id OPERATOR(pg_catalog.=) p_sku_id
       AND (fsi.claimed_count + p_qty) <= fsi.allocated_quota;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    IF v_rows_updated OPERATOR(pg_catalog.=) 0 THEN
        RAISE EXCEPTION 'QUOTA_EXHAUSTED' USING ERRCODE = 'P0003';
    END IF;

    -- STEP 4 (Table 4: public.outbox_messages): Insert Outbox event
    INSERT INTO public.outbox_messages (
        event_id, shard_id, aggregate_type, aggregate_id, aggregate_version,
        event_type, topic, partition_key, payload, headers, created_at
    ) VALUES (
        p_event_id,
        pg_catalog.mod(pg_catalog.abs(pg_catalog.hashtext(p_customer_id::text)), 16),
        'FlashSaleClaim',
        p_claim_id::text,
        1,
        'commerce.flashsale.slot_claimed.v1',
        'commerce.flashsale.events.v1',
        p_customer_id::text,
        p_payload_jsonb,
        p_headers_jsonb,
        pg_catalog.now()
    );

    -- STEP 5 (Table 5: public.idempotency_records): Complete fenced idempotency record
    IF p_expected_lease_gen OPERATOR(pg_catalog.=) 1 THEN
        INSERT INTO public.idempotency_records (
            scope_owner_id, endpoint_id, idempotency_key, payload_hash,
            status, lease_generation, downstream_operation_id,
            http_status_code, response_payload, lease_expires_at,
            created_at, updated_at
        ) VALUES (
            p_customer_id,
            'POST:/api/v1/flash-sales/claim',
            p_idempotency_key,
            pg_catalog.md5(p_payload_jsonb::text),
            'COMPLETED_SUCCESS',
            1,
            p_claim_id,
            202,
            p_response_jsonb,
            p_intent_expires_at,
            pg_catalog.now(),
            pg_catalog.now()
        )
        ON CONFLICT (scope_owner_id, endpoint_id, idempotency_key) DO UPDATE
           SET status = 'COMPLETED_SUCCESS',
               http_status_code = 202,
               response_payload = EXCLUDED.response_payload,
               updated_at = pg_catalog.now()
         WHERE public.idempotency_records.lease_generation OPERATOR(pg_catalog.=) p_expected_lease_gen;
    ELSE
        UPDATE public.idempotency_records ir
           SET status = 'COMPLETED_SUCCESS',
               http_status_code = 202,
               response_payload = p_response_jsonb,
               updated_at = pg_catalog.now()
         WHERE ir.scope_owner_id OPERATOR(pg_catalog.=) p_customer_id
           AND ir.endpoint_id OPERATOR(pg_catalog.=) 'POST:/api/v1/flash-sales/claim'
           AND ir.idempotency_key OPERATOR(pg_catalog.=) p_idempotency_key
           AND ir.lease_generation OPERATOR(pg_catalog.=) p_expected_lease_gen;
    END IF;

    GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
    IF v_rows_updated OPERATOR(pg_catalog.=) 0 THEN
        RAISE EXCEPTION 'IDEMPOTENCY_LEASE_FENCED' USING ERRCODE = 'P0005';
    END IF;

    RETURN QUERY SELECT 'CLAIMED_NEW'::VARCHAR(64), 202, 'CLAIMED_RESERVED'::VARCHAR(32);
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-02: Reconciler Intent Lease Fence (REDIS_INTENT_LEASED -> ABANDONED_FENCED)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp02_reconcile_fenced(
    p_claim_id           UUID,
    p_campaign_id        UUID,
    p_redis_claim_epoch  BIGINT,
    p_sku_id             UUID,
    p_customer_id        UUID,
    p_idempotency_key    VARCHAR(128),
    p_qty                INTEGER,
    p_intent_expires_at  TIMESTAMPTZ
) RETURNS TABLE (
    fenced_created BOOLEAN,
    current_status VARCHAR(32),
    release_epoch  BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
    v_inserted_status VARCHAR(32);
    v_existing_status VARCHAR(32);
BEGIN
    -- STEP 1 (Table 1): Lock campaign FOR SHARE and verify epoch
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR SHARE;

    IF NOT FOUND
       OR v_campaign_status OPERATOR(pg_catalog.<>) 'ACTIVE'
       OR v_current_epoch OPERATOR(pg_catalog.<>) p_redis_claim_epoch THEN
        RETURN QUERY SELECT FALSE, 'EPOCH_OR_STATE_SKIPPED'::VARCHAR(32), v_current_epoch;
        RETURN;
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 2): Insert ABANDONED_FENCED tombstone
    INSERT INTO public.flash_sale_claims (
        claim_id, campaign_id, campaign_epoch, release_epoch, sku_id, customer_id,
        idempotency_key, quantity, status, intent_lease_expires_at, payment_expires_at,
        stock_returned_to_redis, created_at, updated_at
    ) VALUES (
        p_claim_id, p_campaign_id, v_current_epoch, v_current_epoch, p_sku_id, p_customer_id,
        p_idempotency_key, p_qty, 'ABANDONED_FENCED', p_intent_expires_at, p_intent_expires_at,
        FALSE, pg_catalog.now(), pg_catalog.now()
    )
    ON CONFLICT (claim_id) DO NOTHING
    RETURNING status INTO v_inserted_status;

    IF v_inserted_status IS NOT NULL THEN
        RETURN QUERY SELECT TRUE, v_inserted_status, v_current_epoch;
    ELSE
        SELECT fsc.status, fsc.release_epoch
          INTO v_existing_status, v_current_epoch
          FROM public.flash_sale_claims fsc
         WHERE fsc.claim_id OPERATOR(pg_catalog.=) p_claim_id;
        RETURN QUERY SELECT FALSE, v_existing_status, v_current_epoch;
    END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-03: Committed Claim Expiration or Cancellation (-> EXPIRED | CANCELLED)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp03_expire_or_cancel(
    p_claim_id        UUID,
    p_campaign_id     UUID,
    p_terminal_status VARCHAR(32),
    p_event_id        UUID,
    p_payload_jsonb   JSONB,
    p_headers_jsonb   JSONB
) RETURNS TABLE (
    transitioned  BOOLEAN,
    sku_id        UUID,
    quantity      INTEGER,
    release_epoch BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
    v_sku_id          UUID;
    v_customer_id     UUID;
    v_qty             INTEGER;
    v_new_version     BIGINT;
BEGIN
    IF p_terminal_status NOT IN ('EXPIRED', 'CANCELLED') THEN
        RAISE EXCEPTION 'INVALID_TERMINAL_STATUS: %', p_terminal_status USING ERRCODE = 'P0001';
    END IF;

    -- STEP 1 (Table 1): Lock campaign FOR SHARE (blocks during REBUILDING_GATE)
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR SHARE;

    IF NOT FOUND OR v_campaign_status NOT IN ('ACTIVE', 'ENDED') THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_AVAILABLE_FOR_EXPIRY' USING ERRCODE = 'P0001';
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 2): Transition claim to EXPIRED / CANCELLED
    UPDATE public.flash_sale_claims fsc
       SET status = p_terminal_status,
           release_epoch = v_current_epoch,
           stock_returned_to_redis = CASE WHEN v_campaign_status OPERATOR(pg_catalog.=) 'ACTIVE' THEN FALSE ELSE TRUE END,
           version = fsc.version + 1,
           updated_at = pg_catalog.now()
     WHERE fsc.claim_id OPERATOR(pg_catalog.=) p_claim_id
       AND fsc.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND fsc.status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED')
    RETURNING fsc.sku_id, fsc.customer_id, fsc.quantity, fsc.version
      INTO v_sku_id, v_customer_id, v_qty, v_new_version;

    IF NOT FOUND THEN
        RETURN QUERY SELECT FALSE, NULL::UUID, 0, v_current_epoch;
        RETURN;
    END IF;

    -- STEP 3 (Table 3): Decrement claimed_count
    UPDATE public.flash_sale_items fsi
       SET claimed_count = GREATEST(0, fsi.claimed_count - v_qty),
           updated_at = pg_catalog.now()
     WHERE fsi.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND fsi.sku_id OPERATOR(pg_catalog.=) v_sku_id;

    -- STEP 4 (Table 4): Insert Outbox event
    INSERT INTO public.outbox_messages (
        event_id, shard_id, aggregate_type, aggregate_id, aggregate_version,
        event_type, topic, partition_key, payload, headers, created_at
    ) VALUES (
        p_event_id,
        pg_catalog.mod(pg_catalog.abs(pg_catalog.hashtext(v_customer_id::text)), 16),
        'FlashSaleClaim',
        p_claim_id::text,
        v_new_version,
        'commerce.flashsale.claim_released.v1',
        'commerce.flashsale.events.v1',
        v_customer_id::text,
        p_payload_jsonb,
        p_headers_jsonb,
        pg_catalog.now()
    );

    RETURN QUERY SELECT TRUE, v_sku_id, v_qty, v_current_epoch;
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-04: Restock Finalization (stock_returned_to_redis = FALSE -> TRUE)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp04_restock_finalize(
    p_claim_id      UUID,
    p_campaign_id   UUID,
    p_release_epoch BIGINT
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
    v_rows            INTEGER;
BEGIN
    -- STEP 1 (Table 1): Lock campaign FOR SHARE & verify epoch matches release_epoch
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR SHARE;

    IF NOT FOUND
       OR v_campaign_status OPERATOR(pg_catalog.<>) 'ACTIVE'
       OR v_current_epoch OPERATOR(pg_catalog.<>) p_release_epoch THEN
        RETURN FALSE;
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 2): Mark stock_returned_to_redis = TRUE
    UPDATE public.flash_sale_claims fsc
       SET stock_returned_to_redis = TRUE,
           version = fsc.version + 1,
           updated_at = pg_catalog.now()
     WHERE fsc.claim_id OPERATOR(pg_catalog.=) p_claim_id
       AND fsc.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND fsc.release_epoch OPERATOR(pg_catalog.=) v_current_epoch
       AND fsc.stock_returned_to_redis IS FALSE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-05: Order Materialization & Payment Confirmation Progress
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp05_order_payment_progress(
    p_claim_id        UUID,
    p_campaign_id     UUID,
    p_expected_status VARCHAR(32),
    p_next_status     VARCHAR(32)
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
    v_rows            INTEGER;
BEGIN
    IF NOT (p_expected_status OPERATOR(pg_catalog.=) 'CLAIMED_RESERVED' AND p_next_status OPERATOR(pg_catalog.=) 'ORDER_MATERIALIZED')
       AND NOT (p_expected_status OPERATOR(pg_catalog.=) 'ORDER_MATERIALIZED' AND p_next_status OPERATOR(pg_catalog.=) 'PAYMENT_CONFIRMED') THEN
        RAISE EXCEPTION 'INVALID_PROGRESS_TRANSITION: % -> %', p_expected_status, p_next_status USING ERRCODE = 'P0001';
    END IF;

    -- STEP 1 (Table 1): Lock campaign FOR SHARE (blocks during REBUILDING_GATE)
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR SHARE;

    IF NOT FOUND OR v_campaign_status NOT IN ('ACTIVE', 'ENDED') THEN
        RAISE EXCEPTION 'CAMPAIGN_REBUILDING_TRY_AGAIN' USING ERRCODE = 'P0001';
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 2): Advance claim status
    UPDATE public.flash_sale_claims fsc
       SET status = p_next_status,
           version = fsc.version + 1,
           updated_at = pg_catalog.now()
     WHERE fsc.claim_id OPERATOR(pg_catalog.=) p_claim_id
       AND fsc.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND fsc.status OPERATOR(pg_catalog.=) p_expected_status;

    GET DIAGNOSTICS v_rows = ROW_COUNT;
    RETURN v_rows > 0;
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-06: Admin Item & Quota Configuration (Only in DRAFT / APPROVED)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp06_admin_configure_item(
    p_campaign_id     UUID,
    p_sku_id          UUID,
    p_allocated_quota INTEGER
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_current_epoch   BIGINT;
    v_campaign_status VARCHAR(32);
BEGIN
    IF p_allocated_quota < 0 THEN
        RAISE EXCEPTION 'INVALID_ALLOCATED_QUOTA: %', p_allocated_quota USING ERRCODE = 'P0001';
    END IF;

    -- STEP 1 (Table 1): Lock campaign FOR UPDATE
    SELECT cs.current_epoch, cs.status
      INTO v_current_epoch, v_campaign_status
      FROM public.flash_sale_campaigns cs
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       FOR UPDATE;

    IF NOT FOUND OR v_campaign_status NOT IN ('DRAFT', 'APPROVED') THEN
        RAISE EXCEPTION 'QUOTA_EDIT_FORBIDDEN_IN_STATUS: %', v_campaign_status USING ERRCODE = 'P0001';
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_current_epoch);

    -- STEP 2 (Table 3): Upsert item quota
    INSERT INTO public.flash_sale_items (
        campaign_id, sku_id, allocated_quota, claimed_count, created_at, updated_at
    ) VALUES (
        p_campaign_id, p_sku_id, p_allocated_quota, 0, pg_catalog.now(), pg_catalog.now()
    )
    ON CONFLICT (campaign_id, sku_id) DO UPDATE
       SET allocated_quota = EXCLUDED.allocated_quota,
           updated_at = pg_catalog.now();
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-07: Rebuilder Exclusive Fence & Snapshot (REBUILDING_GATE)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp07_rebuilder_fence_and_snapshot(
    p_campaign_id UUID
) RETURNS TABLE (
    new_epoch       BIGINT,
    sku_id          UUID,
    allocated_quota INTEGER,
    claimed_count   INTEGER,
    remaining_stock INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_new_epoch BIGINT;
BEGIN
    -- STEP 1 (Table 1): Acquire EXCLUSIVE FOR UPDATE lock on public.flash_sale_campaigns.
    -- Blocks until 100% of prior FOR SHARE holders (MP-01..MP-05) have COMMITted or ROLLBACKed!
    UPDATE public.flash_sale_campaigns cs
       SET status = 'REBUILDING_GATE',
           current_epoch = cs.current_epoch + 1,
           updated_at = pg_catalog.now()
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND cs.status IN ('ACTIVE', 'REBUILDING_GATE')
    RETURNING cs.current_epoch INTO v_new_epoch;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CAMPAIGN_NOT_REBUILDABLE: %', p_campaign_id USING ERRCODE = 'P0001';
    END IF;

    PERFORM promotion_private.fn_set_campaign_lock_witness(p_campaign_id, v_new_epoch);

    -- STEP 2 (Table 2: public.flash_sale_claims, locked in deterministic claim_id ASC order):
    -- Mark all prior EXPIRED / CANCELLED / ABANDONED_FENCED claims as stock_returned_to_redis = TRUE
    UPDATE public.flash_sale_claims fsc
       SET stock_returned_to_redis = TRUE,
           updated_at = pg_catalog.now()
     WHERE fsc.claim_id IN (
         SELECT c.claim_id
           FROM public.flash_sale_claims c
          WHERE c.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
            AND c.status IN ('EXPIRED', 'CANCELLED', 'ABANDONED_FENCED')
            AND c.stock_returned_to_redis IS FALSE
          ORDER BY c.claim_id ASC
          FOR NO KEY UPDATE
     );

    -- STEP 3 (Table 3: public.flash_sale_items, locked in deterministic sku_id ASC order):
    -- Reconcile claimed_count to exact sum of active claims and return snapshot
    RETURN QUERY
    WITH locked_items AS (
        SELECT i.campaign_id, i.sku_id
          FROM public.flash_sale_items i
         WHERE i.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
         ORDER BY i.sku_id ASC
         FOR NO KEY UPDATE
    )
    UPDATE public.flash_sale_items fsi
       SET claimed_count = COALESCE((
           SELECT SUM(fsc.quantity)::INTEGER
             FROM public.flash_sale_claims fsc
            WHERE fsc.campaign_id OPERATOR(pg_catalog.=) fsi.campaign_id
              AND fsc.sku_id OPERATOR(pg_catalog.=) fsi.sku_id
              AND fsc.status IN ('CLAIMED_RESERVED', 'ORDER_MATERIALIZED', 'PAYMENT_CONFIRMED')
       ), 0),
           updated_at = pg_catalog.now()
      FROM locked_items li
     WHERE fsi.campaign_id OPERATOR(pg_catalog.=) li.campaign_id
       AND fsi.sku_id OPERATOR(pg_catalog.=) li.sku_id
    RETURNING v_new_epoch, fsi.sku_id, fsi.allocated_quota, fsi.claimed_count,
              (fsi.allocated_quota - fsi.claimed_count);
END;
$$;

-- -----------------------------------------------------------------------------
-- MP-08: Campaign Lifecycle Transition (0 -> DRAFT, DRAFT -> APPROVED -> WARMED -> ACTIVE -> ENDED)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_mp08_campaign_lifecycle(
    p_campaign_id    UUID,
    p_expected_epoch BIGINT,
    p_target_status  VARCHAR(32)
) RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, promotion_private, public, pg_temp
AS $$
DECLARE
    v_epoch BIGINT;
BEGIN
    IF p_target_status NOT IN ('DRAFT', 'APPROVED', 'WARMED', 'ACTIVE', 'REBUILDING_GATE', 'ENDED', 'RECONCILED') THEN
        RAISE EXCEPTION 'INVALID_CAMPAIGN_STATUS: %', p_target_status USING ERRCODE = 'P0001';
    END IF;

    IF p_expected_epoch OPERATOR(pg_catalog.=) 0 AND p_target_status OPERATOR(pg_catalog.=) 'DRAFT' THEN
        INSERT INTO public.flash_sale_campaigns (
            campaign_id, name, status, current_epoch, starts_at, ends_at, created_at, updated_at
        ) VALUES (
            p_campaign_id,
            'Campaign ' || p_campaign_id::text,
            'DRAFT',
            1,
            pg_catalog.now(),
            pg_catalog.now() + INTERVAL '2 hours',
            pg_catalog.now(),
            pg_catalog.now()
        )
        RETURNING current_epoch INTO v_epoch;
        RETURN v_epoch;
    END IF;

    UPDATE public.flash_sale_campaigns cs
       SET status = p_target_status,
           current_epoch = CASE WHEN p_target_status OPERATOR(pg_catalog.=) 'ENDED' THEN cs.current_epoch + 1 ELSE cs.current_epoch END,
           updated_at = pg_catalog.now()
     WHERE cs.campaign_id OPERATOR(pg_catalog.=) p_campaign_id
       AND cs.current_epoch OPERATOR(pg_catalog.=) p_expected_epoch
    RETURNING cs.current_epoch INTO v_epoch;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'CAMPAIGN_LIFECYCLE_EPOCH_MISMATCH' USING ERRCODE = 'P0001';
    END IF;

    RETURN v_epoch;
END;
$$;

-- =============================================================================
-- PART 3: Explicit Ownership Transfer & Least-Privilege Function Grants
-- =============================================================================

ALTER FUNCTION public.fn_mp01_writer_claim(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, UUID, JSONB, JSONB, JSONB, BIGINT)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp02_reconcile_fenced(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp03_expire_or_cancel(UUID, UUID, VARCHAR, UUID, JSONB, JSONB)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp04_restock_finalize(UUID, UUID, BIGINT)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp05_order_payment_progress(UUID, UUID, VARCHAR, VARCHAR)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp06_admin_configure_item(UUID, UUID, INTEGER)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp07_rebuilder_fence_and_snapshot(UUID)
    OWNER TO promotion_proc_owner;
ALTER FUNCTION public.fn_mp08_campaign_lifecycle(UUID, BIGINT, VARCHAR)
    OWNER TO promotion_proc_owner;

REVOKE ALL ON FUNCTION
    public.fn_mp01_writer_claim(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, UUID, JSONB, JSONB, JSONB, BIGINT),
    public.fn_mp02_reconcile_fenced(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ),
    public.fn_mp03_expire_or_cancel(UUID, UUID, VARCHAR, UUID, JSONB, JSONB),
    public.fn_mp04_restock_finalize(UUID, UUID, BIGINT),
    public.fn_mp05_order_payment_progress(UUID, UUID, VARCHAR, VARCHAR),
    public.fn_mp06_admin_configure_item(UUID, UUID, INTEGER),
    public.fn_mp07_rebuilder_fence_and_snapshot(UUID),
    public.fn_mp08_campaign_lifecycle(UUID, BIGINT, VARCHAR)
FROM PUBLIC, promotion_migrator;

GRANT EXECUTE ON FUNCTION
    public.fn_mp01_writer_claim(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ, TIMESTAMPTZ, UUID, JSONB, JSONB, JSONB, BIGINT),
    public.fn_mp02_reconcile_fenced(UUID, UUID, BIGINT, UUID, UUID, VARCHAR, INTEGER, TIMESTAMPTZ),
    public.fn_mp03_expire_or_cancel(UUID, UUID, VARCHAR, UUID, JSONB, JSONB),
    public.fn_mp04_restock_finalize(UUID, UUID, BIGINT),
    public.fn_mp05_order_payment_progress(UUID, UUID, VARCHAR, VARCHAR),
    public.fn_mp06_admin_configure_item(UUID, UUID, INTEGER),
    public.fn_mp07_rebuilder_fence_and_snapshot(UUID),
    public.fn_mp08_campaign_lifecycle(UUID, BIGINT, VARCHAR)
TO promotion_app_role, promotion_dba_admin;

RESET ROLE;
