# Data Architecture & Database Ownership — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-DATA-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Database Ownership Matrix

Every persistent store has **exactly one owning service**. No other service may hold credentials to, query, or mutate another service's database or Redis key namespace.

| Owning Service | Database / Store Name | Engine | Core Tables / Collections / Key Prefixes | Migration Tool |
| :--- | :--- | :--- | :--- | :--- |
| **`product-service`** (Java) | `product_db` | PostgreSQL 17 | `categories`, `products`, `product_variants`, `product_media`, `product_search_index`, `outbox_messages`, `inbox_messages` | Flyway |
| | `redis` (`db=0`) | Redis 7.4 | `catalog:product:{id}`, `catalog:sku:{code}`, `catalog:category:tree` | N/A (TTL Cache) |
| | `minio` | MinIO (S3) | Bucket: `product-media` (public read via policy/CDN, pre-signed PUT for Admin) | Init Job |
| **`customer-service`** (.NET) | `customer_db` | PostgreSQL 17 | `customers`, `shipping_addresses`, `refresh_tokens`, `outbox_messages` | EF Core Migrations |
| | `redis` (`db=0`) | Redis 7.4 | `cart:customer:{customerId}`, `auth:blacklist:jti:{jti}` | N/A |
| **`order-service`** (Java) | `order_db` | PostgreSQL 17 | `orders`, `order_lines`, `order_saga_states`, `order_status_history`, `outbox_messages`, `inbox_messages` | Flyway |
| **`inventory-service`** (Java) | `inventory_db` | PostgreSQL 17 | `stock_items`, `stock_reservations`, `inventory_ledger_entries`, `outbox_messages`, `inbox_messages` | Flyway |
| | `redis` (`db=0`) | Redis 7.4 | `inventory:avail:sku:{skuId}` (read-only fast badge cache, short TTL) | N/A |
| **`payment-service`** (Java) | `payment_db` | PostgreSQL 17 | `payment_transactions`, `payment_attempts`, `refund_records`, `outbox_messages`, `inbox_messages` | Flyway |
| **`promotion-service`** (.NET) | `promotion_db` | PostgreSQL 17 | `coupon_campaigns`, `coupon_redemptions`, `flash_sale_campaigns`, `flash_sale_items`, `flash_sale_claims`, `outbox_messages`, `inbox_messages` | EF Core Migrations |
| | `redis` (`db=0`) | Redis 7.4 | `flashsale:{campaignId}:sku:{skuId}:meta`, `flashsale:{campaignId}:sku:{skuId}:stock`, `flashsale:{campaignId}:sku:{skuId}:buyers` | Lua Scripts |
| **`notification-service`** (.NET) | `notification_db` | PostgreSQL 17 | `notification_dispatches`, `inbox_messages` | EF Core Migrations |
| **`ai-agent-service`** (Python) | `ai_agent_db` | PostgreSQL 17 + `pgvector` | `embedding_index_generations`, `knowledge_chunks`, `chunk_embeddings` (multi-dimension `vector` per generation), `conversation_sessions`, `conversation_messages`, `tool_audit_logs`, `pending_human_approvals` | Alembic |
| **`api-gateway`** (.NET) | `redis` (`db=0`) | Redis 7.4 | `ratelimit:ip:{ip}`, `ratelimit:user:{userId}` | N/A |

---

## 2. Core Relational Schemas, Indexes & Constraints

### 2.1 `inventory_db` (Java `inventory-service`)

```sql
CREATE TABLE stock_items (
    sku_id                      UUID PRIMARY KEY,
    sku_code                    VARCHAR(64) NOT NULL UNIQUE,
    available_qty               INTEGER NOT NULL DEFAULT 0 CHECK (available_qty >= 0),
    reserved_qty                INTEGER NOT NULL DEFAULT 0 CHECK (reserved_qty >= 0),
    flash_sale_allocated_qty    INTEGER NOT NULL DEFAULT 0 CHECK (flash_sale_allocated_qty >= 0),
    flash_sale_reserved_qty     INTEGER NOT NULL DEFAULT 0 CHECK (flash_sale_reserved_qty >= 0),
    version                     BIGINT  NOT NULL DEFAULT 0,
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE stock_reservations (
    reservation_id              UUID PRIMARY KEY,
    order_id                    UUID NOT NULL,
    sku_id                      UUID NOT NULL REFERENCES stock_items(sku_id),
    quantity                    INTEGER NOT NULL CHECK (quantity > 0),
    reservation_type            VARCHAR(20) NOT NULL CHECK (reservation_type IN ('STANDARD', 'FLASH_SALE')),
    status                      VARCHAR(20) NOT NULL CHECK (status IN ('RESERVED', 'COMMITTED', 'RELEASED', 'EXPIRED')),
    expires_at                  TIMESTAMPTZ NOT NULL,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_reservation_order_sku UNIQUE (order_id, sku_id)
);

-- Partial index for the background expiration sweeper (scans only active reservations)
CREATE INDEX idx_reservations_active_expiry
    ON stock_reservations (expires_at)
    WHERE status = 'RESERVED';

CREATE TABLE inventory_ledger_entries (
    entry_id                    UUID PRIMARY KEY,
    sku_id                      UUID NOT NULL REFERENCES stock_items(sku_id),
    delta_available             INTEGER NOT NULL,
    delta_reserved              INTEGER NOT NULL,
    delta_flash_allocated       INTEGER NOT NULL DEFAULT 0,
    delta_flash_reserved        INTEGER NOT NULL DEFAULT 0,
    balance_available_after     INTEGER NOT NULL CHECK (balance_available_after >= 0),
    reason                      VARCHAR(40) NOT NULL,
    reference_id                VARCHAR(128) NOT NULL,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ledger_sku_created ON inventory_ledger_entries (sku_id, created_at DESC);
```

### 2.2 `order_db` (Java `order-service`)

```sql
CREATE TABLE orders (
    order_id                    UUID PRIMARY KEY,
    customer_id                 UUID NOT NULL,
    idempotency_key             VARCHAR(128) NOT NULL,
    order_type                  VARCHAR(20) NOT NULL CHECK (order_type IN ('STANDARD', 'FLASH_SALE')),
    flash_sale_campaign_id      UUID NULL,
    coupon_code                 VARCHAR(64) NULL,
    status                      VARCHAR(32) NOT NULL,
    currency                    CHAR(3) NOT NULL DEFAULT 'USD',
    subtotal_amount             NUMERIC(19, 4) NOT NULL CHECK (subtotal_amount >= 0),
    discount_amount             NUMERIC(19, 4) NOT NULL DEFAULT 0 CHECK (discount_amount >= 0),
    total_amount                NUMERIC(19, 4) NOT NULL CHECK (total_amount >= 0),
    shipping_address_snapshot   JSONB NOT NULL,
    expires_at                  TIMESTAMPTZ NOT NULL,
    version                     BIGINT NOT NULL DEFAULT 0,
    created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_orders_customer_idempotency UNIQUE (customer_id, idempotency_key),
    CONSTRAINT chk_orders_total_math CHECK (total_amount = subtotal_amount - discount_amount)
);

CREATE INDEX idx_orders_customer_created ON orders (customer_id, created_at DESC);
CREATE INDEX idx_orders_awaiting_payment_expiry ON orders (expires_at)
    WHERE status IN ('PENDING_RESERVATION', 'AWAITING_PAYMENT');
```

### 2.3 Standardized Outbox & Inbox Tables (All Event-Driven Services)

```sql
CREATE TABLE outbox_messages (
    outbox_sequence BIGSERIAL UNIQUE NOT NULL,
    event_id        UUID PRIMARY KEY,
    aggregate_type  VARCHAR(64) NOT NULL,
    aggregate_id    VARCHAR(128) NOT NULL,
    aggregate_version BIGINT NOT NULL DEFAULT 1,
    event_type      VARCHAR(128) NOT NULL,
    topic           VARCHAR(128) NOT NULL,
    partition_key   VARCHAR(128) NOT NULL,
    payload         JSONB NOT NULL,
    headers         JSONB NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at    TIMESTAMPTZ NULL,
    retry_count     INTEGER NOT NULL DEFAULT 0,
    last_error      TEXT NULL
);

-- Critical partial index so the Outbox Relay never scans already-published rows
CREATE INDEX idx_outbox_unprocessed ON outbox_messages (outbox_sequence ASC)
    WHERE processed_at IS NULL;

CREATE TABLE inbox_messages (
    event_id        UUID NOT NULL,
    consumer_group  VARCHAR(128) NOT NULL,
    event_type      VARCHAR(128) NOT NULL,
    aggregate_id    VARCHAR(128) NULL,
    aggregate_version BIGINT NULL,
    processed_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (event_id, consumer_group)
);
```

---

## 3. Flash Sale Redis Lua Atomic Gate Design

During a Flash Sale, `promotion-service` executes the following atomic Lua script on Redis so checking campaign status, enforcing per-user limits, and decrementing stock occur as a **single indivisible operation**:

```lua
-- KEYS[1]: flashsale:{campaignId}:sku:{skuId}:meta   (Hash: start_ts, end_ts, per_user_limit, status)
-- KEYS[2]: flashsale:{campaignId}:sku:{skuId}:stock  (String: integer remaining stock)
-- KEYS[3]: flashsale:{campaignId}:sku:{skuId}:buyers (Hash: customerId -> claimed_qty)
-- ARGV[1]: now_epoch_ms
-- ARGV[2]: customer_id
-- ARGV[3]: requested_qty
-- ARGV[4]: claim_id

local status = redis.call('HGET', KEYS[1], 'status')
if status ~= 'ACTIVE' then
    return {0, 'CAMPAIGN_NOT_ACTIVE'}
end

local start_ts = tonumber(redis.call('HGET', KEYS[1], 'start_ts'))
local end_ts   = tonumber(redis.call('HGET', KEYS[1], 'end_ts'))
local now_ts   = tonumber(ARGV[1])
if now_ts < start_ts or now_ts > end_ts then
    return {0, 'OUTSIDE_CAMPAIGN_WINDOW'}
end

local limit = tonumber(redis.call('HGET', KEYS[1], 'per_user_limit'))
local req_qty = tonumber(ARGV[3])
local prev_qty = tonumber(redis.call('HGET', KEYS[3], ARGV[2]) or '0')
if (prev_qty + req_qty) > limit then
    return {0, 'USER_LIMIT_EXCEEDED'}
end

local stock = tonumber(redis.call('GET', KEYS[2]) or '0')
if stock < req_qty then
    return {0, 'SOLD_OUT'}
end

local remaining = redis.call('DECRBY', KEYS[2], req_qty)
redis.call('HINCRBY', KEYS[3], ARGV[2], req_qty)
return {1, 'CLAIMED', remaining, ARGV[4]}
```

---

## 4. Connection Pooling & Persistence Behavior Guidelines

1. **HikariCP (Java Services)**:
   - Default `maximumPoolSize` per pod: `10–15` (never `50+`, which overwhelms PostgreSQL `max_connections` when scaling pods horizontally).
   - `spring.jpa.open-in-view: false` is **mandatory** across all Spring Boot services so database connections are never held open during HTTP serialization or external I/O.
   - `hibernate.jdbc.batch_size: 50` and `order_inserts: true` / `order_updates: true` enabled.
2. **Npgsql Connection Pooling (.NET Services)**:
   - Explicit `MaxPoolSize=15`, `ConnectionIdleLifetime=60`, `NoResetOnClose=true` where safe.
   - Read queries must use `.AsNoTracking()` to bypass `ChangeTracker` snapshot allocation overhead.
3. **Transaction Isolation Level**:
   - Default `READ COMMITTED` in PostgreSQL across all services, paired with explicit atomic conditional `UPDATE` or `SELECT ... FOR UPDATE` / `@Version` optimistic locking. Avoid `SERIALIZABLE` on high-contention tables (`stock_items`) where serialization failures (`SQLSTATE 40001`) would cause massive abort storms under spike load.
