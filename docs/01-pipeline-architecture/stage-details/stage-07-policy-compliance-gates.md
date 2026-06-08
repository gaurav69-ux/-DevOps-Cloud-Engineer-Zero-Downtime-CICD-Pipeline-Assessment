# Stage 7: Policy & Compliance Gates

**Tool:** OPA Gatekeeper + Kyverno + Checkov + Cosign  
**SLA Target:** < 3 minutes  
**RBI Mapping:** Sections 4.2, 4.3, 5.4, 6.1  
**PCI-DSS Mapping:** Requirements 6.5, 10.2 — Change management, audit logging

## Purpose
Final automated compliance checkpoint — codify every regulatory requirement as a policy.

## Inputs
- Kubernetes manifests (Helm-rendered)
- Docker image with Cosign signature
- Terraform plan output
- Pipeline audit trail from all previous stages

## Outputs
- OPA policy evaluation results
- Kyverno admission webhook results
- Checkov IaC scan results
- Cosign signature verification
- Compliance evidence bundle (JSON)

## Quality Gates & Thresholds
- Image signature: Must be valid Cosign signature
- Privileged containers: 0 allowed
- Resource limits: CPU + Memory limits mandatory
- Latest tag: Blocked in production
- TLS version: Minimum 1.3
- SoD: Deployer ≠ code author
- All RBI/PCI-DSS OPA policies: 100% pass

## Failure Mode & Remediation
**On failure:** Deployment rejected by admission controller. Dual approval override available for P1 incidents only — requires Release Manager + CISO approval. Full exception documented.

## Configuration Reference
See [architecture.md](../architecture.md#stage-7) for full specification.
