# Stage 4: Dependency & Container Scanning

**Tool:** Trivy + Syft + Grype  
**SLA Target:** < 8 minutes  
**RBI Mapping:** Section 7.2 — Third-party risk management  
**PCI-DSS Mapping:** Requirement 6.3 — Security vulnerabilities

## Purpose
Verify all third-party dependencies and the container image have no critical vulnerabilities.

## Inputs
- Docker image from Stage 2
-  from Gradle
- Trusted base image registry (JFrog Artifactory)

## Outputs
- Trivy vulnerability report
- SBOM in CycloneDX 1.5 JSON format
- Licence compliance report
- Container image provenance attestation

## Quality Gates & Thresholds
- Critical CVE: 0 (hard block)
- High CVE with CVSS ≥8.0: Block
- High CVE with CVSS <8.0: Warning, proceed
- GPL/AGPL/SSPL licence: Block (legal review)
- SBOM: Must be generated and archived

## Failure Mode & Remediation
**On failure (Critical CVE):** 72h remediation window. Developer must upgrade dependency. If no fix available, security team assesses virtual patching. CISO approves exception with time limit.

## Configuration Reference
See [architecture.md](../architecture.md#stage-4) for full specification.
