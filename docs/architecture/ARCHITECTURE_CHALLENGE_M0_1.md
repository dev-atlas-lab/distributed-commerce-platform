# Deep Architecture Challenge & Unresolved Edge-Case Specifications (`M0.1`)

- **Document ID:** `DCP-DOC-ARCH-008`
- **Status:** `PROPOSED` (Phase 4 Architecture Challenge — Requires Human Architect Approval)
- **Date:** 2026-11-10

---

## Purpose

Even with our 7 primary architecture decisions (`Q1–Q7`) locked as `ACCEPTED` (`ADR-0001` through `ADR-0011`), production distributed systems fail in the subtle cracks between components: **partial crashes between Redis and PostgreSQL, expiry jobs racing against webhooks, out-of-order Kafka retries, and multi-provider embedding dimension mismatches**.

In accordance with our working philosophy (*"Challenge decisions when identifying architectural flaws, race conditions, or incorrect assumptions; do not mark unresolved proposals as ACCEPTED"*), this document presents **7 concrete engineering challenges (`CH-01` through `CH-07`)**. Each challenge remains in **`PROPOSED`** status until you review and approve it.

---

## Challenge `CH-01` — Inventory Reservation & Flash Sale Redis-to-DB Partial Failure Race (`Status: PROPOSED`)

### 1. Problem
In `ADR-0005` (`ACCEPTED`), a Flash Sale claim first executes `flash_sale_claim.lua` in Redis (atomically decrementing `stock` from `1000 → 999` and adding `customerId` to `buyers`), and then `Promotion Service` writes `FlashSaleClaim` + `Outbox(FlashSaleSlotClaimed)` to PostgreSQL.
- **Race / Failure Window**: What if `EVALSHA` succeeds in Redis, and `2 milliseconds` later the `promotion-service` pod is `OOMKilled`, loses its PostgreSQL connection, or crashes before the PostgreSQL transaction commits?
  - In Redis: `customerId` is marked as having already claimed (`USER_LIMIT_EXCEEDED` if they retry!), and `1` unit of stock is permanently deducted (`999` left).
  - In PostgreSQL: Zero `FlashSaleClaim` or `Order` exists.
- **Second Race (Option A Expiry Return Race)**: When a `10-minute` unpaid reservation expires (`Q4 Option A`), what if the background Expiration Worker runs `flash_sale_release.lua` in Redis twice due to a Kafka consumer retry, or what if the user cancels the order at `T = 9m59.9s` simultaneously with the Expiration Worker at `T = 10m00.0s`? Without a strict idempotency token inside Redis Lua, `stock` would be incremented **twice** (`INCRBY` $\times 2$), causing an **oversell**!

### 2. Technical Implications
- A naive Redis decrement followed by DB insert violates both **liveness** (crashed user is locked out on retry) and **conservation of stock** (orphaned Redis decrement leaks stock; duplicate release oversells stock).

### 3. Proposed Solution (`PROPOSED`)
1. **Idempotent Retry inside `flash_sale_claim.lua` using `claim_token` (`Idempotency-Key`)**:
   - Instead of storing only `customerId -> qty` in Redis `buyers`, store `HSET flashsale:{campaignId}:sku:{skuId}:claims {customerId} "{claimId}:{idempotencyKey}:{timestampMs}"`.
   - If the client retries with the **same `(customerId, Idempotency-Key)`** after a pod crash, `flash_sale_claim.lua` sees the matching `idempotencyKey` and returns `{1, 'ALREADY_CLAIMED_IDEMPOTENT', existingClaimId}` so `promotion-service` can complete the missing PostgreSQL `INSERT INTO flash_sale_claims ... ON CONFLICT DO NOTHING`!
2. **Idempotent Release Guard in `flash_sale_release.lua` (`Q4 Option A` Safeguard)**:
   - Before `INCRBY stock`, `flash_sale_release.lua` executes `HSETNX flashsale:{campaignId}:sku:{skuId}:released_claims {claimId} {nowMs}`.
   - If `HSETNX` returns `0` (already released by either user cancellation or a previous expiry sweep), the Lua script returns `{0, 'ALREADY_RELEASED'}` and **never** increments stock a second time.
3. **30-Second Orphan Reconciliation Sweeper**:
   - Every 30s, `Promotion Service` inspects Redis claims older than `30 seconds` (`timestampMs < now - 30000`) that have no matching row in PostgreSQL `flash_sale_claims`. Any uncommitted orphan older than 30s is atomically rolled back via `flash_sale_release.lua`.

### 4. Alternatives Considered
- **Alternative A**: Write a `PENDING_CLAIM` row to PostgreSQL *before* calling Redis Lua.
  - *Why rejected*: Forces `100,000` losing requests to hit PostgreSQL before Redis can reject them, defeating the entire purpose of the Redis gate!
- **Alternative B**: Redis Streams (`XADD`) inside the Lua script consumed by a Redis Stream worker.
  - *Trade-off*: Very fast, but adds a second messaging durability model alongside Kafka Outbox.

### 5. Trade-offs
- Storing `claimId:idempotencyKey:timestampMs` per winner in Redis uses `~80 bytes × 1,000 winners = ~80 KB` of Redis RAM per campaign—negligible cost for 100% crash recovery and zero double-restock risk.

### 6. User Approval Required?
- **YES** — Approve `CH-01` (Lua `idempotencyKey` retry recovery + `HSETNX released_claims` double-release guard + 30s orphan sweep).

---

## Challenge `CH-02` — Reservation Expiry vs. Payment Webhook Race & Fencing (`Status: PROPOSED`)

### 1. Problem
Consider an `Order` (`order_id = ORD-123`) whose `10-minute` Flash Sale payment window expires at `16:10:00.000Z`:
- At `16:09:59.800Z`, the customer clicks "Pay" in the Payment Simulator.
- At `16:10:00.050Z`, the `Order Service` Expiration Sweeper selects `ORD-123` (`WHERE status = 'AWAITING_PAYMENT' AND expires_at <= NOW()`) and begins transitioning it to `EXPIRED` + emitting `OrderExpired` (which triggers `Q4 Option A` stock return to another shopper!).
- At `16:10:00.100Z`, the `PaymentSucceeded` event from `Payment Service` arrives at `Order Service`.
- **What if both threads execute concurrently, or what if `Payment Service` processes a `confirmPayment` HTTP call 50ms *after* `Order Service` already expired the order?**

### 2. Technical Implications
If `Order Service` allows `EXPIRED → CONFIRMED`, the platform confirms an order whose inventory was just released back to the Flash Sale pool and bought by another user (**oversell!**). Conversely, if `Order Service` ignores `PaymentSucceeded` on an `EXPIRED` order, the customer's money is captured with no order and no refund (**financial loss!**).

### 3. Proposed Solution (`PROPOSED`)
1. **Strict State-Transition Monotonicity with Row Lock / `@Version`**:
   - In `Order Service`, `EXPIRED` and `CANCELLED` are **terminal for fulfillment** (`EXPIRED` can NEVER transition to `CONFIRMED`).
   - Both the Expiration Sweeper and the `PaymentSucceeded` consumer mutate `Order` inside a transaction that checks `@Version` (or `SELECT ... FOR UPDATE` on `orders WHERE order_id = :id`).
2. **Deterministic Race Resolution Matrix**:
   - **Case 1 (`PaymentSucceeded` wins the lock at `16:10:00.020Z` before Expiry commits)**: `Order` transitions `AWAITING_PAYMENT → CONFIRMED`. When the Expiry Sweeper attempts to expire `ORD-123`, the `WHERE status = 'AWAITING_PAYMENT'` / `@Version` check matches `0` rows and cleanly skips it.
   - **Case 2 (`Expiry Sweeper` wins the lock at `16:10:00.020Z` before `PaymentSucceeded` arrives)**: `Order` transitions `AWAITING_PAYMENT → EXPIRED` and emits `OrderExpired` (releasing stock). When `PaymentSucceeded` arrives `80ms` later and sees `Order.status == EXPIRED`, `Order Service` transitions `Order` to `EXPIRED_REFUND_PENDING` and atomically writes `Outbox(PaymentRefundRequested { orderId, paymentId, reason: "LATE_PAYMENT_AFTER_EXPIRY" })` in the same transaction.
3. **Pre-Capture Expiry Cutoff in `Payment Service`**:
   - When `PaymentRequested` creates a `PaymentTransaction`, it copies `order_expires_at` onto `payment_transactions.expires_at`. `Payment Service` rejects direct user `POST /api/v1/payments/{orderId}/confirm` calls if `NOW() >= expires_at - INTERVAL '2 seconds'` (safety grace buffer), while still handling asynchronous late gateway webhooks via Case 2 auto-refund.

### 4. Alternatives Considered
- **Synchronous HTTP call from `Payment Service` to `Order Service` during webhook processing**: Adds synchronous coupling and fails if `Order Service` is restarting during a deployment.

### 5. Trade-offs
- Case 2 results in an occasional automatic refund when a customer pays at the exact final second of a 10-minute window, which is standard production e-commerce behavior and preserves the zero-oversell invariant 100% of the time.

### 6. User Approval Required?
- **YES** — Approve `CH-02` (Terminal `EXPIRED` state + `EXPIRED_REFUND_PENDING` auto-refund compensation + 2s pre-capture expiry buffer).

---

## Challenge `CH-03` — Idempotency Key Lifecycle, Payload Fingerprint & Concurrency Boundary (`Status: PROPOSED`)

### 1. Problem
We require `Idempotency-Key: <UUID>` on mutating endpoints (`POST /api/v1/orders`, `POST /api/v1/flash-sales/{id}/claim`, `POST /api/v1/payments`). Three edge cases arise in real systems:
1. **In-Flight Concurrent Duplicate**: Client sends Request A (`Idempotency-Key: K1`), and `10ms` later (before Request A finishes committing) sends Request B with the **same `K1`**.
2. **Key Reuse with Different Payload**: Client sends `K1` with `{skuId: "A", qty: 1}` and later accidentally sends the same `K1` with `{skuId: "B", qty: 5}`.
3. **Failure Retryability**: If Request A with `K1` fails with a `400 Validation Error` or `503 Transient DB Timeout`, should a retry with `K1` be blocked or allowed?

### 2. Technical Implications
Returning a `201 Created` from `{skuId: "A"}` when the caller sent `{skuId: "B"}` with a reused key causes silent data corruption.

### 3. Proposed Solution (`PROPOSED`)
1. **Scope & Payload Hash**: Scope idempotency keys by `(customer_id, endpoint, idempotency_key)` and store a `request_hash` (`SHA-256` of canonical request JSON body).
2. **Response Matrix**:
   - **Same Key + Different `request_hash`** → Return **`422 Unprocessable Entity`** (`IDEMPOTENCY_KEY_PAYLOAD_MISMATCH`).
   - **Same Key + Same `request_hash` + First Request Still `IN_PROGRESS`** → Return **`409 Conflict`** (`IDEMPOTENCY_REQUEST_IN_PROGRESS` with `Retry-After: 1`) rather than blocking threads.
   - **Same Key + Same `request_hash` + First Request `COMPLETED` (`2xx` or terminal business `409`)** → Replay the stored status code and response body without re-executing business logic.
   - **First Request Failed with `5xx` (Transient Error)** → Roll back the idempotency record so the client's retry with the same `Idempotency-Key` executes cleanly!

### 4. Alternatives Considered
- Blocking the second concurrent request on a distributed lock until the first request finishes (ties up worker threads during spikes).

### 5. Trade-offs
- Computing `SHA-256` on a `1 KB` JSON body takes `<5 microseconds` and prevents accidental key reuse bugs.

### 6. User Approval Required?
- **YES** — Approve `CH-03` (Payload `SHA-256` fingerprint check + `409 IN_PROGRESS` on concurrent duplicate + rollback on `5xx`).

---

## Challenge `CH-04` — Outbox/Inbox Ordering vs. Non-Blocking Retry Topics (`Status: PROPOSED`)

### 1. Problem
In `ADR-0003` & `ADR-0010` (`ACCEPTED`), Saga events are keyed by `orderId` so `OrderCreated`, `PaymentSucceeded`, and `OrderCancelled` land on the same Kafka partition.
- **Ordering Hazard with Retry Topics**: Suppose `Event 1` (`OrderCreated` for `ORD-99`) fails transiently in `Inventory Service` (e.g., brief lock timeout) and is forwarded to `commerce.order.events.inventory-cg.retry.1m`. Meanwhile, `500ms` later, the customer cancels `ORD-99`, so `Event 2` (`OrderCancelled` for `ORD-99`) arrives on the **main** topic and is processed *before* `Event 1` finishes its 1-minute retry! When `Event 1` finally replays from the retry topic 1 minute later, `Inventory Service` might reserve stock for an already-cancelled order!

### 2. Technical Implications
Non-blocking retry topics trade away strict per-key partition ordering when a message is shunted to a retry topic while newer messages for the same aggregate key proceed on the main topic.

### 3. Proposed Solution (`PROPOSED`)
1. **Saga / Aggregate Tombstone & Monotonic State Guard (`Inventory` & `Promotion`)**:
   - If `OrderCancelled` / `ReleaseStock` arrives for an `order_id` that has **no** `StockReservation` row yet, `Inventory Service` inserts a terminal tombstone row: `StockReservation(order_id, sku_id, status = 'CANCELLED_BEFORE_RESERVE', qty = 0)`.
   - When the delayed `OrderCreated` (`ReserveStock`) event arrives 1 minute later from the retry topic, the `UNIQUE (order_id, sku_id)` constraint sees `status == 'CANCELLED_BEFORE_RESERVE'` and safely ignores the late reservation!
2. **Short In-Place Backoff Before Shunting to Retry Topic**:
   - For stateful Saga consumers (`Order`, `Inventory`, `Payment`, `Promotion`), perform `3` fast in-memory retries (`100ms → 250ms → 500ms`) in the consumer poll loop before publishing to the `.retry.1m` topic. This resolves `99%` of transient lock/connection blips *without* breaking partition order, reserving `.retry.1m` and `.dlq.v1` strictly for prolonged outages or poison pills.

### 4. Alternatives Considered
- **Infinite blocking retry on the main partition**: Preserves ordering 100%, but a single malformed poison message halts the entire partition for all other customers' orders.

### 5. Trade-offs
- Combining `3` fast in-place retries (`<1s` total) + a `CANCELLED_BEFORE_RESERVE` tombstone record gives us **both** poison-pill isolation and immunity to out-of-order retry races.

### 6. User Approval Required?
- **YES** — Approve `CH-04` (3 short in-place retries + `CANCELLED_BEFORE_RESERVE` tombstone guard for out-of-order retry events).

---

## Challenge `CH-05` — OIDC Issuer URI, Audience & Service-to-Service Auth across Docker & K8s (`Status: PROPOSED`)

### 1. Problem
In `ADR-0006` (`ACCEPTED`), all services validate `RS256` JWTs using OIDC Discovery (`/.well-known/openid-configuration` & `/.well-known/jwks.json`).
- **The Split-Horizon Issuer URL Trap**: In Docker Compose and Kubernetes, a browser obtains a token from external URL `https://auth.commerce.dev-atlas.lab` (or `http://localhost:5000`), so the JWT's `"iss"` claim is `"https://auth.commerce.dev-atlas.lab"`. However, when `order-service` inside a container fetches the JWKS keys from `customer-service`, `order-service` must connect over the internal container network (`http://customer-service:8080/.well-known/jwks.json`), NOT `localhost`! If `order-service` sets `issuer-uri: http://customer-service:8080`, JWT validation fails because `"iss"` in the token does not match the internal hostname!
- **Service-to-Service Auth for Background Workers**: When `Order Service` or `AI Agent Service` calls another service during a user HTTP request, it propagates the user's JWT. What about background scheduled jobs (e.g., `Promotion Service` pre-warming Flash Sale quota or querying `Inventory Service` outside a user request)?

### 2. Technical Implications
Mismatched `iss` vs. `jwks_uri` is the #1 cause of broken OIDC setups in containerized microservices (including Keycloak migrations).

### 3. Proposed Solution (`PROPOSED`)
1. **Explicit Separation of `AUTH_ISSUER_URI` (Logical Identifier) and `AUTH_JWKS_URI` (Internal Network Fetch URL)**:
   - Every service configures:
     - `AUTH_ISSUER_URI=https://auth.commerce.dev-atlas.lab` (logical string validated against the JWT `iss` claim).
     - `AUTH_JWKS_URI=http://customer-service:8080/.well-known/jwks.json` (internal cluster URL used to download public keys).
   - Both Spring Security (`jwk-set-uri` + `issuer-uri`) and .NET `JwtBearerOptions` (`ValidIssuer` + `MetadataAddress`/`IssuerSigningKeyResolver`) support this natively, and it works identically when switching to Keycloak!
2. **Audience (`aud`) & Service-to-Service (`client_credentials`)**:
   - User tokens carry `aud: ["commerce-api"]` and `sub: "<customer_uuid>"`.
   - For internal background jobs that must call protected internal APIs without a human user context, `customer-service` (and later Keycloak) supports OAuth2 **`grant_type=client_credentials`** issuing short-lived service tokens with `roles: ["INTERNAL_SERVICE"]` and `sub: "service:promotion-service"`.

### 4. Alternatives Considered
- Forcing pods to route out through external DNS/Hairpin NAT just to fetch JWKS keys (fragile and fails in local Docker Compose).

### 5. Trade-offs
- Zero runtime cost; completely eliminates Docker/K8s split-horizon OIDC errors.

### 6. User Approval Required?
- **YES** — Approve `CH-05` (Split `AUTH_ISSUER_URI` logical claim vs. `AUTH_JWKS_URI` internal fetch endpoint + `client_credentials` grant for background jobs).

---

## Challenge `CH-06` — API/Event Schema Evolution & Multi-Provider Embedding Dimension Alignment (`Status: PROPOSED`)

### 1. Problem
1. **Event Schema Evolution**: During rolling deployments in `M6`, `order-service v2` might publish an updated event while `notification-service v1` is still running. If consumers fail on unknown JSON properties (`FAIL_ON_UNKNOWN_PROPERTIES = true`), adding a single optional field breaks production consumers.
2. **Multi-Provider AI Embedding Dimension Mismatch (`Q7`)**: In `ADR-0008` (`ACCEPTED`), we support switching between **OpenAI** (`text-embedding-3-small` default `1536` dims), **Google Gemini** (`text-embedding-004` default `768` dims), and **Anthropic** (uses external/Voyage or configurable embeddings). In PostgreSQL `pgvector`, a column defined as `embedding vector(1536)` **cannot** store a `768`-dimension vector without altering the table and rebuilding the HNSW index!

### 2. Technical Implications
Switching `AI_PROVIDER` from OpenAI to Gemini would crash `ai_agent_db` vector queries (`ERROR: expected 1536 dimensions, not 768`) unless we standardize the vector column dimension across providers.

### 3. Proposed Solution (`PROPOSED`)
1. **Tolerant Reader Pattern for All REST & Kafka Consumers**:
   - Configure Jackson (`DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES = false`), `.NET System.Text.Json`, and Python Pydantic consumer models (`extra="ignore"`) to ignore unknown additive fields within the same major version (`.v1`).
   - Renaming or removing a required field, or changing a field's type, is forbidden within `.v1` and requires publishing a `.v2` event type (`Upcasting` / dual-schema transition).
2. **Standardize `pgvector` Embedding Dimension at `768` (`vector(768)`) Across All Providers**:
   - OpenAI `text-embedding-3-small` and `text-embedding-3-large` natively support the `dimensions=768` Matryoshka parameter with near-zero accuracy loss (`>99%` retention).
   - Google Gemini `text-embedding-004` natively outputs `768` dimensions (`output_dimensionality=768`).
   - Local/Voyage/BGE models natively support `768` dimensions.
   - Standardizing `knowledge_chunks.embedding` as `vector(768)` (plus storing `embedding_model VARCHAR(64)` metadata per chunk) cuts `pgvector` HNSW memory footprint in **half** (`50%` RAM savings on our `3.8 GiB` VM) and allows switching between OpenAI and Gemini without schema alterations!

### 4. Alternatives Considered
- Separate `embedding_768` and `embedding_1536` columns in `knowledge_chunks` (doubles index memory overhead).

### 5. Trade-offs
- Re-indexing `knowledge_chunks` is still recommended when changing the underlying embedding model family (since OpenAI and Gemini vector spaces are not cross-comparable), which is handled by an admin CLI/endpoint `POST /api/v1/admin/ai/reindex` (`<5s` for our catalog size).

### 6. User Approval Required?
- **YES** — Approve `CH-06` (Tolerant Reader consumer deserialization + standardized `vector(768)` embedding dimension across OpenAI/Gemini/Anthropic adapters).

---

## Challenge `CH-07` — Distributed Tracing Across Outbox & Deterministic Failure Simulation Safety (`Status: PROPOSED`)

### 1. Problem
1. **Broken Traces at the Outbox Boundary**: When `POST /api/v1/orders` commits a row to `outbox_messages`, the HTTP request span finishes immediately (`~20ms`). `100ms` later, a background `@Scheduled` / `BackgroundService` thread wakes up and polls `outbox_messages`. Because the polling thread is not part of the original HTTP thread, OpenTelemetry by default creates a **brand-new disconnected `trace_id`** for the Kafka send and downstream consumers—breaking end-to-end trace visibility!
2. **Failure Simulation Safety**: In `M4`, `M6`, and `M7`, we need deterministic ways to simulate slow payments, webhook timeouts, DB latency, and memory pressure without leaving dangerous backdoors open in production configurations.

### 2. Technical Implications
Without explicit context extraction from `outbox_messages.headers`, Grafana Tempo will show two disconnected traces instead of one unified Saga trace.

### 3. Proposed Solution (`PROPOSED`)
1. **W3C `traceparent` Extraction in Outbox Relay**:
   - On `INSERT INTO outbox_messages`, serialize the active OpenTelemetry `traceparent` and `tracestate` into `outbox_messages.headers` (`JSONB`).
   - When the Outbox Relay polls a row, it uses OpenTelemetry `TextMapPropagator.extract()` on `row.headers` to set the parent context **before** starting the `kafka.publish` producer span and injects `traceparent` into the Kafka record headers.
2. **Feature-Flagged Fault Injection Contract (`X-Fault-Injection` / Simulator Mode)**:
   - Payment Simulator behaviors (`SUCCEED_IMMEDIATELY`, `SUCCEED_DELAYED_5S`, `FAIL_INSUFFICIENT_FUNDS`, `TIMEOUT_NO_WEBHOOK`, `DUPLICATE_WEBHOOK_3X`) are controlled via an explicit request field (`simulatorMode`) or signed admin test header that is **enabled only when `FAULT_INJECTION_ENABLED=true`** (disabled by default in production Helm values).

### 4. Alternatives Considered
- Relying on log `correlationId` grep alone without linking OpenTelemetry parent-child spans across the Outbox.

### 5. Trade-offs
- Extracting `traceparent` in the Outbox Relay is `~15` lines of code in Java and .NET and yields complete end-to-end waterfall traces in Grafana Tempo.

### 6. User Approval Required?
- **YES** — Approve `CH-07` (Outbox `traceparent` span context extraction + `FAULT_INJECTION_ENABLED` guard on fault simulation hooks).
