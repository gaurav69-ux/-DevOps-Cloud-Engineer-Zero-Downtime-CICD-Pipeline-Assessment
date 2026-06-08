# Project 1A: DevOps & Cloud Engineer
## Zero-Downtime CI/CD Pipeline with Compliance Gates for Banking Applications

**Candidate:** [Gaurav Durge]
**Track:** Cloud & DevOps Tech | CI/CD Pipeline Architecture
**Organisation:** NovaPay Digital Bank (Fictional)
**Timeline:** 15 Days | AI-Accelerated Innovation & Research Project
**Submitted to:** ZethetaIntern GitHub Organisation

---

## Executive Summary

This project designs and delivers a production-grade, zero-downtime CI/CD pipeline architecture for **NovaPay Digital Bank** — a fictional RBI-licensed bank currently operating with manual SSH deployments, a 4.5-hour MTTR, fortnightly release cycles, and 17 outstanding RBI audit non-conformances.

The proposed solution transforms NovaPay's deployment capability from a manually operated, compliance-deficient process into an eight-stage automated pipeline that:

- Reduces **commit-to-production time** from 2 weeks → under 2 hours
- Reduces **MTTR** from 4.5 hours → under 15 minutes
- Achieves **five-nines (99.999%) availability** via blue-green and canary strategies
- Enforces **6 automated compliance gates** mapped to RBI Master Direction and PCI-DSS v4.0
- Implements **zero-downtime database migrations** using the expand-contract pattern
- Produces **complete audit evidence** for every code change reaching production

---

## Repository Navigation

| Section | Path | Description |
|---|---|---|
| **Pipeline Architecture** | [`docs/01-pipeline-architecture/`](docs/01-pipeline-architecture/architecture.md) | 8-stage pipeline design, diagrams, stage specs |
| **Deployment Strategies** | [`docs/02-deployment-strategies/`](docs/02-deployment-strategies/deployment-strategies.md) | Blue-green + canary with rollback |
| **Compliance Gates** | [`docs/03-compliance-gates/`](docs/03-compliance-gates/compliance-gates.md) | 6+ gates mapped to RBI + PCI-DSS |
| **Database Migration** | [`docs/04-database-migration/`](docs/04-database-migration/db-migration.md) | Expand-contract ZDT migration strategy |
| **Environment Promotion** | [`docs/05-environment-promotion/`](docs/05-environment-promotion/env-promotion.md) | Dev → Staging → Pre-Prod → Production |
| **Rollback Specification** | [`docs/06-rollback-specification/`](docs/06-rollback-specification/rollback-spec.md) | Automated rollback triggers (3 categories) |
| **Runbook & Playbook** | [`runbooks/`](runbooks/deployment-runbook.md) | Production runbook + incident response playbook |
| **Observability** | [`docs/08-observability/`](docs/08-observability/observability.md) | DORA metrics, dashboards, alerting |
| **Pipeline Code** | [`pipeline/`](pipeline/.github/workflows/) | GitHub Actions YAML, Helm, Terraform, OPA |
| **TRC Presentation** | [`evidence/trc-presentation.pdf`](evidence/trc-presentation.pdf) | Technology Risk Committee deck |
| **Deliberate Errors** | [`ERRATA.md`](ERRATA.md) | 3 planted errors identified and corrected |

---

## NovaPay Current State vs Target State

| Metric | Current State | Target State |
|---|---|---|
| Deployment Frequency | Once every 2 weeks | Multiple times per day |
| Commit-to-Production Time | ~2 weeks | < 2 hours |
| MTTR | 4.5 hours | < 15 minutes |
| Automated Compliance Scanning | Zero | 6 automated gates |
| RBI Audit Non-Conformances | 17 open | 0 (all addressed) |
| Deployment Method | Manual SSH | Automated GitOps (ArgoCD) |
| Observability | Zero (customer-reported) | Full-stack (Prometheus + Grafana + Loki) |
| Database Migrations | Manual, 2 AM maintenance window | Zero-downtime (expand-contract) |

---

## Architecture Overview

```
Developer Commit
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│                    GITHUB ENTERPRISE                         │
│  Branch Protection │ Signed Commits │ PR Required           │
└─────────────────────────────┬───────────────────────────────┘
                              │ Webhook Trigger
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                  CI PIPELINE (GitHub Actions)                │
│                                                              │
│  Stage 1        Stage 2        Stage 3        Stage 4       │
│  Source Control → Build &   → SAST        → Dependency &   │
│  & Trigger       Unit Test    (SonarQube)   Container Scan  │
│                                              (Trivy + SBOM)  │
│                                                              │
│  Stage 5        Stage 6        Stage 7        Stage 8       │
│  Integration  → DAST        → Policy &     → Deploy &      │
│  & Contract     (OWASP ZAP)   Compliance     Verification  │
│  Testing                       Gates (OPA)    (ArgoCD)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              DEPLOYMENT STRATEGY (Kubernetes + Istio)        │
│                                                              │
│   Blue-Green (major releases)   Canary (feature releases)   │
│   ├── novapay-prod-blue         ├── 1-2% → 5-10%           │
│   └── novapay-prod-green        ├── 25-50% → 100%          │
│                                  └── Auto-rollback on SLO   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    OBSERVABILITY STACK                       │
│  Prometheus (metrics) │ Grafana (dashboards) │ Loki (logs) │
│  OpenTelemetry (tracing) │ Alertmanager (routing)           │
└─────────────────────────────────────────────────────────────┘
```

---

## Technology Stack

| Category | Tool | Purpose |
|---|---|---|
| CI/CD Engine | GitHub Actions | Pipeline orchestration |
| GitOps | ArgoCD 2.x | Declarative K8s deployments |
| Container Runtime | Kubernetes 1.29+ (EKS) | Workload orchestration |
| Service Mesh | Istio | Traffic management, mTLS, canary routing |
| SAST | SonarQube | Static code analysis |
| DAST | OWASP ZAP | Dynamic security scanning |
| Container Scanning | Trivy | CVE scanning + SBOM generation |
| Policy Engine | OPA / Kyverno | Compliance-as-code |
| IaC | Terraform 1.7+ | Infrastructure provisioning |
| Packaging | Helm | Kubernetes application packaging |
| Secrets | HashiCorp Vault | Secrets management + rotation |
| Monitoring | Prometheus + Grafana | Metrics + dashboards |
| Logging | Grafana Loki | Log aggregation |
| Tracing | OpenTelemetry + Jaeger | Distributed tracing |
| Image Signing | Cosign | Supply chain security |
| IaC Scanning | Checkov | Terraform security scanning |

---

## Compliance Coverage

| Regulatory Framework | Coverage |
|---|---|
| RBI Master Direction on IT Risk | Sections 4.2, 4.3, 5.1, 5.4, 6.1, 6.3, 7.2 |
| PCI-DSS v4.0 | Requirements 6.2, 6.3, 6.4, 6.5, 10.2, 11.3, 12.6 |
| Segregation of Duties | RBAC enforcement across all pipeline stages |

---

## DORA Metrics Targets

| Metric | Current | Target | Elite Benchmark |
|---|---|---|---|
| Deployment Frequency | 2x/month | Multiple/day | Multiple/day ✅ |
| Lead Time for Changes | ~2 weeks | < 2 hours | < 1 hour |
| Change Failure Rate | Unknown | < 5% | < 5% ✅ |
| MTTR | 4.5 hours | < 15 minutes | < 1 hour ✅ |

---

## Project Deliverables Status

| Deliverable | Status | Day Completed |
|---|---|---|
| D1: Pipeline Architecture | 🔄 In Progress | Day 3 |
| D2: Deployment Strategies | ⏳ Pending | Day 4 |
| D3: Compliance Gates | ⏳ Pending | Day 5 |
| D4: Database Migration | ⏳ Pending | Day 6 |
| D5: Environment Promotion | ⏳ Pending | Day 7 |
| D6: Rollback Specification | ⏳ Pending | Day 8 |
| D7: Runbook & Playbook | ⏳ Pending | Day 9 |
| D8: Observability | ⏳ Pending | Day 10 |
| TRC Presentation | ⏳ Pending | Day 11 |
| Incident Simulation | ⏳ Pending | Day 12 |
| ERRATA (3 errors) | ✅ Complete | Day 1 |

---

## AI Usage Attribution

This project was developed with AI assistance (Claude by Anthropic) for:
- Research synthesis and documentation structure
- YAML pipeline configuration templates
- OPA Rego policy examples
- Architecture diagram descriptions

All technical decisions, regulatory mappings, and design choices were made and validated by the candidate. AI outputs were reviewed, customised, and adapted to NovaPay's specific banking context.

---

*Strictly Private and Confidential — Submitted to Zetheta Algorithms Private Limited*
