# Pipeline Architecture Diagrams

## Diagram 1: Full 8-Stage Pipeline Flow

> Copy this code into https://mermaid.live to generate the PNG diagram.
> Export as PNG and save as `pipeline-overview.png` in this folder.

```mermaid
flowchart LR
    subgraph SRC["① Source Control"]
        A1[GitHub Enterprise\nBranch Protection\nSigned Commits]
    end

    subgraph BLD["② Build"]
        B1[Gradle Build\nUnit Tests\nJaCoCo Coverage\nDocker Multi-Stage]
    end

    subgraph SEC["③④ Security — Parallel"]
        C1[SonarQube\nSAST\n0 Critical]
        C2[Trivy + Syft\nContainer Scan\nSBOM]
    end

    subgraph INT["⑤ Integration"]
        D1[Pact Contracts\nEphemeral K8s\nPerf Baseline]
    end

    subgraph DAST["⑥ DAST"]
        E1[OWASP ZAP\nActive Scan\nOWASP Top 10]
    end

    subgraph GATE["⑦ Compliance"]
        F1[OPA Policies\nCosign Verify\nRBI + PCI-DSS\nSoD Check]
    end

    subgraph DEPLOY["⑧ Deploy"]
        G1{Strategy}
        G2[Blue-Green]
        G3[Canary\n1→10→50→100%]
        G4[Smoke Tests\nVersion Check\nRollback Ready]
    end

    SRC --> BLD --> SEC --> INT --> DAST --> GATE --> DEPLOY
    G1 -->|Major| G2
    G1 -->|Feature| G3
    G2 & G3 --> G4

    style SRC fill:#1a3a6b,color:#fff
    style BLD fill:#1a3a6b,color:#fff
    style SEC fill:#7b1a00,color:#fff
    style INT fill:#1a4a6b,color:#fff
    style DAST fill:#7b1a00,color:#fff
    style GATE fill:#1a6b2a,color:#fff
    style DEPLOY fill:#4a1a6b,color:#fff
```

---

## Diagram 2: Deployment Strategy Detail

```mermaid
flowchart TD
    subgraph PROD["Production Kubernetes Cluster"]
        subgraph BG["Blue-Green Strategy"]
            BL[novapay-prod-BLUE\nCurrent Live Traffic\n100%]
            GR[novapay-prod-GREEN\nNew Version Deploying\n0% traffic initially]
            IS[Istio VirtualService\nAtomic Switch]
            BL -->|"Step 5: Switch"| IS
            GR -->|"Step 4: Ready"| IS
        end

        subgraph CAN["Canary Strategy"]
            SV[Stable Version\n100% → 99% → 95% → 50% → 0%]
            CV[Canary Version\n0% → 1% → 5% → 50% → 100%]
            PR[Prometheus\nError Rate\nLatency p99]
            SV & CV --> PR
        end
    end

    subgraph DB["Shared Database Layer"]
        PG[(PostgreSQL 16\npgBouncer\nRead/Write)]
        RD[(Redis 7\nSession Store\n3 nodes)]
    end

    BL & GR & SV & CV --> DB
```

---

## Diagram 3: Compliance Gate Chain

```mermaid
flowchart LR
    A[Code Commit] --> B{SAST Gate\nSonarQube}
    B -->|0 Critical ✅| C{Dependency Gate\nTrivy}
    B -->|Critical Found ❌| B1[Block + Auto-ticket\nCISO 24h approval]
    C -->|0 Critical CVE ✅| D{DAST Gate\nOWASP ZAP}
    C -->|Critical CVE ❌| C1[Block\n72h remediation]
    D -->|0 Critical/High ✅| E{Licence Gate\nFOSSA}
    D -->|Critical Found ❌| D1[Block\nRisk Accept + TRC]
    E -->|No GPL/AGPL ✅| F{Policy Gate\nOPA/Kyverno}
    E -->|Violation ❌| E1[Block\nLegal Team Sign-off]
    F -->|All Policies Pass ✅| G{Infra Gate\nCheckov}
    F -->|Policy Fail ❌| F1[Deploy Rejected\nDual Approval Override]
    G -->|No Violations ✅| H[✅ Deploy to Production]
    G -->|Violation ❌| G1[PR Blocked\nTech Lead Exemption]
```

---

## How to Generate PNG Diagrams

1. Go to **https://mermaid.live**
2. Paste each diagram code block above
3. Click **Download PNG**
4. Save in this `/diagrams/` folder as:
   - `pipeline-overview.png`
   - `deployment-strategy.png`
   - `compliance-gate-chain.png`
5. Embed in architecture.md using: `![Pipeline Overview](diagrams/pipeline-overview.png)`

