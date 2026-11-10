# ADR-0004: Hybrid Order Fulfillment Saga & Decoupled Order vs. Payment Lifecycles

- **Status:** `ACCEPTED` (Hybrid Saga Accepted in `M0.1`; `CH-02` Decoupled Order/Payment State Machines `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Completing an e-commerce order coordinates state across `Order`, `Inventory`, `Promotion`, `Payment`, and `Notification`. Furthermore, external payment gateways are asynchronous: webhooks can arrive duplicated, out of order (`captured` before `authorized`), or **late** (after the Order's 10-minute inventory reservation has already expired and been released). Wall-clock buffers (such as a 2-second cutoff) cannot guarantee correctness against arbitrary network delays.

## 2. Options Considered
- **Option A**: Pure Event Choreography + single entangled Order/Payment status enum.
- **Option B**: External Workflow Engine (`Temporal` / `Camunda`).
- **Option C**: **Hybrid Saga (`Order Service` Orchestrator for Checkout + Choreography for Notifications/Read-Models) with Strictly Separated `Order` and `Payment` State Machines (`CH-02`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `Order Service` acts as the Saga Orchestrator for the transactional checkout path (`order_saga_states`), while `Notification Service` and catalog search projections subscribe via Event Choreography.
2. **Refined Order & Payment Lifecycle Separation (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-02`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Order Lifecycle (`order_db`)** governs commercial fulfillment and inventory reservation (`PENDING_RESERVATION -> AWAITING_PAYMENT -> CONFIRMED -> FULFILLED`, with terminal `EXPIRED / CANCELLED -> *_REFUNDING -> *_REFUNDED`). Once an Order is `EXPIRED` or `CANCELLED`, it can **never** transition to `CONFIRMED`.
   - **Payment Lifecycle (`payment_db`)** governs financial movement (`PaymentIntent` with `1..N` `PaymentAttempt`s supporting both Two-Step `INITIATED -> AUTHORIZED -> CAPTURED / VOIDED` and One-Step `INITIATED -> CAPTURED -> REFUNDED`).
   - **Monotonic Webhook Precedence**: Webhooks are deduplicated via `payment_webhook_logs (webhook_event_id PK)` and evaluated by monotonic state rank (`CAPTURED(30) > AUTHORIZED(20) > INITIATED(10)`) so out-of-order webhooks never regress state.
   - **Late Payment Deterministic Compensation**: If `PaymentAuthorized` arrives after `Order` is `EXPIRED`, `Order Service` issues `VoidPaymentCommand`. If `PaymentCaptured` arrives after `Order` is `EXPIRED`, `Order Service` transitions to `EXPIRED_REFUNDING` and issues `RefundPaymentCommand`.

## 4. Consequences & Trade-offs
- **Positive**: Eliminates reliance on fragile wall-clock buffers; prevents both overselling and unrefunded customer charges under arbitrary webhook delays.
- **Negative / Cost**: Requires maintaining explicit `VOID` and `REFUND` compensation commands and a 5-minute reconciliation safety sweep.

## 5. Rejected Alternatives
- **2-Second Pre-Capture Buffer as a Correctness Mechanism (`M0.1` draft)**: Rejected in `M0.2` because network partitions, GC pauses, or delayed webhooks can exceed any fixed clock buffer.
