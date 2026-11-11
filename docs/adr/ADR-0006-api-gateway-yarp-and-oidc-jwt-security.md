# ADR-0006: `.NET 10` YARP API Gateway, OIDC Identity vs. RFC 9068 OAuth2 Access Tokens & Scoped Service Identity

- **Status:** `ACCEPTED` (`Q5` Standards-Compliant OIDC from Day 1, Keycloak-Ready Accepted in `M0.1`; `CH-05` RFC 9068 Validation & Claim Normalization Approved in Principle, Pending Final Validation in `M0.2.1`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We need an API Gateway (`.NET 10 YARP`) and an authentication/authorization architecture across `.NET 10`, `Java 21`, and `Python 3.12+` that cleanly separates **OIDC Authentication (`id_token`)** from **OAuth2 Resource Authorization (`RFC 9068` `access_token`)**, handles split-horizon container networking (`iss` vs. internal `jwks_uri`), supports zero-downtime key rotation (`kid`), enforces least-privilege M2M `client_credentials` scopes, and guarantees zero-code-change migration to **Keycloak** (`Q5`, `CH-05`).

## 2. Options Considered
- **Option A**: Symmetric `HS256` shared secret or passing OIDC `id_token`s to backend resource servers.
- **Option B**: **Standards-Compliant OIDC (`id_token` for SPA only) + RFC 9068 OAuth2 JWT `access_token`s for Resource Servers + Split Issuer/JWKS Resolution + Dual-Key Rotation + Keycloak-Compatible Claim Normalization (`CH-05`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `.NET 10 + YARP` serves as the edge API Gateway.
   - `customer-service` implements OIDC Discovery (`/.well-known/openid-configuration`, `/.well-known/jwks.json`) and `RS256` token issuance in `M2–M5`, swappable with **Keycloak** via configuration in `M6+`.
2. **Validated `M0.2.1` OIDC & OAuth2 Specifications (`PROPOSED` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-05`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **OIDC Identity (`id_token`) vs. OAuth2 Authorization (`access_token`)**: `id_token` (`aud: "commerce-web-spa"`) is consumed exclusively by the frontend SPA for user session identity and is **rejected** (`401`) if sent to `api-gateway` or backend APIs. Backend Resource Servers accept only RFC 9068 `access_token`s (`typ` in `["at+jwt", "JWT"]`, `"commerce-api" \in aud`).
   - **Split-Horizon Discovery**: Resource servers validate `iss == AUTH_ISSUER_URI` (`https://auth.commerce.dev-atlas.lab`) while fetching JWKS keys over internal cluster network `AUTH_JWKS_URI` (`http://customer-service:8080/.well-known/jwks.json`).
   - **Zero-Downtime Key Rotation (`kid`)**: `/.well-known/jwks.json` publishes both the `ACTIVE_SIGNER` key and the previous `VERIFY_ONLY` key for $\ge 2 \times \text{MaxTokenTTL}$ (`30m`).
   - **Keycloak-Compatible Claim Normalization & Principal Separation**:
     - `resolved_client_id = coalesce(jwt.client_id, jwt.azp)`
     - **Strict Principal Separation (`HUMAN_PRINCIPAL` vs. `SERVICE_PRINCIPAL`)**: M2M `client_credentials` tokens (`sub` starting with `service-account-`) are classified as `SERVICE_PRINCIPAL` and stripped of any human roles (`CUSTOMER`, `ADMIN_MERCHANT`, `ADMIN_OPS`), preventing M2M privilege escalation.
     - For `HUMAN_PRINCIPAL` tokens, human roles are extracted only from the explicit allowlist `{"CUSTOMER", "ADMIN_MERCHANT", "ADMIN_OPS"}` in `jwt.roles` or `jwt.realm_access.roles`, while client-specific roles are scoped strictly to the target service's own resource key (`jwt.resource_access[target_service_id].roles`).
     - `scopes = split(jwt.scope, " ")`
   - **Per-Service Authorization Policies**: Enforced via explicit `(PrincipalType, Role, Scope, OwnershipRule)` policies at each service boundary.

## 4. Consequences & Trade-offs
- **Positive**: Strict adherence to OIDC Core 1.0 and RFC 9068; zero application code changes when migrating to Keycloak; prevents `id_token` misuse and M2M privilege escalation.
- **Negative / Cost**: Requires configuring the 5-step claim normalization pipeline in Java, .NET, and Python security middleware (`M1/M2`).

## 5. Rejected Alternatives
- **Option A (Accepting `id_token` at Resource Servers or flat M2M roles)**: Violates OAuth2 audience isolation and least privilege.
