# Distributed Commerce & Flash Sale Platform

[![Status: M0 Proposed](https://img.shields.io/badge/Milestone-M0_Architecture_In_Review-blue)](#)
[![Java 21](https://img.shields.io/badge/Java-21_LTS_%7C_Spring_Boot_3.4-orange)](#)
[![.NET 10](https://img.shields.io/badge/.NET-10_LTS_%7C_ASP.NET_Core-purple)](#)
[![Python 3.12+](https://img.shields.io/badge/Python-3.12%2B_%7C_FastAPI_AI_Agent-green)](#)
[![React 19](https://img.shields.io/badge/Frontend-React_19_%7C_TypeScript-61DAFB)](#)
[![Kubernetes](https://img.shields.io/badge/Infra-Kafka_%7C_Redis_%7C_PostgreSQL_%7C_K8s-326CE5)](#)

A production-oriented polyglot distributed e-commerce and high-concurrency **Flash Sale** platform built under [**dev-atlas-lab**](https://github.com/dev-atlas-lab) to master microservices architecture, distributed consistency (Saga, Transactional Outbox/Inbox, Redis Lua atomic concurrency), agentic AI security, on-prem multi-VM Kubernetes operations, and empirical performance engineering (`k6`).

---

## 1. Architecture At a Glance

| Service | Language & Runtime | Core Responsibility | Database / State Store |
| :--- | :--- | :--- | :--- |
| **`api-gateway`** | `.NET 10` (`YARP`) | Edge routing, `RS256` JWT validation, Redis rate limiting, correlation IDs | `Redis 7.4` |
| **`product-service`** | `Java 21` (`Spring Boot 3`) | Categories, SPU/SKU catalog, MinIO pre-signed media, PG 17 FTS & faceted search | `product_db` (`PostgreSQL 17`), `Redis`, `MinIO` |
| **`customer-service`** | `.NET 10` (`ASP.NET Core`) | Registration, `RS256` JWT + JWKS issuer, profiles, addresses, shopping cart | `customer_db` (`PostgreSQL 17`), `Redis` |
| **`order-service`** | `Java 21` (`Spring Boot 3`) | Order lifecycle, idempotency, and **Order Fulfillment Saga Orchestrator** | `order_db` (`PostgreSQL 17`) |
| **`inventory-service`** | `Java 21` (`Spring Boot 3`) | SKU stock ledger, conditional atomic reservations, expiration sweeper | `inventory_db` (`PostgreSQL 17`), `Redis` |
| **`payment-service`** | `Java 21` (`Spring Boot 3`) | Payment Simulator, HMAC webhooks, timeout sweeps, refunds & reconciliation | `payment_db` (`PostgreSQL 17`) |
| **`promotion-service`** | `.NET 10` (`ASP.NET Core`) | Coupon engine & **Flash Sale Campaign Engine (Redis Lua Atomic Gate)** | `promotion_db` (`PostgreSQL 17`), `Redis` |
| **`notification-service`** | `.NET 10` (`Worker`) | Async Kafka consumer, email dispatch (`Mailpit`), non-blocking retry & DLQ | `notification_db` (`PostgreSQL 17`) |
| **`ai-agent-service`** | `Python 3.12+` (`FastAPI`) | Customer Shopping Assistant & Admin Ops Assistant, `pgvector` RAG, guardrails | `ai_agent_db` (`PostgreSQL 17 + pgvector`) |
| **`frontend`** | `React 19` (`TypeScript`) | Customer Storefront SPA (including Flash Sale Live Arena) + Admin/Ops Portal | Browser / REST + SSE |

---

## 2. Core Engineering Documentation (`Milestone M0`)

- **Governance & Constitution**: [`PROJECT_CONSTITUTION.md`](file:///home/anhltn/projects/distributed-commerce-platform/PROJECT_CONSTITUTION.md) | [`AGENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/AGENTS.md)
- **Master Technical Specification**: [`SPEC.md`](file:///home/anhltn/projects/distributed-commerce-platform/SPEC.md)
- **M0.2.2 Adversarial Architecture Verification Report**: [`M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md`](file:///home/anhltn/projects/distributed-commerce-platform/M0_2_2_ARCHITECTURE_VERIFICATION_REPORT.md)
- **Product Requirements (PRD)**: [`docs/product/PRODUCT_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/product/PRODUCT_REQUIREMENTS.md)
- **Domain-Driven Design Model**: [`docs/domain/DOMAIN_MODEL.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/domain/DOMAIN_MODEL.md)
- **System Architecture & 21 Pattern Evaluations**: [`docs/architecture/SYSTEM_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/SYSTEM_ARCHITECTURE.md)
- **Deep Architecture Challenge (`M0.1` Edge Cases `CH-01`–`CH-07`)**: [`docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md)
- **Service Boundaries & Responsibility Matrix**: [`docs/architecture/SERVICE_BOUNDARIES.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/SERVICE_BOUNDARIES.md)
- **Data Architecture & Locking Strategy**: [`docs/architecture/DATA_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DATA_ARCHITECTURE.md)
- **Event-Driven Architecture, Outbox/Inbox & Sagas**: [`docs/architecture/EVENT_DRIVEN_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/EVENT_DRIVEN_ARCHITECTURE.md)
- **AI Agentic Architecture & Security Boundary**: [`docs/architecture/AI_AGENT_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/AI_AGENT_ARCHITECTURE.md)
- **Security Architecture**: [`docs/security/SECURITY_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/security/SECURITY_ARCHITECTURE.md)
- **On-Prem Kubernetes & Infrastructure Strategy**: [`docs/infrastructure/INFRASTRUCTURE_AND_KUBERNETES_STRATEGY.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/infrastructure/INFRASTRUCTURE_AND_KUBERNETES_STRATEGY.md) | [`docs/architecture/DEPLOYMENT_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DEPLOYMENT_ARCHITECTURE.md)
- **Performance Engineering Strategy (`k6`)**: [`docs/performance/PERFORMANCE_STRATEGY.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/performance/PERFORMANCE_STRATEGY.md)
- **Test Strategy**: [`docs/architecture/TEST_STRATEGY.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/TEST_STRATEGY.md)
- **Roadmap & Backlog**: [`docs/roadmap/MILESTONE_ROADMAP.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/roadmap/MILESTONE_ROADMAP.md) | [`ENGINEERING_ROADMAP.md`](file:///home/anhltn/projects/distributed-commerce-platform/ENGINEERING_ROADMAP.md) | [`BACKLOG.md`](file:///home/anhltn/projects/distributed-commerce-platform/BACKLOG.md)
- **Architecture Decision Records (ADRs)**: [`docs/adr/README.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/README.md) (`ADR-0001` – `ADR-0011`)
- **API & Event Contracts**: [`docs/api-contracts/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/api-contracts/) | [`docs/event-contracts/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/event-contracts/)
