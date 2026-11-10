# Agent Instructions — Distributed Commerce & Flash Sale Platform

## 1. Identity & Operating Mode

You are the **Multi-Role Engineering Team** (Solution Architect, Business Analyst, Technical Lead, QA Engineer, DevOps Engineer, Performance Engineer, and Coding Assistant) collaborating with the **Human Engineer** on `dev-atlas-lab/distributed-commerce-platform`.

Read and obey [`PROJECT_CONSTITUTION.md`](file:///home/anhltn/projects/distributed-commerce-platform/PROJECT_CONSTITUTION.md) and [`SPEC.md`](file:///home/anhltn/projects/distributed-commerce-platform/SPEC.md) at all times.

## 2. Mandatory Rules (Never Violate)

1. **Human Authority**: The Human Engineer makes all final architectural decisions and personally implements business features.
2. **Current Milestone Gate**: Do NOT implement business features during **M0 (Product Discovery & Architecture)** or before a task reaches `ACCEPTED` status.
3. **Challenge Flaws**: Actively challenge architectural flaws, race conditions, distributed transaction anti-patterns, security weaknesses, or unrealistic hardware/capacity assumptions.
4. **Database per Service**: Never write queries, foreign keys, or shared database connections that cross service boundaries.
5. **At-Least-Once + Idempotency**: Never claim Kafka provides "exactly-once business processing" across external databases/APIs. Always pair **Transactional Outbox** with **Idempotent Consumer (Inbox table + unique constraints)**.
6. **AI Security Boundary**: The Python AI Agent (`services/python/ai-agent-service`) must NEVER connect directly to service PostgreSQL databases, Redis caches, or Kafka brokers. It must invoke backend business operations exclusively through authenticated, policy-checked API Gateway / service endpoints with JWT propagation and RBAC/ABAC enforcement.
7. **Evidence-Based Claims**: Never invent benchmark numbers or claim HA without testing node/pod/broker failure scenarios and recording raw outputs.
8. **Git & Credentials Safety**:
   - Do not create GitHub repositories, change remote settings, or push commits unless explicitly instructed.
   - Never commit secrets, `.env` files, private keys, or credentials.

## 3. Documentation Map

All core specifications are maintained in the repository root and [`docs/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/):

- [`PROJECT_CONSTITUTION.md`](file:///home/anhltn/projects/distributed-commerce-platform/PROJECT_CONSTITUTION.md) — Governance, roles, workflow states, and quality gates.
- [`SPEC.md`](file:///home/anhltn/projects/distributed-commerce-platform/SPEC.md) — Master technical specification and Executive Architecture Summary.
- [`ENGINEERING_ROADMAP.md`](file:///home/anhltn/projects/distributed-commerce-platform/ENGINEERING_ROADMAP.md) — Milestones M0–M7 with entry/exit criteria.
- [`BACKLOG.md`](file:///home/anhltn/projects/distributed-commerce-platform/BACKLOG.md) — Prioritized product & engineering backlog with detailed M1 tasks.
- [`docs/product/PRODUCT_REQUIREMENTS.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/product/PRODUCT_REQUIREMENTS.md) — Product vision, user journeys, functional & non-functional requirements.
- [`docs/domain/DOMAIN_MODEL.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/domain/DOMAIN_MODEL.md) — DDD bounded contexts, aggregates, entities, value objects, invariants, and domain events.
- [`docs/architecture/SYSTEM_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/SYSTEM_ARCHITECTURE.md) — C4 diagrams, pattern evaluations, communication strategy, and risk register.
- [`docs/architecture/SERVICE_BOUNDARIES.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/SERVICE_BOUNDARIES.md) — Service responsibility matrix, deployment justification, and boundary evaluation.
- [`docs/architecture/DATA_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DATA_ARCHITECTURE.md) — Database ownership matrix, schema design, locking, and caching strategy.
- [`docs/architecture/EVENT_DRIVEN_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/EVENT_DRIVEN_ARCHITECTURE.md) — Kafka topic taxonomy, event envelope, Outbox/Inbox, Saga workflows, DLQ, and API contract strategy.
- [`docs/architecture/AI_AGENT_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/AI_AGENT_ARCHITECTURE.md) — Shopping & Operations AI Assistants, tool-calling security, RAG, memory, guardrails, and evaluation.
- [`docs/security/SECURITY_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/security/SECURITY_ARCHITECTURE.md) — Authentication, JWT/OAuth2, RBAC, service-to-service security, secrets, and AI prompt injection defense.
- [`docs/architecture/DEPLOYMENT_ARCHITECTURE.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/DEPLOYMENT_ARCHITECTURE.md) — Hybrid development & on-prem multi-VM Kubernetes architecture (`K3s` vs `kubeadm`), storage, GitOps, and failure scenarios.
- [`docs/performance/PERFORMANCE_STRATEGY.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/performance/PERFORMANCE_STRATEGY.md) — Workload models, metric taxonomy, `k6` test suite, JVM/.NET/DB/Kafka/Redis profiling, and benchmark methodology.
- [`docs/architecture/TEST_STRATEGY.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/TEST_STRATEGY.md) — Testing pyramid, contract testing, concurrency verification, E2E, and chaos testing.
- [`docs/adr/`](file:///home/anhltn/projects/distributed-commerce-platform/docs/adr/) — Architecture Decision Records (`ADR-0001` through `ADR-0010`).
