# Stage 3: Static Analysis (SAST)

**Tool:** SonarQube + Custom Banking Quality Profile  
**SLA Target:** < 10 minutes  
**RBI Mapping:** Section 5.1 — Vulnerability assessment  
**PCI-DSS Mapping:** Requirement 6.2 — Bespoke software security

## Purpose
Detect security vulnerabilities and code quality issues in source code before runtime.

## Inputs
- Source code
- JaCoCo coverage report from Stage 2
- SonarQube quality profile: 

## Outputs
- SonarQube quality gate result (PASS/FAIL)
- Findings report (Critical, High, Medium, Low)
- Technical debt ratio
- Coverage metrics

## Quality Gates & Thresholds
- Critical findings: 0 (hard block)
- High findings: ≤2 (block if >2)
- Coverage: ≥80% line (enforced in SonarQube gate)
- Technical debt ratio: ≤5% for new code
- New issues: Critical/High introduced by PR = block

## Failure Mode & Remediation
**On failure:** Pipeline blocked. Auto-ticket created in Jira assigned to developer. CISO notified. CISO must approve within 24h or risk accept within 72h. Exception documented in audit log.

## Configuration Reference
See [architecture.md](../architecture.md#stage-3) for full specification.
