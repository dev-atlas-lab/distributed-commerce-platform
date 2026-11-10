# ADR-0006: `.NET 10` YARP API Gateway, Standards-Compliant OIDC/JWT & Scoped Service Identity

- **Status:** `ACCEPTED` (`Q5` Standards-Compliant OIDC from Day 1, Keycloak-Ready Accepted in `M0.1`; `CH-05` Split-Horizon Discovery, Key Rotation & M2M Scopes `PROPOSED` in `M0.2`)
- **Date:** 2026-11-10
- **Deciders:** Human Architect, Solution Architect Agent

## 1. Context & Problem
We need an API Gateway (`.NET 10 YARP`) and an OIDC/OAuth2 architecture across `.NET 10`, `Java 21`, and `Python 3.12+` that is standards-compliant from Day 1 (`Q5`) and ready for seamless **Keycloak** introduction later, while solving split-horizon Docker/K8s discovery (`iss` vs. internal `jwks_uri`), zero-downtime signing key rotation (`kid`), and least-privilege service-to-service (`client_credentials`) authentication (`CH-05`).

## 2. Options Considered
- **Option A**: Symmetric `HS256` shared secret + flat `"INTERNAL_SERVICE"` god-role.
- **Option B**: **Standards-Compliant OIDC (`/.well-known/openid-configuration`, `/.well-known/jwks.json`) + `RS256` JWTs (RFC 9068 Profile) + Split Issuer/JWKS Resolution + Dual-Key Rotation + Scoped `client_credentials` M2M Identity (`CH-05`)**.

## 3. Decision
1. **Accepted Baseline (`ACCEPTED`)**:
   - `.NET 10 + YARP` serves as the edge API Gateway.
   - `customer-service` implements standard OIDC Discovery and `RS256` JWT issuance in `M2–M5`, swappable with **Keycloak** via configuration in `M6+`.
2. **Refined OIDC & Service Identity Specifications (`PROPOSED` in `M0.2` — See [`ARCHITECTURE_CHALLENGE_M0_1.md#ch-05`](file:///home/anhltn/projects/distributed-commerce-platform/docs/architecture/ARCHITECTURE_CHALLENGE_M0_1.md))**:
   - **Public vs. Internal Discovery Resolution**: Resource servers validate the JWT `iss` claim against logical `AUTH_ISSUER_URI` (`https://auth.commerce.dev-atlas.lab`) while fetching JWKS keys over internal cluster network `AUTH_JWKS_URI` (`http://customer-service:8080/.well-known/jwks.json`).
   - **Zero-Downtime Key Rotation (`kid`)**: `/.well-known/jwks.json` publishes both the `ACTIVE_SIGNER` key and the previous `VERIFY_ONLY` key for $\ge 2 \times \text{MaxTokenTTL}$ (`30m`).
   - **Keycloak-Compatible Claim Mapping**: Support both top-level `roles` and `realm_access.roles` + standard OAuth2 `scope` and `azp`.
   - **Least-Privilege M2M (`client_credentials`)**: Background service-to-service calls use scoped client credentials (`inventory:quota:allocate`, `inventory:read`, etc.) rather than a blanket admin role; `ai-agent-service` strictly uses On-Behalf-Of user JWT propagation.

## 4. Consequences & Trade-offs
- **Positive**: Zero split-horizon container networking failures; zero active-session drops during key rotation; zero application code changes when switching to Keycloak.
- **Negative / Cost**: Requires maintaining a 2-key JWKS ring (`ACTIVE` + `PREVIOUS`) and scope policies per internal client.

## 5. Rejected Alternatives
- **Flat `"INTERNAL_SERVICE"` role without scopes**: Rejected in `M0.2` because it violates least privilege across service boundaries.
