# Security Architecture — Distributed Commerce & Flash Sale Platform

- **Document ID:** `DCP-DOC-SEC-001`
- **Status:** `PROPOSED` (Milestone M0 — Pending Human Approval)
- **Last Updated:** 2026-11-10

---

## 1. Security Design Principles

1. **Defense in Depth**: Edge verification at `.NET YARP API Gateway` + resource-level authorization inside each downstream `Java`, `.NET`, and `Python` service.
2. **Least Privilege everywhere**: Every database user, service account, and AI Agent tool operates with the minimum required permissions.
3. **Zero Trust on Client Inputs**: Never trust client-supplied prices, discounts, user IDs, or role headers (`X-User-Id` from external clients is stripped at the Gateway).
4. **Zero Plaintext Secrets in Git**: All credentials, signing keys, and API tokens are injected via environment variables / Kubernetes Secrets managed via `SOPS` or `External Secrets`.

---

## 2. Authentication & Identity Strategy (`Customer Service` JWT vs. `Keycloak`)

### 2.1 Architectural Evaluation
We evaluate two options for Identity Provider (IdP) (recorded in `ADR-0006`):
- **Option A (Recommended for M2–M5 Baseline): Standards-Compliant OAuth2/OIDC JWT Issued by `Customer Service` (`RS256` Asymmetric Key Pair + JWKS Endpoint `/.well-known/jwks.json`)**:
  - **Why**: Lets you personally implement and master secure authentication mechanics (`Argon2id` password hashing, short-lived `15m` `RS256` Access Tokens, rotating `7d` Refresh Tokens with reuse detection in PostgreSQL + Redis JTI revocation list) without spending `~1 GiB` RAM on a dedicated Keycloak JVM container during early milestones.
  - Because all downstream services (`Java Spring Security OAuth2 Resource Server`, `.NET JwtBearer`, `Python FastAPI`) validate tokens via standard `/.well-known/jwks.json`, migrating to or adding **Keycloak** in `M6` requires changing **only the `ISSUER_URI` / `JWKS_URI` configuration**—zero application code rewrite!
- **Option B: Deploy Keycloak Container Immediately in M2**:
  - Adds enterprise IdP features (federation, admin UI) immediately, at the cost of `+700–1024 MiB` container RAM and hiding auth implementation internals behind a third-party product.

### 2.2 Token Structure & Claims
```json
{
  "iss": "https://auth.commerce.dev-atlas.lab",
  "sub": "9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d",
  "aud": ["commerce-api"],
  "roles": ["CUSTOMER"],
  "jti": "019316b0-1122-7000-9abc-def012345678",
  "iat": 1794325500,
  "exp": 1794326400
}
```

---

## 3. Role-Based & Resource-Based Access Control (RBAC + ABAC)

| Role | Allowed Capabilities | Explicitly Denied |
| :--- | :--- | :--- |
| `ANONYMOUS` | Browse/search products, view active Flash Sales & public coupons, register/login. | Placing orders, claiming Flash Sales, accessing AI Assistant, viewing orders. |
| `CUSTOMER` | Manage own profile/addresses/cart, place orders, claim Flash Sales, pay for own orders, query own orders, use Shopping AI Assistant. | Viewing/modifying any other customer's orders/cart (`IDOR`), accessing Admin endpoints or Operations AI Assistant. |
| `ADMIN_MERCHANT` | Create/update products, SKUs, categories, coupon campaigns, and schedule Flash Sale campaigns. | Modifying historical financial ledgers, bypassing inventory ledger audit trail. |
| `ADMIN_OPS` | View system-wide order/payment/inventory diagnostics, inspect/replay DLQ messages, approve HITL reconciliation actions, use Operations AI Assistant. | Impersonating customer checkout or modifying customer passwords directly. |

### 3.1 Preventing Broken Object Level Authorization (BOLA / IDOR)
Every customer-facing query or mutation (`GET /api/v1/orders/{orderId}`, `POST /api/v1/orders/{orderId}/cancel`, `POST /api/v1/payments/{orderId}/confirm`) MUST enforce in the domain/application query:
```sql
WHERE order_id = :orderId AND customer_id = :authenticatedJwtSub
```
If a customer requests another user's `orderId`, return `404 Not Found` (or `403 Forbidden`) to prevent UUID enumeration.

---

## 4. Service-to-Service & Webhook Security

1. **Gateway-to-Service Token Forwarding**:
   - `api-gateway` validates the JWT signature, expiration, and issuer, strips any spoofed external `X-Internal-*` headers, and forwards the original `Authorization: Bearer <jwt>` header to downstream services.
   - Downstream services independently verify the JWT signature against the cached JWKS public key (Zero-Trust internal verification).
2. **Internal Service-to-Service Calls & Kubernetes NetworkPolicies**:
   - In Kubernetes (`M6`), default-deny `NetworkPolicy` blocks unauthorized pod-to-pod traffic; only explicitly allowed ingress paths (e.g., `api-gateway` → backend services, `ai-agent-service` → `api-gateway`, backend services → `postgres`/`redis`/`kafka`) are permitted.
3. **Webhook Signature Verification (`Payment Service`)**:
   - The Payment Simulator signs all webhook payloads using `HMAC-SHA256` (`X-Payment-Signature: t=<timestamp>,v1=<hmac>`) with a timestamp tolerance window of `±300 seconds` to prevent webhook spoofing and replay attacks.

---

## 5. Edge Protection, Rate Limiting & Anti-Abuse (Flash Sale)

At the `.NET 10 YARP API Gateway` + `Redis`:
1. **Global IP Rate Limit**: Token Bucket / Fixed Window limit (e.g., `100 req / 10s` per IP) for general browsing.
2. **Authenticated Flash Sale Endpoint Rate Limit**: Strict sliding-window limit on `POST /api/v1/flash-sales/{id}/claim` (`e.g., 3 requests / 5 seconds per authenticated sub`) so a single bot script cannot flood the Redis Lua gate with 10,000 requests per second.
3. **Checkout & Login Brute-Force Protection**: Strict rate limit on `POST /api/v1/auth/login` (`5 failed attempts / 15m` per email + IP).
