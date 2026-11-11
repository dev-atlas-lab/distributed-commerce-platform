# ADR-0004: Hybrid Order Fulfillment Saga & Decoupled Order vs. Payment Transition Matrices

- **Status:** `DESIGN_ACCEPTED` (Hybrid Saga Accepted in `M0.1`; `CH-02` Explicit State Transition Matrices Frozen as `DESIGN_ACCEPTED` in `M0.3`)
- **Date:** 2026-04-11
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Completing an e-commerce order coordinates state across `Order`, `Inventory`, `Promotion`, `Payment`, and `Notification`. External payment webhooks can arrive duplicated, out of order (`captured` before `authorized`), or late (after the Order's inventory reservation has expired). Furthermore, **payment states form a branching DAG (`AUTHORIZED -> CAPTURED` vs. `AUTHORIZED -> VOIDED`), NOT a single scalar numeric hierarchy**.

## 2. Options Considered
- **Option A**: Entangled Order/Payment status + 2-second clock buffer.
- **Option B**: Scalar numeric state ranks (`10..100` — `M0.2` draft).
- **Option C**: **Hybrid Saga (`Order Service` Orchestrator) + Orthogonal `Order` and `PaymentAttempt` State Machines Governed by Explicit Transition Matrices & Recorded Fact Timestamps (`CH-02`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `Order Service` orchestrates the transactional checkout Saga (`order_saga_states`), while `Notification Service` and search read-models subscribe via Event Choreography.
2. **Refined `M0.2.1` Order & Payment State Machines (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-02`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **No Scalar Ranks**: State changes are validated strictly against explicit `(CurrentState, CommandOrWebhookEvent) -> NextState` transition tables.
   - **Provider-Reported Fact Timestamps (Never Fabricated)**: `payment_attempts` records `provider_authorized_at`, `provider_captured_at`, `provider_voided_at`, `provider_refunded_at`, and `provider_failed_at` strictly when reported by the provider. A direct `payment.captured` event sets **only** `provider_captured_at` (`provider_authorized_at` remains `NULL` unless an actual `payment.authorized` event arrives).
   - **Out-of-Order & Duplicate Webhook Resolution**: Webhooks are deduplicated via `payment_webhook_logs (provider_event_id PK)` inside the same local DB transaction as the `PaymentAttempt` update and Outbox insert. When a delayed `payment.authorized` webhook arrives while `status == CAPTURED`, the explicit `(CAPTURED, ON_WEBHOOK_AUTHORIZED)` rule records `provider_authorized_at` and performs an idempotent `NOOP` with zero duplicate Outbox events.
   - **Branch Conflict & Late Capture Idempotent Auto-Refund**:
     - Once `Order` is `EXPIRED` or `CANCELLED`, it never transitions to `CONFIRMED`.
     - Late `PaymentAuthorized` on an `EXPIRED` order triggers `VoidPaymentCommand` (`AUTHORIZED -> VOID_PENDING -> VOIDED`).
     - Late `PaymentCaptured` on an `EXPIRED` order (or a gateway race where `payment.captured` arrives on a `VOID_PENDING`/`VOIDED` attempt) inserts an idempotent row in `refund_requests (UNIQUE (attempt_id, reason_code))` and transitions the attempt to `REFUND_PENDING -> REFUNDED`.

## 4. Consequences & Trade-offs
- **Positive**: Accurately models mutually exclusive `CAPTURE` vs. `VOID` branches; handles out-of-order and late webhooks deterministically without scalar rank bugs or clock buffers.
- **Negative / Cost**: Requires maintaining explicit transition tables and fact timestamp columns in `payment_attempts`.

## 5. Rejected Alternatives
- **Option B (Scalar numeric ranks)**: Rejected in `M0.2.1` because `VOIDED` and `CAPTURED` are mutually exclusive sibling branches, not linear steps.
