# Stage 2: Build & Compilation

**Tool:** Gradle 8.x + Docker BuildKit  
**SLA Target:** < 8 minutes  
**RBI Mapping:** Section 6.1 — Audit trails  
**PCI-DSS Mapping:** Requirement 6.2 — Bespoke software security

## Purpose
Produce a reproducible, versioned, signed Docker image with passing unit tests.

## Inputs
- Source code from Stage 1
-  (must exist)
- Base image: 

## Outputs
- Docker image: 
- JaCoCo coverage report
- JUnit test results XML
- Gradle dependency report

## Quality Gates & Thresholds
- Unit tests: 100% pass rate, 0 failures tolerated
- Line coverage: ≥80%
- Branch coverage: ≥70%
- Dependency lockfile: Must exist and be committed
- Build time: < 8 minutes

## Failure Mode & Remediation
**On failure:** Build log published as PR comment. Pipeline blocked. Developer must fix locally and re-push. No escalation — self-service.

## Configuration Reference
See [architecture.md](../architecture.md#stage-2) for full specification.
