# Stage-by-Stage Specifications Index

This folder contains individual specification files for each pipeline stage.
Cross-reference with the main [architecture.md](../architecture.md) for the full picture.

| File | Stage | Key Tool |
|---|---|---|
| [stage-01-source-control.md](stage-01-source-control.md) | Source Control & Trigger | GitHub Enterprise |
| [stage-02-build.md](stage-02-build.md) | Build & Compilation | Gradle + Docker |
| [stage-03-sast.md](stage-03-sast.md) | Static Analysis (SAST) | SonarQube |
| [stage-04-dependency-scan.md](stage-04-dependency-scan.md) | Dependency & Container Scan | Trivy + Syft |
| [stage-05-integration-testing.md](stage-05-integration-testing.md) | Integration & Contract Testing | Pact |
| [stage-06-dast.md](stage-06-dast.md) | Dynamic Analysis (DAST) | OWASP ZAP |
| [stage-07-compliance-gates.md](stage-07-compliance-gates.md) | Policy & Compliance Gates | OPA + Kyverno |
| [stage-08-deployment.md](stage-08-deployment.md) | Deployment & Verification | ArgoCD + Istio |
