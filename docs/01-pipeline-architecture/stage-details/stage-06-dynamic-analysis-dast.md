# Stage 6: Dynamic Analysis (DAST)

**Tool:** OWASP ZAP 2.14+  
**SLA Target:** < 20 minutes  
**RBI Mapping:** Section 5.1 — Vulnerability assessment  
**PCI-DSS Mapping:** Requirements 6.4, 11.3 — Web app protection, pen testing

## Purpose
Test the running application for security vulnerabilities that only manifest at runtime.

## Inputs
- Running application in staging environment
- OpenAPI/Swagger specification
- ZAP authenticated test credentials (from Vault)
- OWASP ZAP scan policy: 

## Outputs
- ZAP findings report (Critical, High, Medium)
- OWASP Top 10 compliance status
- Authenticated scan coverage report
- API endpoint coverage metrics

## Quality Gates & Thresholds
- Critical findings: 0 (hard block)
- High findings from OWASP Top 10: 0 (hard block)
- Authenticated scan: Must cover ≥90% of API endpoints
- Scan completion: Full active scan required (not passive only)

## Failure Mode & Remediation
**On failure:** Pipeline blocked. Risk Acceptance Form required signed by CISO. TRC approval needed for production deployment exception. Documented in compliance audit trail.

## Configuration Reference
See [architecture.md](../architecture.md#stage-6) for full specification.
