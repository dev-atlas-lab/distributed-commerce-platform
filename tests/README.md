# Test Suites Directory (`tests/`)

This directory organizes cross-cutting and system-level verification suites aligned with [`docs/requirements/ACCEPTANCE_CRITERIA.md`](file:///home/anhltn/projects/distributed-commerce-platform/docs/requirements/ACCEPTANCE_CRITERIA.md):

- [`architecture/`](file:///home/anhltn/projects/distributed-commerce-platform/tests/architecture): Automated architecture boundary and monorepo structure governance tests (`NFR-GOV-001`).
- `integration/`: Testcontainers-backed PostgreSQL, Redis, and Kafka integration tests (`AC-PRO-*`, `AC-ORD-*`, `AC-PAY-*`, `AC-OUT-*` — implemented starting in `M1+`).
- `contract/`: OpenAPI 3.1 and JSON Schema event envelope contract verification suites.
- `performance/`: `k6` load testing scripts for Catalog FTS, `pgvector` hybrid search, and Flash Sale concurrency (`NFR-PERF-001`..`004` — benchmarked in `M10`).
- `security/`: OIDC/OAuth2 JWT token-type, audience, principal-type separation, and PostgreSQL least-privilege role verification suites (`NFR-SEC-001`..`005`).
