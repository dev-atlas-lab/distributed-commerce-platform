# ADR-0004: Hybrid Order Fulfillment Saga & Decoupled Order vs. Payment Transition Matrices

- **Status:** `ACCEPTED` (Hybrid Saga Accepted in `M0.1`; `CH-02` Explicit State Transition Matrices `PROPOSED` in `M0.2.1`)
- **Date:** 2026-11-10
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
   - **Recorded Fact Timestamps**: `payment_attempts` records `authorized_at`, `captured_at`, `voided_at`, `refunded_at`, and `failed_at` alongside `status`.
   - **Out-of-Order Webhook Resolution**: If `payment.captured` arrives while `INITIATED`, the attempt transitions `INITIATED -> CAPTURED` (setting both `authorized_at` and `captured_at`) and emits `PaymentCaptured` in the same local transaction. When the delayed `payment.authorized` webhook arrives while `status == CAPTURED`, the explicit `(CAPTURED, ON_WEBHOOK_AUTHORIZED)` rule records `authorized_at` if needed and performs an idempotent `NOOP` with zero duplicate Outbox events.
   - **Branch Conflict & Late Capture Protection**:
     - Once `Order` is `EXPIRED` or `CANCELLED`, it never transitions to `CONFIRMED`.
     - Late `PaymentAuthorized` on an `EXPIRED` order triggers `VoidPaymentCommand` (`AUTHORIZED -> VOID_PENDING -> VOIDED`).
     - Late `PaymentCaptured` on an `EXPIRED` order (or a gateway race where `payment.captured` arrives on a `VOID_PENDING`/`VOIDED` attempt) transitions the attempt to `REFUND_PENDING -> REFUNDED` and the order to `EXPIRED_REFUNDING -> EXPIRED_REFUNDED`.

## 4. Consequences & Trade-offs
- **Positive**: Accurately models mutually exclusive `CAPTURE` vs. `VOID` branches; handles out-of-order and late webhooks deterministically without scalar rank bugs or clock buffers.
- **Negative / Cost**: Requires maintaining explicit transition tables and fact timestamp columns in `payment_attempts`.

## 5. Rejected Alternatives
- **Option B (Scalar numeric ranks)**: Rejected in `M0.2.1` because `VOIDED` and `CAPTURED` are mutually exclusive sibling branches, not linear steps.
