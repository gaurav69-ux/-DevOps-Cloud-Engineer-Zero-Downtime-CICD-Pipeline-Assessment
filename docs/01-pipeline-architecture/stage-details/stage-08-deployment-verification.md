# Stage 8: Deployment & Verification

**Tool:** ArgoCD + Istio + Prometheus  
**SLA Target:** < 15 minutes  
**RBI Mapping:** Sections 4.2, 6.3 — Change management, incident management  
**PCI-DSS Mapping:** Requirement 6.5 — Change management processes

## Purpose
Deploy the verified artefact to production with zero downtime and verify success.

## Inputs
- Signed, scanned, policy-approved Docker image
- Helm chart with environment-specific values
- ArgoCD Application manifest
- Deployment runbook (reviewed and signed off)

## Outputs
- ArgoCD sync status
- Smoke test results (15 critical path tests)
- Version consistency check (all pods same SHA)
- Post-deploy metrics baseline
- Deployment audit record

## Quality Gates & Thresholds
- Smoke tests: 15/15 pass required
- Version consistency: All pods must run identical image SHA
- Error rate post-deploy: < 0.1% for 5 minutes
- p99 latency post-deploy: Within 10% of baseline
- Rollback trigger: HTTP 5xx > 5% for 60s → auto-rollback

## Failure Mode & Remediation
**On failure:** Automatic rollback to last known good deployment. SEV-2 incident raised automatically. On-call engineer paged. Postmortem required within 48 hours.

## Configuration Reference
See [architecture.md](../architecture.md#stage-8) for full specification.
