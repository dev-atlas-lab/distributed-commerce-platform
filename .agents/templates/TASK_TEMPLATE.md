# Task Specification Template (`DCP-M<X>-<NNN>`)

- **Task ID:** `DCP-M<X>-<NNN>`
- **Title:** `<Short Descriptive Action Title>`
- **Status:** `PROPOSED` | `DISCUSSION` | `ACCEPTED` | `IMPLEMENTING` | `IMPLEMENTED` | `VERIFIED` | `DONE`
- **Owner:** `Human Engineer` (Business Implementation) / `AI Engineering Team` (Scaffolding, Contracts, Tests, Review)

## 1. Business Context
Why does this task matter to the customer, merchant, or business domain?

## 2. Technical Context
Which Bounded Context, service, database, and ADRs govern this task?

## 3. Objective
Single clear statement of what this task achieves.

## 4. Scope
- **In Scope:**
  - ...
- **Out of Scope:**
  - ...

## 5. Dependencies
- Upstream Task IDs, ADRs, or contracts required before starting.

## 6. Acceptance Criteria
1. ...
2. ...

## 7. Edge Cases & Failure Modes
- Concurrency collisions, duplicate requests, network timeouts, malformed payloads, out-of-order events.

## 8. Security Considerations
- JWT validation, RBAC/ABAC (`IDOR` check), input validation, secret handling.

## 9. Test Cases
- **Positive:**
- **Negative:**
- **Edge / Concurrency:**

## 10. Expected Deliverables
- Exact file paths, migrations, contracts, and test files.

## 11. Definition of Done (DoD)
- All quality gates pass (`build`, `lint`, `unit`, `integration`, `contract`) with verifiable command output.
