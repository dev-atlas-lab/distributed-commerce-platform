# ADR-0004: Hybrid Order Fulfillment Saga (Orchestration for Checkout, Choreography for Side Effects)

- **Status:** `ACCEPTED` (Approved in M0.1)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
Completing an e-commerce order requires coordinating state across four independent services (`Order`, `Inventory`, `Promotion`, `Payment`) and notifying the customer (`Notification`). Using distributed XA/2PC transactions across services is an availability and latency anti-pattern. We must choose between pure Event Choreography, pure Central Orchestration, or a Hybrid Saga approach.

## 2. Options Considered
- **Option A: Pure Event Choreography** (Order emits `OrderCreated` → Inventory emits `StockReserved` → Promotion emits `CouponLocked` → Payment emits `PaymentSucceeded` → Order emits `OrderConfirmed`).
- **Option B: External Workflow Engine (`Temporal` / `Camunda` / `Conductor`)**.
- **Option C: Hybrid Saga — State-Machine Orchestration inside `Order Service` for Core Checkout + Event Choreography for Downstream Notifications/Read-Models**.

## 3. Decision (`ACCEPTED`)
Adopt **Option C**:
1. **`Order Service` acts as the Saga Orchestrator** for the transactional checkout path (`OrderSagaState` persisted in `order_db`). It tracks whether `Inventory` and `Promotion` reservations succeeded before requesting `Payment`, and drives deterministic compensating actions (`ReleaseStock`, `ReleaseCoupon`, or `RefundPayment` on late webhooks) if any step fails or times out.
2. **Downstream non-transactional reactions** (`Notification Service` sending emails, `Product Service` updating search availability badges) subscribe via **Event Choreography** so `Order Service` never needs to know about email delivery or search indexing.

## 4. Consequences & Trade-offs
- **Positive**: Single source of truth (`order_saga_states`) for inspecting why an order is stuck or compensating; avoids cyclic choreography chains across 4 services; requires zero extra workflow-engine containers.
- **Negative / Cost**: `Order Service` must handle timeout sweeps for sagas stuck in `PENDING_RESERVATION` or `AWAITING_PAYMENT`.

## 5. Rejected Alternatives
- **Option A (Pure Choreography)**: When both `Inventory` and `Promotion` must succeed in parallel before payment, or when a late payment arrives after order expiry, choreography degenerates into spiderweb point-to-point error events with no single coordinator.
- **Option B (External Workflow Engine)**: Adds heavy extra infrastructure and hides the Saga state-machine engineering that you want to implement and explain in interviews.
