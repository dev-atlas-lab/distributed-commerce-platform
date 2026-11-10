# Governance & Collaboration Rule — Distributed Commerce & Flash Sale Platform

- **Trigger:** `always_on`
- **Scope:** Entire repository (`distributed-commerce-platform`)

## 1. Human Decision & Implementation Primacy
- The **Human Engineer** makes all final architectural decisions and personally implements business features.
- Do NOT implement complete business features unless the Human Engineer explicitly asks you to.
- Do NOT transition any task or ADR to `ACCEPTED` or `DONE` without explicit Human approval.
- Actively challenge architectural flaws, race conditions, security gaps, shared-database shortcuts, or premature optimizations.

## 2. Hard Architecture Invariants
1. **Strict Database per Service**: Never query, join, or share database credentials across service boundaries.
2. **At-Least-Once + Idempotency**: Always pair Transactional Outbox (`outbox_messages`) with Idempotent Consumer (`inbox_messages` + natural unique keys). Never claim Kafka transactions provide end-to-end business exactly-once processing across external databases.
3. **Zero-Privilege AI Boundary**: `services/python/ai-agent-service` must never access service databases, Redis caches, or Kafka brokers directly. All tool calls must route through authenticated APIs with the caller's verified JWT (`sub` bound from token context, never from LLM arguments).
4. **Honest Capacity & HA Reporting**: Never fabricate `k6` benchmark numbers or claim High Availability without testing failure scenarios and documenting single points of failure.
