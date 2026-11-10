# API Contract Index & Governance — Distributed Commerce & Flash Sale Platform

All synchronous REST APIs are specified using **OpenAPI 3.1** before implementation begins.

## 1. Contract Inventory

| Service | Base Route via Gateway | Contract Specification | Status |
| :--- | :--- | :--- | :--- |
| **`customer-service`** (`.NET 10`) | `/api/v1/auth/**`, `/api/v1/customers/**`, `/api/v1/cart/**` | `customer-service.v1.openapi.yaml` (planned M2) | `PROPOSED` |
| **`product-service`** (`Java 21`) | `/api/v1/categories/**`, `/api/v1/products/**` | `product-service.v1.openapi.yaml` (planned M2) | `PROPOSED` |
| **`order-service`** (`Java 21`) | `/api/v1/orders/**` | [`order-and-flashsale.v1.openapi.yaml`](file:///home/anhltn/projects/distributed-commerce-platform/docs/api-contracts/order-and-flashsale.v1.openapi.yaml) | `PROPOSED` |
| **`inventory-service`** (`Java 21`) | `/api/v1/inventory/**` | `inventory-service.v1.openapi.yaml` (planned M3) | `PROPOSED` |
| **`payment-service`** (`Java 21`) | `/api/v1/payments/**` | `payment-service.v1.openapi.yaml` (planned M4) | `PROPOSED` |
| **`promotion-service`** (`.NET 10`) | `/api/v1/promotions/**`, `/api/v1/flash-sales/**` | [`order-and-flashsale.v1.openapi.yaml`](file:///home/anhltn/projects/distributed-commerce-platform/docs/api-contracts/order-and-flashsale.v1.openapi.yaml) | `PROPOSED` |
| **`ai-agent-service`** (`Python 3.12+`) | `/api/v1/ai/**` | `ai-agent-service.v1.openapi.yaml` (planned M5) | `PROPOSED` |

## 2. Mandatory HTTP Header Conventions

| Header Name | Direction | Requirement | Purpose |
| :--- | :--- | :--- | :--- |
| `Authorization` | Request | `Bearer <RS256_JWT>` on protected routes | Carries user `sub`, `roles`, and `jti`. |
| `Idempotency-Key` | Request | Required (`UUIDv4`) on all state-mutating `POST`/`PATCH` calls | Prevents duplicate orders, claims, or payments on network retry. |
| `X-Correlation-Id` / `traceparent` | Both | Generated at Edge Gateway if absent; echoed in responses | Correlates logs, traces, and Kafka events end-to-end. |
