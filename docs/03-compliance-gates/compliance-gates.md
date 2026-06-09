# Deliverable 3: Compliance Gate Architecture
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge

---

## 1. Overview

NovaPay currently has **zero automated compliance scanning** — the last RBI audit flagged 17 non-conformances. This document defines 6 automated compliance gates embedded directly in the CI/CD pipeline, ensuring every code change is verified against RBI Master Direction and PCI-DSS v4.0 before reaching production.

**Core principle:** Compliance is not a post-release audit. It is a hard blocking condition in the deployment pipeline. A change that fails any compliance gate never reaches production — no exceptions without a documented, time-bound approval from the appropriate authority.

---

## 2. Compliance Gate Map

```
Code Commit
    │
    ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GATE 1: SAST Gate          GATE 2: Dependency Gate                 │
│  Tool: SonarQube            Tool: Trivy + Grype                     │
│  0 Critical, ≤2 High        0 Critical CVE, SBOM generated          │
│  ≥80% coverage              CVSS ≥8.0 High = block                  │
│  RBI: 5.1 | PCI: 6.2        RBI: 7.2 | PCI: 6.3                   │
└──────────────────┬───────────────────────┬───────────────────────────┘
                   │ Both pass             │
                   ▼                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GATE 3: DAST Gate          GATE 4: Licence Gate                    │
│  Tool: OWASP ZAP            Tool: FOSSA / Scancode                  │
│  0 Critical/High OWASP Top10│ No GPL/AGPL/SSPL                      │
│  Authenticated scan         │ SBOM licence inventory                │
│  RBI: 5.1 | PCI: 6.4, 11.3 │ RBI: 7.2 | PCI: 6.3                 │
└──────────────────┬───────────────────────┬───────────────────────────┘
                   │ Both pass             │
                   ▼                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  GATE 5: Policy Gate        GATE 6: Infrastructure Gate             │
│  Tool: OPA / Kyverno        Tool: Checkov / Terraform               │
│  All K8s policies pass      No privileged containers                │
│  Image signed (Cosign)      Resource limits set                     │
│  SoD enforced               IaC security baseline met               │
│  RBI: 4.3 | PCI: 6.5, 10.2 │ RBI: 5.4 | PCI: 6.5                 │
└──────────────────────────────────────────────────────────────────────┘
                   │ ALL 6 GATES PASS
                   ▼
         ✅ DEPLOY TO PRODUCTION
         + Compliance evidence bundle archived (7 years)
```

---

## 3. Gate Specifications

### Gate 1: SAST Gate

| Attribute | Specification |
|---|---|
| **Tool** | SonarQube with NovaPay Banking Quality Profile |
| **Stage** | Pipeline Stage 3 |
| **Pass Condition** | 0 Critical findings, ≤2 High findings, ≥80% line coverage |
| **Additional Checks** | Technical debt ratio ≤5%, no hardcoded credentials, no PII logging |
| **RBI Mapping** | Section 5.1 — Vulnerability assessment must be performed regularly |
| **PCI-DSS Mapping** | Requirement 6.2 — Bespoke software security |
| **On Failure** | Pipeline blocked; auto-ticket raised in Jira (P2) |
| **Exception Process** | CISO approval within 24 hours; risk acceptance form filed |
| **Audit Trail** | `{"gate":"SAST","status":"FAILED","findings":n,"timestamp":"...","approver":"..."}` |
| **Retention** | 7 years (RBI audit requirement) |

**Custom Banking Rules in SonarQube Profile:**

```
Rule: novapay:HardcodedCredentials    — Severity: BLOCKER
Rule: novapay:PIILogging             — Severity: CRITICAL  
Rule: novapay:WeakEncryption         — Severity: CRITICAL (AES<256, MD5, SHA1)
Rule: novapay:SQLInjectionRisk       — Severity: CRITICAL
Rule: novapay:InsecureRandom         — Severity: MAJOR (java.util.Random in crypto context)
Rule: novapay:UnencryptedPIIStorage  — Severity: CRITICAL
```

---

### Gate 2: Dependency & Container Vulnerability Gate

| Attribute | Specification |
|---|---|
| **Tool** | Trivy (primary) + Grype (cross-validation) + Syft (SBOM) |
| **Stage** | Pipeline Stage 4 |
| **Pass Condition** | 0 Critical CVEs; High CVEs with CVSS ≥8.0 blocked; SBOM generated |
| **SBOM Format** | CycloneDX 1.5 JSON — archived in JFrog Artifactory with image |
| **RBI Mapping** | Section 7.2 — Third-party risk management |
| **PCI-DSS Mapping** | Requirement 6.3 — Security vulnerabilities identified and managed |
| **On Failure** | Pipeline blocked; 72-hour remediation window |
| **Exception Process** | If no fix available: CISO reviews virtual patching options; time-limited exception |
| **Audit Trail** | SBOM + Trivy JSON report archived alongside every image |

**CVE Severity Decision Matrix:**

| CVSS Score | Severity | NovaPay Action |
|---|---|---|
| 9.0–10.0 | Critical | Immediate block; 24h emergency patch required |
| 7.0–8.9 | High | Block if exploitable (CVSS ≥8.0); 72h remediation |
| 4.0–6.9 | Medium | Warning only; added to tech debt backlog |
| 0.1–3.9 | Low | Logged in SBOM; no action required |

---

### Gate 3: DAST Gate

| Attribute | Specification |
|---|---|
| **Tool** | OWASP ZAP 2.14+ (Active Scan mode) |
| **Stage** | Pipeline Stage 6 |
| **Pass Condition** | 0 Critical or High findings from OWASP Top 10 |
| **Scan Coverage** | ≥90% of API endpoints (verified via OpenAPI spec) |
| **Authentication** | Authenticated scan using Vault-managed test credentials |
| **RBI Mapping** | Section 5.1 — Vulnerability assessment |
| **PCI-DSS Mapping** | Requirements 6.4 (web app protection), 11.3 (penetration testing) |
| **On Failure** | Pipeline blocked; Risk Acceptance Form required |
| **Exception Process** | CISO + TRC approval; documented risk acceptance with expiry date |
| **False Positive Process** | Security team reviews; suppression requires written justification + sign-off |

**OWASP Top 10 Blocking Rules for NovaPay:**

| OWASP Risk | ZAP Rule ID | NovaPay Threshold |
|---|---|---|
| A01: Broken Access Control | 10094, 10104 | 0 High/Critical |
| A02: Cryptographic Failures | 10112, 90001 | 0 High/Critical |
| A03: Injection (SQL, XSS) | 40018, 40012, 40014 | 0 High/Critical |
| A05: Security Misconfiguration | 10096, 10097 | 0 High/Critical |
| A06: Vulnerable Components | Covered by Gate 2 | 0 Critical CVEs |
| A07: Auth Failures | 10105, 10101 | 0 High/Critical |
| A09: Logging Failures | 10099 | 0 High/Critical |

---

### Gate 4: Licence Compliance Gate

| Attribute | Specification |
|---|---|
| **Tool** | FOSSA (primary) or Scancode Toolkit (open-source fallback) |
| **Stage** | Pipeline Stage 4 (parallel with Gate 2) |
| **Pass Condition** | No GPL, AGPL, SSPL, or LGPL dependencies in production build |
| **Allowed Licences** | MIT, Apache 2.0, BSD 2-Clause, BSD 3-Clause, ISC, MPL 2.0 |
| **RBI Mapping** | Section 7.2 — Third-party risk management (legal risk component) |
| **PCI-DSS Mapping** | Requirement 6.3 — Security vulnerabilities (supply chain) |
| **On Failure** | Pipeline blocked; Legal team notified automatically |
| **Exception Process** | Legal team sign-off required; dependency must be replaced within 90 days |
| **Audit Trail** | Full dependency tree with licence for every build, archived in SBOM |

**Licence Decision Matrix:**

| Licence | Category | NovaPay Position |
|---|---|---|
| MIT | Permissive | ✅ Approved |
| Apache 2.0 | Permissive | ✅ Approved |
| BSD 2/3-Clause | Permissive | ✅ Approved |
| ISC | Permissive | ✅ Approved |
| MPL 2.0 | Weak Copyleft | ✅ Approved (with legal review) |
| LGPL v2.1/v3 | Weak Copyleft | ⚠️ Legal review required |
| GPL v2/v3 | Strong Copyleft | ❌ Blocked |
| AGPL v3 | Network Copyleft | ❌ Blocked |
| SSPL | Network Copyleft | ❌ Blocked |
| Proprietary | Commercial | ⚠️ Procurement approval required |

---

### Gate 5: Policy & Kubernetes Compliance Gate

| Attribute | Specification |
|---|---|
| **Tools** | OPA Gatekeeper + Kyverno + Cosign |
| **Stage** | Pipeline Stage 7 |
| **Pass Condition** | All OPA/Kyverno policies pass; image signature verified |
| **Policies Enforced** | See policy list below |
| **RBI Mapping** | Sections 4.2 (change management), 4.3 (SoD), 6.1 (audit trails) |
| **PCI-DSS Mapping** | Requirements 6.5 (change management), 10.2 (audit logging) |
| **On Failure** | Deployment rejected by admission controller |
| **Exception Process** | Dual approval: Release Manager + CISO; 4-hour maximum window |
| **Audit Trail** | Every admission decision logged to immutable S3 with request details |

**Complete Policy Inventory:**

| Policy | Tool | RBI/PCI-DSS Ref | Threshold |
|---|---|---|---|
| No privileged containers | OPA | RBI 5.4 | 0 privileged containers |
| Resource limits mandatory | OPA | PCI 6.5 | CPU + Memory limits on all containers |
| No `latest` image tag | Kyverno | RBI 6.1 | Immutable SemVer tags only |
| Image must be signed | Kyverno + Cosign | RBI 6.1 | Valid Cosign signature required |
| Images from trusted registry only | Kyverno | RBI 7.2 | `artifactory.novapay.internal/*` only |
| Run as non-root | OPA | RBI 5.4 | UID != 0 |
| No host network | OPA | PCI 6.5 | `hostNetwork: false` |
| mTLS enforced | Istio + Kyverno | RBI 5.4 | PeerAuthentication STRICT mode |
| Audit logging label | OPA | RBI 6.1 | `novapay/audit-logging: "true"` label |
| Namespace isolation | OPA | RBI 4.3 | Production pods only in `novapay-prod` |
| Segregation of duties | Pipeline script | RBI 4.3 | Deployer != commit author |

---

### Gate 6: Infrastructure as Code Security Gate

| Attribute | Specification |
|---|---|
| **Tool** | Checkov (Terraform scanning) |
| **Stage** | Pipeline Stage 7 (parallel with Gate 5) |
| **Pass Condition** | No HIGH or CRITICAL Checkov findings in Terraform files |
| **Checks** | Encryption at rest, security groups, IAM least privilege, logging enabled |
| **RBI Mapping** | Section 5.4 — Encryption of data in transit and at rest |
| **PCI-DSS Mapping** | Requirement 6.5 — Change management processes |
| **On Failure** | PR blocked (IaC changes require re-approval after fix) |
| **Exception Process** | Tech Lead + Security Engineer exemption with documented rationale |
| **Audit Trail** | Checkov SARIF report archived with every IaC change |

**Key Checkov Rules for NovaPay Banking:**

```
CKV_AWS_19  — S3 bucket encryption enabled (audit logs must be encrypted)
CKV_AWS_66  — CloudWatch log group encryption
CKV_AWS_7   — KMS key rotation enabled
CKV_AWS_2   — ALB HTTPS listener only
CKV_K8S_8   — Liveness probe defined
CKV_K8S_9   — Readiness probe defined
CKV_K8S_28  — Do not admit containers with capabilities
CKV_K8S_30  — Apply security context to pods
```

---

## 4. Compliance Evidence Bundle

Every successful pipeline run generates a structured compliance evidence bundle archived to an immutable S3 bucket. Format:

```json
{
  "evidence_id": "EVD-20250608-abc1234-7821",
  "pipeline_run_id": "7821",
  "commit_sha": "abc1234def5678",
  "commit_author": "dev@novapay.in",
  "approver": "techlead@novapay.in",
  "deployment_timestamp": "2025-06-08T14:32:00Z",
  "gates": {
    "sast": {
      "status": "PASSED",
      "tool": "SonarQube",
      "critical_findings": 0,
      "high_findings": 1,
      "coverage_pct": 84.2,
      "rbi_mapping": ["5.1"],
      "pci_mapping": ["6.2"]
    },
    "dependency_scan": {
      "status": "PASSED",
      "tool": "Trivy",
      "critical_cves": 0,
      "high_cves_blocked": 0,
      "sbom_generated": true,
      "sbom_format": "CycloneDX-1.5",
      "rbi_mapping": ["7.2"],
      "pci_mapping": ["6.3"]
    },
    "dast": {
      "status": "PASSED",
      "tool": "OWASP ZAP",
      "critical_findings": 0,
      "high_findings": 0,
      "endpoints_scanned": 47,
      "rbi_mapping": ["5.1"],
      "pci_mapping": ["6.4", "11.3"]
    },
    "licence": {
      "status": "PASSED",
      "tool": "FOSSA",
      "components_scanned": 312,
      "violations": 0,
      "rbi_mapping": ["7.2"],
      "pci_mapping": ["6.3"]
    },
    "policy": {
      "status": "PASSED",
      "tool": "OPA+Kyverno",
      "policies_evaluated": 11,
      "policies_failed": 0,
      "image_signed": true,
      "sod_verified": true,
      "rbi_mapping": ["4.2", "4.3", "6.1"],
      "pci_mapping": ["6.5", "10.2"]
    },
    "infrastructure": {
      "status": "PASSED",
      "tool": "Checkov",
      "critical_findings": 0,
      "high_findings": 0,
      "rbi_mapping": ["5.4"],
      "pci_mapping": ["6.5"]
    }
  },
  "rbi_sections_verified": ["4.2","4.3","5.1","5.4","6.1","6.3","7.2"],
  "pci_requirements_verified": ["6.2","6.3","6.4","6.5","10.2","11.3"],
  "overall_status": "COMPLIANT",
  "retention_years": 7
}
```

---

## 5. Exception Workflow

When any gate fails and an exception is required:

```
Gate Fails
    │
    ▼
Auto-ticket raised in Jira (P2 minimum)
    │
    ▼
Exception Request Form submitted:
  - Gate that failed
  - Finding details
  - Business justification
  - Proposed remediation timeline
  - Risk owner (who accepts the risk)
    │
    ▼
Approval routing (based on gate):
  SAST / DAST      → CISO approval (24h SLA)
  Dependency       → CISO approval (72h SLA)
  Licence          → Legal team sign-off
  Policy           → Release Manager + CISO dual approval
  Infrastructure   → Tech Lead + Security Engineer
    │
    ▼
Approved exception is:
  - Time-limited (max 30 days; 7 days for Critical)
  - Documented in immutable audit trail
  - Assigned remediation ticket in Jira
  - Auto-expires (pipeline re-blocks after expiry)
    │
    ▼
Remediation tracking:
  - Weekly review of all open exceptions
  - CISO dashboard shows outstanding exceptions
  - Reported to TRC monthly
```

---

## 6. RBI Non-Conformance Resolution Map

NovaPay had 17 open RBI non-conformances. This table maps each compliance gate to the non-conformances it resolves:

| RBI Section | Non-Conformance | Gate That Resolves It |
|---|---|---|
| 4.2 | No documented change management process | Gates 5 + 6 (policy + IaC) + dual approval |
| 4.3 | No segregation of duties enforcement | Gate 5 (SoD policy in OPA) |
| 5.1 | No vulnerability assessment process | Gates 1 (SAST) + 3 (DAST) |
| 5.4 | Unencrypted data in transit found in audit | Gate 6 (Checkov TLS enforcement) |
| 6.1 | Incomplete audit trails for system changes | All 6 gates write to immutable evidence bundle |
| 6.3 | No incident management integration | Automated rollback + SEV classification |
| 7.2 | No third-party component risk management | Gates 2 (CVE) + 4 (licence) + SBOM |

---

## 7. Cross-References

| Topic | See Also |
|---|---|
| Gate implementation in pipeline | [Deliverable 1: Stage 7 — Policy & Compliance Gates](../01-pipeline-architecture/stage-details/stage-07-policy-compliance-gates.md) |
| OPA policy code | [`pipeline/policies/`](../../pipeline/policies/) |
| DAST in pipeline | [Deliverable 1: Stage 6 — DAST](../01-pipeline-architecture/stage-details/stage-06-dynamic-analysis-dast.md) |
| Rollback on gate failure | [Deliverable 6: Rollback Specification](../06-rollback-specification/rollback-spec.md) |
| Regulatory dashboard | [Deliverable 8: Observability](../08-observability/observability.md) |

---
