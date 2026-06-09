# Deliverable 2: Blue-Green & Canary Deployment Strategies
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge

---

## 1. Overview

NovaPay's current deployment process causes unavoidable downtime — production servers are updated via manual SSH with no traffic management, no rollback capability, and no health verification. This document specifies two complementary zero-downtime deployment strategies:

- **Blue-Green** — for major releases requiring atomic, instantaneous traffic switching
- **Canary** — for feature releases requiring progressive, metrics-driven traffic shifting

Both strategies share a common automated rollback framework with three trigger categories, ensuring NovaPay can recover from any production incident in under 15 minutes.

---

## 2. Strategy Selection Guide

| Release Type | Strategy | Rationale |
|---|---|---|
| Major version (breaking changes) | Blue-Green | Atomic switch; instant full rollback available |
| Feature release (backward compatible) | Canary | Gradual exposure; statistical validation before full rollout |
| Security hotfix | Blue-Green (expedited) | Speed critical; full rollback if patch causes regression |
| Database schema change | Canary + Expand-Contract | Schema deployed first; app follows progressively |
| Configuration change (WAF, routing) | Canary (1% only) | Even config changes tested on live traffic before full rollout |

> **Cloudflare Lesson (Case Study 3):** The 2019 Cloudflare outage was caused by a WAF rule deployed globally without canary testing. NovaPay enforces canary for ALL production changes — including configuration, not just application code.

---

## 3. Blue-Green Deployment

### 3.1 Architecture

NovaPay runs two identical production environments in separate Kubernetes namespaces sharing a single database layer:

```
                    ┌─────────────────────────────────┐
                    │     ISTIO VIRTUAL SERVICE        │
                    │   (Single point of control)      │
                    └──────────┬──────────┬────────────┘
                               │          │
                    100% traffic          0% traffic
                    (current live)        (staging new)
                               │          │
              ┌────────────────▼──┐  ┌────▼────────────────┐
              │  novapay-prod-BLUE │  │ novapay-prod-GREEN  │
              │  App v1.2.3       │  │ App v1.3.0          │
              │  3 replicas       │  │ 3 replicas          │
              │  Status: LIVE     │  │ Status: STANDBY     │
              └────────────┬──────┘  └──────┬──────────────┘
                           │                │
                           └───────┬────────┘
                                   │
                    ┌──────────────▼──────────────┐
                    │   novapay-shared namespace   │
                    │   PostgreSQL 16 + pgBouncer  │
                    │   Redis 7 (session store)    │
                    │   RabbitMQ 3.13             │
                    └─────────────────────────────┘
```

### 3.2 Five-Step Traffic Switching Protocol

**Pre-conditions:** All 8 pipeline stages passed. Deployment runbook signed off by SRE Lead. On-call engineer confirmed available.

```
STEP 1: Deploy to idle environment (GREEN)
   └── ArgoCD syncs new image to novapay-prod-green
   └── All pods reach Running state (health checks pass)
   └── Version consistency verified: all pods same SHA
   └── Duration: ~3 minutes

STEP 2: Pre-switch smoke tests on GREEN (internal traffic only)
   └── 15 critical path tests against green service directly
   └── Payment initiation, balance check, UPI transaction, auth
   └── 0 failures required to proceed
   └── Duration: ~2 minutes

STEP 3: Session drain on BLUE
   └── Blue stops accepting NEW connections
   └── In-flight requests allowed to complete
   └── HTTP timeout: 60 seconds for standard requests
   └── Payment settlement jobs: up to 5 minutes drain window
   └── RabbitMQ consumers: graceful shutdown signal sent
   └── Duration: ~1-5 minutes

STEP 4: Atomic traffic switch
   └── Istio VirtualService updated: blue=0%, green=100%
   └── Switch is atomic — no period where both receive traffic
   └── kubectl patch vs/novapay-vs --type merge -p '{"spec":{"http":[{"route":[{"destination":{"host":"novapay-green","port":{"number":8080}},"weight":100}]}]}}'
   └── Duration: < 5 seconds

STEP 5: Post-switch verification (15 minutes bake time)
   └── Prometheus: error rate < 0.1%, p99 latency within 10% of baseline
   └── Synthetic transactions: payment + balance every 30 seconds
   └── If verification passes: OLD environment (blue) becomes new standby
   └── If verification fails: Instant rollback (reverse VirtualService)
   └── Duration: 15 minutes
```

### 3.3 Session Management

Both environments connect to the same Redis 7 cluster for session storage, ensuring users experience no session loss during the switch:

```yaml
# Redis session config — same cluster for blue and green
spring:
  session:
    store-type: redis
    redis:
      namespace: novapay:sessions
  data:
    redis:
      cluster:
        nodes:
          - redis-0.novapay-shared:6379
          - redis-1.novapay-shared:6379
          - redis-2.novapay-shared:6379
      timeout: 5000ms
      lettuce:
        pool:
          max-active: 20
          max-idle: 10
```

### 3.4 Database Compatibility Requirement

Blue-green requires both app versions to operate against the **same database schema simultaneously**:

- During STEP 1–3: BLUE (v1.2.3) and GREEN (v1.3.0) both run against the same DB
- Schema must be backward compatible — GREEN must not use columns/tables not yet in the DB
- This is enforced by the [Expand-Contract migration pattern](../04-database-migration/db-migration.md)
- GREEN deployment is **blocked** if schema migration has not completed the EXPAND phase first

### 3.5 Istio VirtualService Configuration

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: novapay-vs
  namespace: novapay-prod
spec:
  hosts:
    - novapay.internal
    - api.novapay.in
  http:
    - match:
        - headers:
            x-novapay-canary:
              exact: "true"
      route:
        - destination:
            host: novapay-green
            port:
              number: 8080
          weight: 100
    - route:
        # BLUE-GREEN: Change weights atomically
        - destination:
            host: novapay-blue
            port:
              number: 8080
          weight: 100  # Change to 0 during switch
        - destination:
            host: novapay-green
            port:
              number: 8080
          weight: 0    # Change to 100 during switch
```

---

## 4. Canary Deployment

### 4.1 Four-Phase Progression

NovaPay's canary rollout uses four progressive phases, each requiring statistical validation before proceeding:

```
COMMIT → PIPELINE PASSES → DEPLOY
                                │
                    ┌───────────▼───────────┐
                    │   PHASE 1: CANARY     │
                    │   Traffic: 1–2%       │
                    │   Duration: 15 min    │
                    │   Error rate < 0.1%   │
                    │   p99 latency < 200ms │
                    └───────────┬───────────┘
                    Statistical test PASS?
                    YES ──────► NO: Auto-rollback
                                │
                    ┌───────────▼───────────┐
                    │  PHASE 2: EARLY       │
                    │  ADOPTER              │
                    │  Traffic: 5–10%       │
                    │  Duration: 30 min     │
                    │  Error rate < 0.05%   │
                    │  No critical alerts   │
                    └───────────┬───────────┘
                    Statistical test PASS?
                    YES ──────► NO: Auto-rollback
                                │
                    ┌───────────▼───────────┐
                    │  PHASE 3: EXPANSION   │
                    │  Traffic: 25–50%      │
                    │  Duration: 60 min     │
                    │  All SLOs met         │
                    │  No degradation vs    │
                    │  baseline             │
                    └───────────┬───────────┘
                    Statistical test PASS?
                    YES ──────► NO: Auto-rollback
                                │
                    ┌───────────▼───────────┐
                    │  PHASE 4: FULL        │
                    │  ROLLOUT              │
                    │  Traffic: 100%        │
                    │  Duration: 24h bake   │
                    │  Complete SLO         │
                    │  compliance           │
                    └───────────┬───────────┘
                    24h stable? Mark deployment STABLE
```

### 4.2 Phase-by-Phase Specification

| Phase | Traffic % | Duration | Error Rate Threshold | Latency Threshold | Auto-Action |
|---|---|---|---|---|---|
| 1 — Canary | 1–2% | 15 min | < 0.1% | p99 < 200ms | Proceed or auto-rollback |
| 2 — Early Adopter | 5–10% | 30 min | < 0.05% | p99 < 180ms | Proceed or auto-rollback |
| 3 — Expansion | 25–50% | 60 min | < 0.05% | p99 within 5% of baseline | Proceed to full rollout |
| 4 — Full Rollout | 100% | 24h bake | < 0.1% sustained | p99 within 10% of baseline | Mark deployment stable |

### 4.3 Statistical Analysis Engine

Canary promotion decisions are not based on simple threshold checks alone — they use statistical significance testing to prevent false promotions:

**Latency Comparison — Welch's t-test:**
```python
import scipy.stats as stats
import numpy as np

def should_promote_canary(stable_latencies, canary_latencies, alpha=0.05):
    """
    Welch's t-test for latency comparison.
    Returns True if canary is NOT significantly worse than stable.
    Uses 95% confidence interval (alpha=0.05).
    """
    t_stat, p_value = stats.ttest_ind(
        stable_latencies, 
        canary_latencies, 
        equal_var=False  # Welch's (does not assume equal variance)
    )
    
    canary_mean = np.mean(canary_latencies)
    stable_mean = np.mean(stable_latencies)
    
    # Canary is worse AND statistically significant
    if canary_mean > stable_mean and p_value < alpha:
        return False, f"Canary p99 {canary_mean:.0f}ms significantly worse than stable {stable_mean:.0f}ms (p={p_value:.4f})"
    
    return True, f"Canary latency acceptable (p={p_value:.4f})"

# Error rate comparison — Chi-squared test
def error_rate_significant(stable_errors, stable_total, canary_errors, canary_total, alpha=0.05):
    """
    Chi-squared test for error rate proportional differences.
    Returns True if canary error rate is NOT significantly higher.
    """
    contingency = [
        [stable_errors, stable_total - stable_errors],
        [canary_errors, canary_total - canary_errors]
    ]
    chi2, p_value, _, _ = stats.chi2_contingency(contingency)
    
    canary_rate = canary_errors / canary_total if canary_total > 0 else 0
    stable_rate = stable_errors / stable_total if stable_total > 0 else 0
    
    if canary_rate > stable_rate and p_value < alpha:
        return False, f"Canary error rate {canary_rate*100:.2f}% significantly higher than stable {stable_rate*100:.2f}% (p={p_value:.4f})"
    
    return True, f"Error rate within acceptable range (p={p_value:.4f})"
```

**Rolling Baseline:** All comparisons use a rolling 7-day production baseline, not a fixed threshold. This accounts for natural traffic variation (salary days, festivals) and prevents false rollbacks.

### 4.4 Canary Istio Configuration

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: novapay-vs-canary
  namespace: novapay-prod
spec:
  hosts:
    - novapay.internal
  http:
    # Phase 1: 1% canary traffic
    - route:
        - destination:
            host: novapay-stable
            port:
              number: 8080
          weight: 99
        - destination:
            host: novapay-canary
            port:
              number: 8080
          weight: 1
---
# Prometheus rules for canary analysis
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: novapay-canary-analysis
  namespace: novapay-prod
spec:
  groups:
    - name: canary.analysis
      interval: 30s
      rules:
        - alert: CanaryErrorRateHigh
          expr: |
            (
              rate(http_requests_total{deployment="canary",status=~"5.."}[2m])
              /
              rate(http_requests_total{deployment="canary"}[2m])
            ) > 0.001
          for: 2m
          labels:
            severity: critical
            action: rollback
          annotations:
            summary: "Canary error rate {{ $value | humanizePercentage }} exceeds 0.1% threshold"
            runbook: "https://runbooks.novapay.internal/canary-rollback"

        - alert: CanaryLatencyHigh
          expr: |
            histogram_quantile(0.99,
              rate(http_request_duration_seconds_bucket{deployment="canary"}[2m])
            ) > 0.2
          for: 2m
          labels:
            severity: critical
            action: rollback
          annotations:
            summary: "Canary p99 latency {{ $value | humanizeDuration }} exceeds 200ms"
```

### 4.5 Automated Canary Controller Script

```bash
#!/bin/bash
# novapay-canary-controller.sh
# Manages progressive canary traffic shifting with automatic rollback

set -euo pipefail

NAMESPACE="novapay-prod"
APP="novapay-app"
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus.monitoring:9090}"
PHASES=(1 5 25 100)
DURATIONS=(900 1800 3600 86400)  # seconds: 15min, 30min, 1hr, 24hr
ERROR_THRESHOLDS=(0.001 0.0005 0.0005 0.001)
LATENCY_THRESHOLDS=(0.200 0.180 0.180 0.200)  # p99 in seconds

rollback() {
    echo "ROLLBACK TRIGGERED: $1"
    kubectl patch vs novapay-vs -n $NAMESPACE \
        --type merge \
        -p '{"spec":{"http":[{"route":[{"destination":{"host":"novapay-stable"},"weight":100},{"destination":{"host":"novapay-canary"},"weight":0}]}]}}'
    
    # Raise SEV-2 incident
    curl -X POST "$SLACK_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{\"text\":\"🚨 CANARY AUTO-ROLLBACK: $1\nDeployment reverted to stable version.\"}"
    exit 1
}

check_metrics() {
    local phase=$1
    local error_threshold=$2
    local latency_threshold=$3
    
    # Query Prometheus
    ERROR_RATE=$(curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=rate(http_requests_total{deployment=\"canary\",status=~\"5..\"}[2m])/rate(http_requests_total{deployment=\"canary\"}[2m])" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); r=d['data']['result']; print(r[0]['value'][1] if r else '0')")
    
    P99_LATENCY=$(curl -s "$PROMETHEUS_URL/api/v1/query" \
        --data-urlencode "query=histogram_quantile(0.99, rate(http_request_duration_seconds_bucket{deployment=\"canary\"}[2m]))" \
        | python3 -c "import sys,json; d=json.load(sys.stdin); r=d['data']['result']; print(r[0]['value'][1] if r else '0')")
    
    echo "Phase $phase metrics: error_rate=$ERROR_RATE, p99_latency=${P99_LATENCY}s"
    
    python3 -c "
error = float('$ERROR_RATE')
latency = float('$P99_LATENCY')
if error > $error_threshold:
    raise SystemExit(f'Error rate {error*100:.3f}% exceeds {$error_threshold*100:.3f}% threshold')
if latency > $latency_threshold:
    raise SystemExit(f'p99 latency {latency*1000:.0f}ms exceeds {$latency_threshold*1000:.0f}ms threshold')
print('Metrics within thresholds')
" || rollback "Phase $phase metric threshold exceeded: error=$ERROR_RATE, latency=$P99_LATENCY"
}

set_traffic() {
    local canary_weight=$1
    local stable_weight=$((100 - canary_weight))
    echo "Setting traffic: stable=${stable_weight}%, canary=${canary_weight}%"
    kubectl patch vs novapay-vs-canary -n $NAMESPACE \
        --type json \
        -p "[{\"op\":\"replace\",\"path\":\"/spec/http/0/route/0/weight\",\"value\":${stable_weight}},{\"op\":\"replace\",\"path\":\"/spec/http/0/route/1/weight\",\"value\":${canary_weight}}]"
}

# Run progressive canary
for i in "${!PHASES[@]}"; do
    PHASE="${PHASES[$i]}"
    DURATION="${DURATIONS[$i]}"
    ERROR_T="${ERROR_THRESHOLDS[$i]}"
    LATENCY_T="${LATENCY_THRESHOLDS[$i]}"
    
    echo "=== CANARY PHASE $((i+1)): ${PHASE}% traffic for $((DURATION/60)) minutes ==="
    set_traffic $PHASE
    
    # Monitor for duration, checking every 60 seconds
    END=$((SECONDS + DURATION))
    while [ $SECONDS -lt $END ]; do
        check_metrics $PHASE $ERROR_T $LATENCY_T
        sleep 60
    done
    
    echo "Phase $((i+1)) PASSED. Proceeding to next phase."
done

echo "✅ Canary deployment SUCCESSFUL. All phases passed."
```

---

## 5. Automated Rollback Framework

### 5.1 Three Trigger Categories

#### Category A — Immediate Rollback (< 60 seconds, zero human intervention)

| Trigger | Threshold | Detection Method |
|---|---|---|
| HTTP 5xx error rate | > 5% sustained for 60s | Prometheus `rate(http_requests_total{status=~"5.."}[1m])` |
| Health check failure | 3 consecutive failures | Kubernetes liveness probe |
| OOM kills | Any OOM kill detected | `kube_pod_container_status_last_terminated_reason == "OOMKilled"` |
| CrashLoopBackOff | Pod in CrashLoopBackOff | `kube_pod_container_status_waiting_reason == "CrashLoopBackOff"` |
| DB connection exhaustion | pgBouncer pool > 95% | `pgbouncer_pools_server_active_connections / pgbouncer_pools_server_max_connections > 0.95` |
| Version mismatch detected | Any pod running wrong SHA | Post-deploy version consistency check script |

**Action:** Istio VirtualService patched to route 100% traffic back to stable. No human required.

#### Category B — Escalated Rollback (< 15 minutes, alert on-call)

| Trigger | Threshold | Escalation |
|---|---|---|
| Latency degradation | p99 > 2x baseline sustained 5 min | Page on-call SRE; auto-rollback if no response in 10 min |
| Error budget burn | > 10x normal burn rate for 10 min | Page on-call + VP Eng |
| Transaction success rate | Drops > 2% below 7-day baseline | Page on-call SRE |
| Resource saturation | CPU > 90% OR memory > 85% sustained 5 min | Page on-call; auto-rollback if sustained 10 min |

**Action:** PagerDuty alert fired. On-call SRE has 10 minutes to assess and take action. If no acknowledgement, automated rollback executes.

#### Category C — Manual Decision Required

| Trigger | Indicator |
|---|---|
| Gradual performance degradation | Below thresholds but trending negatively |
| Customer support escalation | Reports from helpdesk indicating degraded UX |
| Downstream dependency correlation | Partner API errors correlated with deployment |
| Retroactive compliance failure | Post-deploy audit finding |

**Action:** SRE on-call receives Slack alert with deployment context. Human decision required within defined SLA.

### 5.2 Rollback Execution Workflow (8 Steps)

```
T+0s   DETECT    ─── Prometheus alert fires OR health check fails
          │
T+15s  CORRELATE ─── Automated correlation: is this deployment-related?
          │              Compare: error rate before vs after deploy timestamp
          │
T+20s  FREEZE    ─── Stop canary progression immediately (if applicable)
          │              Halt any pending phase transitions
          │
T+30s  ROLLBACK  ─── Execute traffic revert (Category A: automatic)
          │              Blue-green: VirtualService weight 100/0 restored
          │              Canary: VirtualService weight 100/0 restored
          │
T+45s  VERIFY    ─── Confirm error rate returning to baseline
          │              Smoke tests against stable version
          │
T+60s  NOTIFY    ─── Slack #incidents: automated rollback notification
          │              PagerDuty: SEV-2 incident auto-raised
          │              Status page: "Investigating" set automatically
          │
T+2min INCIDENT  ─── On-call SRE acknowledges SEV-2
          │              Incident commander assigned
          │
T+48h  POSTMORTEM─── 5-whys analysis required
                       Pipeline gate gap identified
                       Improvement action tracked in Jira
```

### 5.3 Prometheus Alerting Rules for Rollback

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: novapay-rollback-triggers
  namespace: novapay-prod
spec:
  groups:
    - name: rollback.category-a
      interval: 15s
      rules:
        - alert: CategoryA_HighErrorRate
          expr: |
            rate(http_requests_total{namespace="novapay-prod",status=~"5.."}[1m])
            / rate(http_requests_total{namespace="novapay-prod"}[1m]) > 0.05
          for: 1m
          labels:
            severity: critical
            rollback_category: A
            action: immediate_rollback
          annotations:
            summary: "CATEGORY A: Error rate {{ $value | humanizePercentage }} > 5%"
            description: "Triggering immediate automated rollback. No human action required."

        - alert: CategoryA_HealthCheckFailing
          expr: kube_pod_container_status_ready{namespace="novapay-prod"} == 0
          for: 3m
          labels:
            severity: critical
            rollback_category: A
            action: immediate_rollback
          annotations:
            summary: "CATEGORY A: Pod {{ $labels.pod }} health check failing"

    - name: rollback.category-b
      interval: 30s
      rules:
        - alert: CategoryB_LatencyDegradation
          expr: |
            histogram_quantile(0.99,
              rate(http_request_duration_seconds_bucket{namespace="novapay-prod"}[5m])
            )
            >
            2 * histogram_quantile(0.99,
              rate(http_request_duration_seconds_bucket{namespace="novapay-prod"}[7d] offset 5m)
            )
          for: 5m
          labels:
            severity: high
            rollback_category: B
            action: page_oncall
          annotations:
            summary: "CATEGORY B: p99 latency 2x above 7-day baseline"
            description: "Auto-rollback in 10 min if no on-call acknowledgement."
```

---

## 6. Deployment Blackout Calendar

NovaPay deployments are **blocked** during the following windows (enforced in Stage 1 pipeline gate):

| Window | Dates/Times | Reason |
|---|---|---|
| Salary days | 1st, 7th, 15th of month (09:00–21:00 IST) | 3–5x normal transaction volume |
| Month-end processing | 28th–31st of month (all day) | Batch settlement jobs running |
| Diwali | ±3 days around festival (all day) | Peak retail banking |
| Eid | ±2 days (all day) | Peak retail banking |
| Christmas | Dec 24–26 (all day) | Peak retail banking |
| Holi | Day of festival (all day) | Peak retail banking |
| RBI settlement windows | RTGS/NEFT settlement hours | Critical payment infrastructure |
| Peak UPI hours | 10:00–12:00, 17:00–20:00 IST (daily) | NPCI Technical Decline Rate monitoring |
| Post-major-incident | 48 hours after P1 incident | System stability monitoring period |

> **SBI YONO Lesson (Case Study 4):** Repeated outages were caused partly by deployments overlapping with predictable high-traffic windows. NovaPay's blackout calendar is codified in the pipeline, not in a wiki.

---

## 7. Knight Capital Prevention Controls

The 2012 Knight Capital disaster ($440M loss in 45 minutes) was caused by a manual deployment missing one server. NovaPay prevents this pattern through:

| Knight Capital Gap | NovaPay Control |
|---|---|
| Manual server-by-server deployment | ArgoCD GitOps — all pods updated atomically |
| No deployment verification | Version consistency check: all pods must match target SHA |
| 45-minute detection time | Category A rollback in < 60 seconds |
| No canary — blast radius was 100% | Canary starts at 1-2% — blast radius minimised |
| Dead code with unintended behaviour | SAST custom rules scan for dead code paths |
| No feature flags | Feature flags toggled per environment; dead paths disabled |

---

## 8. Cross-References

| Topic | See Also |
|---|---|
| Database backward compatibility | [Deliverable 4: DB Migration](../04-database-migration/db-migration.md) |
| Pipeline stages triggering deployment | [Deliverable 1: Pipeline Architecture](../01-pipeline-architecture/architecture.md#stage-8-deployment--verification) |
| Rollback trigger thresholds | [Deliverable 6: Rollback Specification](../06-rollback-specification/rollback-spec.md) |
| Prometheus metrics definitions | [Deliverable 8: Observability](../08-observability/observability.md) |
| On-call response procedures | [Incident Playbook](../../runbooks/incident-playbook.md) |
| Blackout calendar enforcement | [Stage 1 — Source Control](../01-pipeline-architecture/stage-details/stage-01-source-control-trigger.md) |

---