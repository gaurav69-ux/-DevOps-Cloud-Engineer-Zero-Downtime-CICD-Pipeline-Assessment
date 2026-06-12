# NovaPay Incident Response Playbook
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge  
**Standard:** Production-quality — covers SEV-1 through SEV-4 with full communication templates

---

## Part 1: Severity Classification

| Severity | Definition | Response Time | Auto-Rollback | Escalation |
|---|---|---|---|---|
| **SEV-1** | Complete service outage OR data integrity risk OR UPI transaction failure affecting >50% users | < 5 minutes | Category A (automatic) | CTO + CISO + VP Eng |
| **SEV-2** | Major feature degradation affecting >10% users OR rollback executed | < 15 minutes | Category A or B | VP Eng + SRE Lead |
| **SEV-3** | Minor degradation, workaround exists, <10% users affected | < 1 hour | Category C (manual) | SRE on-call + Tech Lead |
| **SEV-4** | Cosmetic issue, no user impact, no SLA breach | Next business day | None | Assigned engineer |

**RBI obligation:** Any technology incident exceeding 30 minutes duration must be reported to RBI within the timeframe specified in the Master Direction on IT Risk (Section 6.3).

---

## Part 2: Seven-Step Incident Response Workflow

### Step 1 — DETECT (T+0)
**Sources:** Prometheus → Alertmanager → PagerDuty → Slack #incidents

```
Automated detection (Category A) → PagerDuty pages on-call within 30 seconds
Manual detection (customer report) → Anyone posts in #incidents with @oncall tag
```

**Immediate actions (first 60 seconds):**
1. Acknowledge PagerDuty alert
2. Join the incident bridge: https://novapay.zoom.us/j/incident-bridge
3. Post in #incidents: `🚨 INCIDENT OPEN | Severity: [TBD] | Bridge: [link] | IC: [your name]`

---

### Step 2 — CLASSIFY (T+1 to T+5 minutes)

**Incident Commander determines severity using this flowchart:**

```
Is UPI/payment processing affected?
  YES → Is failure rate > 50%? → SEV-1
        Is failure rate 10-50%? → SEV-2
  NO  → Are core banking APIs returning errors?
          YES → Affecting > 10% users? → SEV-2
                Affecting < 10% users? → SEV-3
          NO  → Cosmetic / non-functional? → SEV-4
```

**Assign roles:**
- **Incident Commander (IC):** Owns the incident. Usually SRE Lead or senior SRE.
- **Technical Lead:** Leads diagnosis and remediation.
- **Communications Lead:** Handles Slack, status page, and customer comms.
- **Scribe:** Documents timeline in real-time.

---

### Step 3 — CONTAIN (T+5 minutes)

Prevent the incident from getting worse before diagnosing root cause:

```bash
# 3a. If a deployment triggered this → IMMEDIATE ROLLBACK (do not diagnose first)
./scripts/rollback-controller.sh "INCIDENT_CONTAINMENT" "sev2"

# 3b. Freeze all ongoing deployments
# Post in #deployments: "⚠️ DEPLOYMENT FREEZE — Incident in progress — INC-XXXX"
kubectl annotate namespace novapay-prod \
  novapay/deployment-freeze=true \
  novapay/freeze-reason="incident-INC-XXXX"

# 3c. Disable any active canary progression
kubectl annotate virtualservice novapay-vs -n novapay-prod \
  novapay/canary-frozen=true \
  novapay/freeze-reason="incident-INC-XXXX"

# 3d. If database issue suspected — scale down non-critical services to reduce connection pool pressure
# Only if DB pool exhaustion alert is firing:
kubectl scale deployment novapay-analytics --replicas=0 -n novapay-prod

# 3e. Update status page immediately (even before root cause is known)
# Status: "Investigating" — do not delay status page update
```

---

### Step 4 — DIAGNOSE (T+5 to T+20 minutes)

**Structured diagnosis checklist:**

```bash
# D1. Check error rates (last 10 minutes)
curl -sf "http://prometheus:9090/api/v1/query_range" \
  --data-urlencode 'query=rate(http_requests_total{namespace="novapay-prod",status=~"5.."}[1m])/rate(http_requests_total{namespace="novapay-prod"}[1m])' \
  --data-urlencode "start=$(date -d '10 minutes ago' +%s)" \
  --data-urlencode "end=$(date +%s)" \
  --data-urlencode 'step=30'

# D2. Check recent deployments — did this correlate with a deployment?
argocd app history novapay-production --server $ARGOCD_SERVER
kubectl rollout history deployment/novapay-app -n novapay-prod

# D3. Check pod events for clues
kubectl get events -n novapay-prod --sort-by='.lastTimestamp' | tail -30

# D4. Check application logs for errors
kubectl logs -l app=novapay -n novapay-prod --since=10m | grep -E "ERROR|FATAL|Exception" | tail -50

# D5. Check database connectivity
kubectl exec -n novapay-shared deploy/pgbouncer -- pgbouncer -d /etc/pgbouncer/pgbouncer.ini showpools

# D6. Check downstream dependencies (UPI/NPCI status)
curl -sf https://www.npci.org.in/status 2>/dev/null || echo "NPCI status check failed — check manually"

# D7. Check if this is a known pattern (check runbook knowledge base)
# https://wiki.novapay.internal/sre/incident-patterns
```

---

### Step 5 — MITIGATE (T+10 to T+30 minutes)

**Based on root cause, select mitigation:**

| Root Cause | Mitigation Action |
|---|---|
| Bad deployment | Rollback (Section 3a above) |
| DB connection exhaustion | Scale down non-critical services + increase pgBouncer pool size |
| OOM / memory leak | Rolling restart of affected pods: `kubectl rollout restart deploy/novapay-app -n novapay-prod` |
| Downstream dependency (UPI) | Enable circuit breaker + degrade gracefully; post incident update |
| Traffic spike | Scale up: `kubectl scale deployment novapay-app --replicas=8 -n novapay-prod` |
| Configuration drift | Trigger ArgoCD self-heal: `argocd app sync novapay-production --force` |
| SSL certificate expired | Renew cert via cert-manager: `kubectl annotate certificate novapay-tls cert-manager.io/renew=true` |

---

### Step 6 — COMMUNICATE (ongoing throughout incident)

See Section 3 for full communication templates. Key rule: **update stakeholders every 30 minutes for SEV-1, every 60 minutes for SEV-2.** Never go silent.

---

### Step 7 — RESOLVE & REVIEW (T+resolution)

```bash
# 7a. Confirm service fully restored
./scripts/smoke-tests.sh --target "$PROD_URL" --suite production-critical-path
# Expected: 15/15 smoke tests pass

# 7b. Confirm metrics back to baseline
# Error rate < 0.1%
# p99 latency within 10% of 7-day baseline

# 7c. Update status page: "Resolved"
# Include: resolution time, brief description (no technical details for customers)

# 7d. Re-enable deployments
kubectl annotate namespace novapay-prod novapay/deployment-freeze-
echo "Deployment freeze lifted"

# 7e. Raise postmortem ticket in Jira immediately
# Postmortem due: within 48 hours for SEV-2, within 24 hours for SEV-1
```

---

## Part 3: Communication Templates

### Template 1 — Initial Acknowledgement (post within 5 minutes of detection)

**Internal Slack (#incidents):**
```
🚨 INCIDENT DECLARED | INC-[date][seq]

Severity: SEV-[1/2/3]
Status: Investigating
Time detected: [HH:MM IST]
Incident Commander: [Name]

Symptoms: [1-2 sentences describing what is broken]

Customer impact: [Assessed / Assessing]
Affected services: [novapay-api / upi-payments / etc]

Action: Engineering team actively investigating.
Next update: [HH:MM IST] (in 15 minutes)

Bridge: https://novapay.zoom.us/j/incident-bridge
Runbook: https://runbooks.novapay.internal/incident-response
```

**External Status Page (status.novapay.in):**
```
Investigating — We are investigating reports of [service degradation / payment failures].
Our engineering team is working to identify the cause.
Next update by [HH:MM IST].
```

---

### Template 2 — Progress Update (every 30 min for SEV-1, 60 min for SEV-2)

**Internal Slack (#incidents):**
```
📊 INCIDENT UPDATE | INC-[date][seq] | T+[minutes]

Status: [Investigating / Mitigating / Monitoring]
Root cause: [Identified: {description} / Still investigating]
Action taken: [What has been done]

Customer impact: [Quantified if possible: ~X% of transactions affected]
Current error rate: [X%] (target: < 0.1%)

ETA to resolution: [Time estimate or "Unknown"]
Next update: [HH:MM IST]
```

---

### Template 3 — Rollback Notification

**Internal Slack (#incidents):**
```
🔄 ROLLBACK EXECUTED | INC-[date][seq]

Reason: [Category A auto-rollback / Manual rollback due to {reason}]
Rolled back from: [new version tag]
Rolled back to: [stable version tag]
Traffic routing: 100% to stable

Rollback time: [HH:MM:SS IST]
Verification: [Smoke tests passed / In progress]

On-call: [Name] — monitoring recovery
Next update: [HH:MM IST]
```

---

### Template 4 — Resolution Notice

**Internal Slack (#incidents):**
```
✅ INCIDENT RESOLVED | INC-[date][seq]

Resolved at: [HH:MM IST]
Total duration: [X hours Y minutes]

Root cause: [Technical description]
Resolution: [What fixed it]

Customer impact: [Estimated number of affected users / transactions]
SLA impact: [Availability SLA: X% during incident]

Postmortem: Due by [date+48h] | Jira: NOVA-OPS-[ticket]

Thanks to: [Names of responders]
```

---

### Template 5 — RBI Regulatory Notification (if incident > 30 minutes)

```
RBI Technology Incident Report — NovaPay Digital Bank
RBI License: [License number]
Incident Reference: INC-[date][seq]

Incident Summary:
[2-3 sentences describing the incident, impact, and resolution]

Timeline:
- Incident detected: [datetime IST]
- Mitigation initiated: [datetime IST]
- Service restored: [datetime IST]
- Total duration: [minutes]

Customer Impact:
- Number of customers affected: [estimate]
- Transaction failures: [count and amount if quantifiable]

Root Cause: [Technical description]

Preventive Actions: [What will be done to prevent recurrence]

Reporting Officer: [Name, Title]
Date of Report: [date]
```

---

## Part 4: Incident Simulation — Friday 5:07 PM Production Disaster

**Scenario (from Section B5 of assessment):**

> It is Friday at 5:07 PM IST. A developer pushed a "critical hotfix" that bypassed staging. The canary deployment has been running for 8 minutes when these alerts fire simultaneously:
> - ALERT: HTTP 500 error rate at 12% (threshold: 5%) — Severity: CRITICAL
> - ALERT: PostgreSQL connection pool exhaustion on primary — Severity: HIGH  
> - ALERT: Downstream payment gateway timeout rate at 35% — Severity: CRITICAL

### Simulation Response Walkthrough

**17:07:00 IST — Alerts fire simultaneously**

PagerDuty pages on-call SRE. Three alerts correlate:
- `CategoryA_ErrorRateHigh` fires (12% > 5% threshold)
- `CategoryA_DBPoolExhausted` fires (pool > 95%)
- `DownstreamPaymentGatewayTimeout` fires (35% > 20% threshold)

The automated rollback controller fires within 15 seconds for CategoryA triggers.

**17:07:15 IST — Automated rollback executes (Category A)**

```bash
# Rollback controller executes automatically:
kubectl patch virtualservice novapay-vs -n novapay-prod \
  --type merge \
  -p '{"spec":{"http":[{"route":[{"destination":{"host":"novapay-blue"},"weight":100},{"destination":{"host":"novapay-canary"},"weight":0}]}]}}'

# Canary frozen:
kubectl annotate virtualservice novapay-vs -n novapay-prod \
  novapay/canary-frozen=true novapay/freeze-reason="CategoryA_ErrorRateHigh"
```

**17:07:20 IST — On-call SRE acknowledges PagerDuty**

```
[17:07] @channel 🚨 INCIDENT DECLARED | INC-20251219-001

Severity: SEV-1 (payment gateway failures + DB pool exhaustion)
Status: AUTO-ROLLBACK EXECUTING
Time detected: 17:07:00 IST
IC: [SRE name]

Symptoms:
- HTTP 5xx rate: 12% (threshold 5%) — CRITICAL
- PostgreSQL pool exhaustion — HIGH
- Payment gateway timeout: 35% — CRITICAL

Automated rollback: EXECUTING — routing to stable
Next update: 17:12 IST (5 minutes)

Bridge: https://novapay.zoom.us/j/incident-bridge
```

**17:07:30 IST — Traffic restored to stable blue environment**

Rollback completes. Error rate begins dropping.

**17:08:00 IST — IC joins bridge, assigns roles**

```
IC: [SRE Lead]
Tech Lead: [Senior SRE]
Comms: [DevOps Engineer]
Scribe: [On-call engineer]
```

**17:08:30 IST — Diagnosis begins**

```bash
# Check what was deployed
kubectl rollout history deployment/novapay-app -n novapay-prod
# Output shows: hotfix/NOVA-789 was deployed 8 minutes ago via canary

# Check logs of canary pods (now being terminated)
kubectl logs -l version=canary -n novapay-prod --since=10m | grep -E "ERROR|Exception" | head -20
# Shows: "HikariPool-1 - Connection is not available, request timed out after 30000ms"
# Shows: "java.sql.SQLTransientConnectionException: Unable to acquire JDBC Connection"

# Root cause identified: The hotfix introduced an N+1 query in the payment processing path
# Each payment request made 45+ DB queries instead of 3 → pool exhausted under 12% traffic
```

**17:09:00 IST — Root cause confirmed**

```
[17:09] UPDATE: INC-20251219-001

Root cause IDENTIFIED:
Hotfix commit abc1234 introduced N+1 query bug in PaymentProcessor.java
- Each payment request now fires 45+ DB queries (was 3)
- DB connection pool exhausted under canary load (12% traffic = 45x query volume increase)
- Pool exhaustion caused payment gateway timeouts (waiting for DB responses)

Action: Rollback COMPLETE. 100% traffic on stable blue environment.
DB pool recovering. Payment gateway timeouts should clear in 2-3 minutes.

Customer impact: ~35% of UPI transactions failed for 8 minutes
Estimated affected transactions: Calculating...

Next update: 17:15 IST
```

**17:09:30 IST — Verify rollback success**

```bash
./scripts/smoke-tests.sh --target "$PROD_STABLE_URL" --suite production-critical-path
# 15/15 tests pass ✓

# Error rate dropping
# 17:07: 12% → 17:08: 6% → 17:09: 1.2% → 17:10: 0.08% ← within threshold

# DB pool recovering
kubectl exec -n novapay-shared deploy/pgbouncer -- pgbouncer showpools
# sv_active: 12/100 (recovering from 98/100)
```

**17:10:00 IST — Status page updated**

```
Status: Monitoring Recovery
We have identified and resolved the issue affecting UPI payment processing.
Services are recovering. We are monitoring closely.
Customers who experienced payment failures should retry their transactions.
```

**17:12:00 IST — Update comms**

```
[17:12] UPDATE: INC-20251219-001

Status: MONITORING RECOVERY
Error rate: 0.07% (below 0.1% threshold ✓)
DB pool: 15/100 (recovering ✓)
Payment gateway timeouts: 0.2% (recovering ✓)

Rollback was successful. Services are recovering.
No data integrity issues detected.

Customer impact: UPI transactions failed for ~8 minutes
Reconciliation: Payment ops team running reconciliation check now

ETA to full resolution: 5 minutes
Next update: 17:20 IST
```

**17:15:00 IST — Incident resolved**

All metrics back to baseline. Smoke tests green. Payment gateway normal.

```
[17:15] ✅ INCIDENT RESOLVED | INC-20251219-001

Resolved at: 17:15 IST
Total duration: 8 minutes

Root cause: N+1 query bug in hotfix commit abc1234 (PaymentProcessor.java)
Resolution: Automated Category A rollback + revert to stable version

Customer impact: ~35% UPI transactions failed for 8 minutes
Estimated 12,400 failed transactions — reconciliation in progress

SLA impact: 8 minutes at >5% error rate = ~0.056% of monthly availability budget consumed

Postmortem: Due 19:15 IST Sunday | Jira: NOVA-OPS-892

Thanks to: [IC], [Tech Lead], [Comms]
```

### Post-Incident Analysis: Did the Pipeline Prevent This?

**What pipeline gate was bypassed?**

The developer pushed the hotfix to `hotfix/NOVA-789` and it bypassed staging promotion (Stage 5 Integration Testing was skipped via emergency hotfix path). The critical bug was an N+1 query that would have been caught by **performance testing in Stage 5** (p99 latency < 500ms under 2x load gate).

**What prevented it from being worse:**

| Control | Effect |
|---|---|
| Canary at 1% → not bypassed | Only 12% of traffic hit the bug (canary was at 10% phase 2) |
| Category A automated rollback | Rollback in 15 seconds — MTTR 8 minutes vs 4.5 hours baseline |
| DB pool exhaustion alert | Fired simultaneously with error rate alert — correlated root cause faster |
| Smoke tests on canary | Did not catch the N+1 (smoke tests use synthetic low-volume traffic) |

**Improvement actions from this incident:**

1. **NOVA-OPS-893:** Add DB query count assertion to smoke tests (>50 queries per request = fail)
2. **NOVA-OPS-894:** Hotfix path must still run Stage 5 integration test with load test component
3. **NOVA-OPS-895:** Add N+1 query detection rule to SonarQube banking profile
4. **NOVA-OPS-896:** Canary Phase 1 must use real traffic load profile, not just percentage

---

## Part 5: Postmortem Template

```markdown
# Postmortem — INC-[date][seq]

**Date:** [date]
**Severity:** SEV-[1/2/3]
**Duration:** [X minutes]
**Incident Commander:** [Name]
**Document owner:** [Name]
**Review deadline:** [48h from resolution]

## Impact
- Users affected: [count/estimate]
- Transactions failed: [count]
- Revenue impact: [if quantifiable]
- SLA impact: [% availability consumed]
- Regulatory notification required: YES / NO

## Timeline

| Time (IST) | Event |
|---|---|
| [time] | Incident detected |
| [time] | SEV-[n] declared |
| [time] | Root cause identified |
| [time] | Mitigation initiated |
| [time] | Service restored |
| [time] | Incident resolved |

## Root Cause

[Technical description of what caused the incident]

## Contributing Factors

1. [Factor 1 — e.g., insufficient load testing in hotfix path]
2. [Factor 2 — e.g., no N+1 query detection in SAST]
3. [Factor 3 — e.g., staging bypass for hotfixes]

## What Went Well

- [e.g., Automated rollback executed in 15 seconds]
- [e.g., Canary limited blast radius to 10% of users]
- [e.g., Clear escalation path followed correctly]

## What Went Wrong

- [e.g., Hotfix bypassed Stage 5 performance testing]
- [e.g., N+1 query not caught by existing SAST rules]

## Action Items

| # | Action | Owner | Due Date | Priority |
|---|---|---|---|---|
| 1 | Add DB query count to smoke tests | [Engineer] | [date] | HIGH |
| 2 | Hotfix path must include load test | [SRE Lead] | [date] | HIGH |
| 3 | Add N+1 detection to SonarQube | [Security] | [date] | MEDIUM |

## Lessons Learned

[Key takeaways for the engineering team]

---
*Reviewed by: IC, Tech Lead, VP Engineering*
*Sent to: SRE team, Engineering leadership, Compliance (for incidents > 30 minutes)*
```

---

*Cross-reference: [Deployment Runbook](deployment-runbook.md) | [Rollback Spec](../docs/06-rollback-specification/rollback-spec.md) | [Observability](../docs/08-observability/observability.md)*