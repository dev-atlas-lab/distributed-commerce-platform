# ADR-0006: `.NET 10` YARP API Gateway & Standards-Compliant OIDC/JWT Architecture (Keycloak-Ready)

- **Status:** `ACCEPTED` (Approved in M0.1 — Q5 Standards-Compliant OIDC from Day 1, Keycloak-Ready)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We need an API Gateway for unified edge routing, rate limiting, and correlation ID injection, alongside an Authentication & Authorization architecture across `.NET 10`, `Java 21`, and `Python 3.12+` services that is **100% standards-compliant OIDC from Day 1** without requiring a `~1 GiB` Keycloak container in `M2`, yet allows seamless drop-in migration to **Keycloak** later (`Q5`).

## 2. Options Considered
- **Option A**: Custom non-standard symmetric `HS256` JWT shared secret across all services.
- **Option B (Chosen)**: **Standards-Compliant OIDC Discovery (`/.well-known/openid-configuration` & `/.well-known/jwks.json`) + Asymmetric `RS256` JWTs issued by `customer-service` in `M2–M5`, with zero-code-change configuration switch to `Keycloak` in `M6+`**.
- **Option C**: Mandatory Keycloak deployment in `M1/M2`.

## 3. Decision (`ACCEPTED`)
1. **API Gateway**: Adopt **`.NET 10 + YARP`** (`services/dotnet/api-gateway`) with Redis-backed distributed rate limiting.
2. **Standards-Compliant OIDC Design from Day 1 (`Q5 — ACCEPTED`)**:
   - `customer-service` exposes standard OIDC metadata endpoints:
     - `GET /.well-known/openid-configuration` (`issuer`, `jwks_uri`, `token_endpoint`, `id_token_signing_alg_values_supported: ["RS256"]`)
     - `GET /.well-known/jwks.json` (public RSA key set with explicit `kid`, `kty`, `use: "sig"`, `alg: "RS256"`, `n`, `e`)
   - All issued Access Tokens (`15m` TTL) use standard OIDC/JWT claims: `iss`, `sub`, `aud`, `exp`, `nbf`, `iat`, `jti`, `scope`, and `roles` (mapped cleanly from both top-level `roles` and Keycloak's `realm_access.roles` claim structure via a unified claim transformer).
   - All downstream Resource Servers (`api-gateway`, `product-service`, `order-service`, `inventory-service`, `payment-service`, `promotion-service`, `ai-agent-service`) validate tokens strictly via `AUTH_ISSUER_URI` OIDC discovery—never hardcoding public keys or custom proprietary token validation logic.
   - When **Keycloak** is introduced in `M6` (or any environment profile), switching from built-in OIDC to Keycloak requires changing only `AUTH_ISSUER_URI` in environment configuration.

## 4. Consequences & Trade-offs
- **Positive**: Zero shared signing secret risk; zero extra `1 GiB` container overhead during `M2–M5`; gives hands-on mastery of OIDC Discovery, `JWKS` key rotation (`kid`), `Argon2id`, and refresh token rotation while guaranteeing plug-and-play Keycloak compatibility.
- **Negative / Cost**: Requires implementing `/.well-known/openid-configuration`, `/.well-known/jwks.json`, and dual role-claim mapping (`roles` / `realm_access.roles`).

## 5. Rejected Alternatives
- **Option A (`HS256` or non-standard JWTs)**: Couples services to custom auth logic and requires refactoring every service when Keycloak is introduced.
