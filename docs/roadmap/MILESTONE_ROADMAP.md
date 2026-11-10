# Milestone Roadmap & Execution Gates (`M0` – `M7`) — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-RDM-002`
- **Status:** `ACCEPTED` (`M0.1` Decisions Locked; Awaiting Final Gate Approval for `M1`)
- **Primary Reference:** [`ENGINEERING_ROADMAP.md`](file:///home/anhltn/projects/distributed-commerce-platform/ENGINEERING_ROADMAP.md) & [`BACKLOG.md`](file:///home/anhltn/projects/distributed-commerce-platform/BACKLOG.md)
- **Last Updated:** 2026-11-10

---

## 1. Approved Architecture Baseline (`M0.1`)

All 7 foundational architectural questions from `M0` have been answered and locked by the Human Architect:

| Decision ID | Topic | Approved Decision (`Status: ACCEPTED`) | Governing ADR |
| :--- | :--- | :--- | :--- |
| **Q1** | GitHub Repository & Workspace | Private repository `dev-atlas-lab/distributed-commerce-platform` created, connected to `/home/anhltn/projects/distributed-commerce-platform/`, and synced on `main`. | [`REPOSITORY_BOOTSTRAP_REPORT.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/reports/REPOSITORY_BOOTSTRAP_REPORT.md) |
| **Q2** | Target VM Hardware Topology | 3–4 additional Linux VMs (`2 vCPUs`, `~3.8 GiB RAM` each, `aarch64`/`x86_64`) can be provisioned alongside the current VM (`4–5 VMs total`). | [`ADR-0009`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md) |
| **Q3** | Kubernetes Distribution | Start with **`K3s`** (`--disable traefik --disable servicelb` + standard `MetalLB` + `Ingress-NGINX`) and maintain 100% manifest compatibility to migrate to **`kubeadm`** later. | [`ADR-0009`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0009-on-prem-kubernetes-k3s-vs-kubeadm-and-storage.md) |
| **Q4** | Flash Sale Unpaid Reservation Expiry | **Option A**: Expired reservations return stock to the active Redis Flash Sale campaign pool (if campaign is still `ACTIVE`), guarded by idempotent claim-release tracking and a 30s Redis-to-PostgreSQL reconciliation worker. | [`ADR-0005`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0005-flash-sale-concurrency-and-three-tier-locking.md) |
| **Q5** | Identity & OIDC Architecture | Design **standards-compliant OIDC Discovery (`/.well-known/openid-configuration`, `/.well-known/jwks.json`) + `RS256` JWT** from Day 1 in `customer-service`, enabling zero-code-change migration to **Keycloak** later. | [`ADR-0006`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0006-api-gateway-yarp-and-oidc-jwt-security.md) |
| **Q6** | Product Catalog Search | Start with **PostgreSQL 17 Full-Text Search (`tsvector` + `pg_trgm` + `JSONB` GIN)** behind a `ProductSearchRepository` port, and benchmark with `k6` before considering **OpenSearch**. | [`ADR-0007`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0007-catalog-search-postgresql-fts-vs-opensearch.md) |
| **Q7** | AI Provider Integration | Implement a **Multi-Provider AI Abstraction Port** supporting **OpenAI**, **Google Gemini**, and **Anthropic Claude** behind a strict zero-privilege API-only tool boundary. | [`ADR-0008`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/ADR-0008-ai-agent-security-boundary-and-pgvector-rag.md) |

---

## 2. Milestone Summary & Gate Status

| Milestone | Title | Key Deliverables | Gate Status |
| :--- | :--- | :--- | :--- |
| **M0 / M0.1** | **Product Discovery, Architecture & Deep Challenge Review** | PRD, DDD Domain Model, C4 Diagrams, 21 Pattern Evaluations, 11 ADRs (`ADR-0001`–`ADR-0011`), OpenAPI & Event Schemas, Phase 4 Deep Architecture Challenge (`CH-01`–`CH-07`). | **`IN REVIEW` (Current Gate)** |
| **M1** | **Foundation & Polyglot Scaffolding** | Toolchain setup (`DCP-M1-001`), Docker Compose infra (`DCP-M1-002`), Java 21 skeletons (`DCP-M1-003`), .NET 10 skeletons (`DCP-M1-004`), Python 3.12 AI skeleton (`DCP-M1-005`), React 19 shell (`DCP-M1-006`), GitHub Actions CI (`DCP-M1-007`). | `PROPOSED` (Starts after M0.1 approval) |
| **M2** | **Core Commerce (Sync Baseline & Dual UI)** | OIDC Auth & Cart (`customer-service`), Catalog & PG FTS (`product-service`), Baseline Order (`order-service`), YARP Gateway, Storefront & Admin UI. | `PROPOSED` |
| **M3** | **Distributed Systems Core** | `inventory-service` ledger & atomic SQL reservation, Transactional Outbox + Inbox, Order Fulfillment Saga Orchestrator, `notification-service` retry + DLQ. | `PROPOSED` |
| **M4** | **Advanced Commerce & Flash Sale** | `payment-service` simulator & webhooks, `promotion-service` coupons & Flash Sale Redis Lua Gate + Option A expiry return + 30s reconciliation, Storefront Flash Sale Arena. | `PROPOSED` |
| **M5** | **AI Agentic Assistant** | Multi-provider (`OpenAI`/`Gemini`/`Anthropic`) Shopping & Ops Assistants, `pgvector` RAG, JWT-bound tools, HITL approvals, 50-case Eval Suite. | `PROPOSED` |
| **M6** | **On-Prem Multi-VM Kubernetes & GitOps** | 4–5 VM `K3s` cluster (portable to `kubeadm`), MetalLB, Ingress-NGINX, NetworkPolicies, Helm, Argo CD, OpenTelemetry + LGTM Observability. | `PROPOSED` |
| **M7** | **Performance Engineering & Chaos** | 7-suite `k6` load/spike/soak/breakpoint tests, JVM/.NET/PG profiling, before/after optimization reports, 10 reproducible failure scenarios (`FAIL-01`–`FAIL-10`). | `PROPOSED` |
