# ADR Index — Distributed Commerce & Flash Sale Platform

All significant architectural decisions for `dev-atlas-lab/distributed-commerce-platform` are recorded in this directory.

| ADR ID | Title | Status | Milestone |
| :--- | :--- | :--- | :--- |
| [ADR-0001](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0001-polyglot-microservices-and-service-boundaries.md) | Polyglot Microservices Topology & Pragmatic Internal Architecture | `PROPOSED` | M0 |
| [ADR-0002](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0002-database-per-service-on-shared-postgres-instance.md) | Database-per-Service Isolation on a Consolidated PostgreSQL Instance | `PROPOSED` | M0 |
| [ADR-0003](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0003-transactional-outbox-and-inbox-idempotency.md) | Transactional Outbox Polling Relay & Idempotent Consumer Inbox | `PROPOSED` | M0 |
| [ADR-0004](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0004-hybrid-order-fulfillment-saga-orchestration.md) | Hybrid Order Fulfillment Saga (Orchestration for Checkout, Choreography for Side Effects) | `PROPOSED` | M0 |
| [ADR-0005](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md) | Flash Sale Concurrency Architecture (Redis Lua Atomic Gate + 3-Tier Locking Strategy) | `PROPOSED` | M0 |
| [ADR-0006](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md) | `.NET 10` YARP API Gateway & Standards-Based `RS256` JWT/JWKS Authentication | `PROPOSED` | M0 |
| [ADR-0007](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0007-catalog-search-postgresql-fts-vs-opensearch.md) | Phased Product Catalog Search: PostgreSQL 17 FTS + `pg_trgm` before OpenSearch | `PROPOSED` | M0 |
| [ADR-0008](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md) | Zero-Privilege AI Agent Boundary, JWT-Bound Tool Calling & `pgvector` RAG | `PROPOSED` | M0 |
| [ADR-0009](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md) | On-Prem Multi-VM Kubernetes Strategy (`K3s` vs. `kubeadm`), MetalLB & Storage | `PROPOSED` | M0 |
| [ADR-0010](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0010-event-contracts-json-schema-and-kafka-kraft.md) | Apache Kafka KRaft Mode & Monorepo JSON Schema Event Contracts | `PROPOSED` | M0 |
