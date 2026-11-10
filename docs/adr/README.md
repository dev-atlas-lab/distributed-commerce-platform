# ADR Index — Distributed Commerce & Flash Sale Platform

All significant architectural decisions for `dev-atlas-lab/distributed-commerce-platform` are recorded in this directory.

| ADR ID | Title | Domain | Status | Milestone |
| :--- | :--- | :--- | :--- | :--- |
| [ADR-0001](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0001-polyglot-microservices-and-service-boundaries.md) | Polyglot Microservices Topology & Pragmatic Internal Architecture | Service Boundaries | `ACCEPTED` | M0.1 |
| [ADR-0002](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0002-database-per-service-on-shared-postgres-instance.md) | Database-per-Service Isolation on a Consolidated PostgreSQL Instance | Data Architecture | `ACCEPTED` | M0.1 |
| [ADR-0003](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0003-transactional-outbox-and-inbox-idempotency.md) | Transactional Outbox Polling Relay & Idempotent Consumer Inbox | Event Delivery | `ACCEPTED` | M0.1 |
| [ADR-0004](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0004-hybrid-order-fulfillment-saga-orchestration.md) | Hybrid Order Fulfillment Saga (Orchestration for Checkout, Choreography for Side Effects) | Distributed Transactions | `ACCEPTED` | M0.1 |
| [ADR-0005](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md) | Flash Sale Concurrency Architecture, Reservation Expiration & 3-Tier Locking Strategy | Reservation & Inventory Consistency | `ACCEPTED` | M0.1 |
| [ADR-0006](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md) | `.NET 10` YARP API Gateway & Standards-Compliant OIDC/JWT Architecture (Keycloak-Ready) | OIDC & Identity Architecture | `ACCEPTED` | M0.1 |
| [ADR-0007](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0007-catalog-search-postgresql-fts-vs-opensearch.md) | Phased Product Catalog Search: PostgreSQL 17 FTS + `pg_trgm` Benchmark Gate before OpenSearch | Search Strategy | `ACCEPTED` | M0.1 |
| [ADR-0008](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md) | Multi-Provider AI Abstraction (`OpenAI` / `Gemini` / `Anthropic`), Zero-Privilege Boundary & `pgvector` RAG | AI Provider Abstraction & Security | `ACCEPTED` | M0.1 |
| [ADR-0009](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md) | On-Prem Multi-VM Kubernetes Strategy (`K3s` First on 4–5 VMs, `kubeadm` Migration Path), MetalLB & Storage | Infrastructure & Kubernetes Strategy | `ACCEPTED` | M0.1 |
| [ADR-0010](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0010-event-contracts-json-schema-and-kafka-kraft.md) | Service Communication, OpenAPI 3.1 REST & Kafka KRaft JSON Schema Event Contracts | Service Communication & Contracts | `ACCEPTED` | M0.1 |
| [ADR-0011](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0011-observability-opentelemetry-and-lgtm-stack.md) | Unified OpenTelemetry & LGTM Observability Architecture (`Metrics`, `Logs`, `Traces`) | Observability Architecture | `ACCEPTED` | M0.1 |
