# ADR-0006: `.NET 10` YARP API Gateway & Standards-Based `RS256` JWT/JWKS Authentication

- **Status:** `PROPOSED`
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We need an API Gateway to provide unified ingress routing, rate limiting, CORS, and correlation ID injection, and an Authentication/Authorization mechanism across `.NET 10`, `Java 21`, and `Python 3.12+` services without overloading development VMs with heavy identity infrastructure prematurely.

## 2. Options Considered
- **Gateway Options**: `.NET 10 YARP` vs. `Spring Cloud Gateway` vs. `Kong`.
- **Auth Options**:
  - **Option A**: Symmetric `HS256` JWT shared secret across all 9 services.
  - **Option B**: Asymmetric `RS256` OAuth2/OIDC JWT issued by `customer-service` with public key published via `/.well-known/jwks.json` (OIDC Discovery compatible), swappable with `Keycloak`.
  - **Option C**: Mandatory `Keycloak` container from Day 1 (`M2`).

## 3. Decision
1. **API Gateway**: Adopt **`.NET 10 + YARP`** (`services/dotnet/api-gateway`) with Redis-backed distributed rate limiting (`Microsoft.AspNetCore.RateLimiting`).
2. **Authentication**: Adopt **Option B (`RS256` JWT + JWKS endpoint in `customer-service`)** for `M2–M5`, with optional plug-and-play **Keycloak** integration in `M6`:
   - Only `customer-service` holds the private RSA signing key (`RS256`).
   - All other services (`api-gateway`, `order-service`, `inventory-service`, `payment-service`, `promotion-service`, `ai-agent-service`) fetch and cache the public key from `/.well-known/jwks.json`.

## 4. Consequences & Trade-offs
- **Positive**: Zero shared signing secret (`HS256` compromise risk eliminated); zero extra `1 GiB` Keycloak container required in `M2`; lets you implement `Argon2id`, refresh token rotation, and `JWKS` first-hand; 100% compatible with Keycloak via configuration change.
- **Negative / Cost**: Requires implementing refresh token rotation and JTI revocation in `customer-service`.

## 5. Rejected Alternatives
- **Option A (`HS256` shared secret)**: Any compromised downstream service could forge admin JWTs for the entire platform.
- **Option C (Mandatory Keycloak in M2)**: Consumes `~800 MiB–1 GiB` RAM on local/dev VMs and hides core authentication engineering behind an external product.
