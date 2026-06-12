# NovaPay Production Deployment Runbook
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge  
**Standard:** Production-quality — usable by on-call engineer at 3 AM with minimal context  
**Version:** 1.0 | Last reviewed: Day 9

---

## ⚠️ CRITICAL: Read This First

This runbook is for **production deployments only**. Before you do anything:

1. Confirm you are the on-call engineer or Release Manager
2. Confirm it is NOT a blackout window (salary days 1/7/15, month-end 28-31, festivals, peak UPI 10–12 and 17–20 IST)
3. Confirm dual approval has been obtained (Release Manager + SRE Lead both clicked "Approve" in GitHub)
4. Have the rollback procedure (Section 6) open in a separate tab before you start

**Emergency contacts:**
- On-call SRE: PagerDuty schedule → https://novapay.pagerduty.com/schedules
- Release Manager: #releases Slack channel
- CTO escalation: Only for SEV-1 with customer data impact

---

## Part A: Pre-Deployment Checklist

All 8 items must be confirmed before proceeding. Do not skip any item. Each has a verification method.

| # | Check | How to Verify | Owner |
|---|---|---|---|
| 1 | All CI/CD pipeline stages passed | GitHub Actions run shows green ✓ on all jobs | Release Manager |
| 2 | Compliance evidence bundle generated | S3 bucket `novapay-compliance-audit/evidence/$(date +%Y/%m/%d)/` has JSON file for this SHA | Release Manager |
| 3 | RBI compliance gates verified (6 gates) | Evidence bundle JSON `overall_status: "COMPLIANT"` | Compliance |
| 4 | Database migration tested in pre-prod | DBA signed off in Jira ticket (link in PR description) | DBA |
| 5 | Deployment runbook reviewed and current | This document — check version header is current | SRE Lead |
| 6 | CAB approval obtained OR pre-approved change | Change ticket in ServiceNow/Jira status = APPROVED | Release Manager |
| 7 | On-call engineer available and briefed | PagerDuty acknowledgment in #deployments Slack | SRE on-call |
| 8 | Deployment window is NOT blackout | Run: `python3 scripts/check-blackout.py` | Release Manager |

**If any item is NOT confirmed → STOP. Do not deploy.**

---

## Part B: Deployment Execution Procedure

### Step 1: Validate Release Candidate (2 minutes)

```bash
# 1a. Confirm correct image tag
IMAGE_TAG="<from GitHub Actions output>"
echo "Deploying: $IMAGE_TAG"

# 1b. Verify image exists in Artifactory
curl -sf "https://artifactory.novapay.internal/v2/novapay-app/manifests/$IMAGE_TAG" \
  -H "Authorization: Bearer $ARTIFACTORY_TOKEN" | python3 -m json.tool | grep "schemaVersion"

# 1c. Verify Cosign signature on image
cosign verify \
  --certificate-identity "cicd@novapay.in" \
  --certificate-oidc-issuer "https://token.actions.githubusercontent.com" \
  artifactory.novapay.internal/novapay-app:$IMAGE_TAG
echo "✓ Image signature verified"

# 1d. Cross-reference commit SHA in compliance evidence
COMMIT_SHA=$(git rev-parse HEAD)
aws s3 ls s3://novapay-compliance-audit/evidence/ --recursive | grep "$COMMIT_SHA"
echo "✓ Compliance evidence present"
```

**Decision gate:** If any check fails → STOP. Raise issue in #deployments Slack. Do NOT proceed.

---

### Step 2: Verify Production Cluster Health (3 minutes)

```bash
# 2a. Check all nodes are Ready
kubectl get nodes -o wide
# Expected: All STATUS=Ready, no NotReady nodes

# 2b. Check current pod health
kubectl get pods -n novapay-prod
# Expected: All STATUS=Running, READY=n/n for all pods

# 2c. Check Prometheus for baseline error rate
# Run in Grafana or terminal:
curl -sf "http://prometheus.monitoring:9090/api/v1/query" \
  --data-urlencode 'query=rate(http_requests_total{namespace="novapay-prod",status=~"5.."}[5m])/rate(http_requests_total{namespace="novapay-prod"}[5m])' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); r=d['data']['result']; print('Baseline error rate:', r[0]['value'][1] if r else '0')"
# Expected: < 0.001 (0.1%)

# 2d. Check database connection pool
kubectl exec -n novapay-shared deploy/pgbouncer -- pgbouncer -d /etc/pgbouncer/pgbouncer.ini showpools
# Expected: sv_active < sv_max * 0.7

# 2e. Check Redis cluster health
kubectl exec -n novapay-shared redis-0 -- redis-cli cluster info | grep cluster_state
# Expected: cluster_state:ok
```

**Decision gate:** If cluster is unhealthy → delay deployment. Page SRE Lead if degraded state.

---

### Step 3: Apply Database Migration (if required) (variable — check Jira ticket)

**Check:** Does this release include a schema migration?
- Look in PR description for: `db-migration: YES/NO`
- If NO → skip to Step 4

```bash
# 3a. Confirm EXPAND phase only (never CONTRACT in this step)
# The migration phase for this deployment:
MIGRATION_PHASE=$(cat .migration-phase 2>/dev/null || echo "NONE")
echo "Migration phase: $MIGRATION_PHASE"

# 3b. Run EXPAND or MIGRATE phase only
if [ "$MIGRATION_PHASE" = "EXPAND" ] || [ "$MIGRATION_PHASE" = "MIGRATE" ]; then
  # Trigger migration job in Kubernetes
  kubectl apply -f pipeline/db-migration-job.yaml -n novapay-prod
  
  # Wait for completion with timeout
  kubectl wait job/db-migration \
    --for=condition=complete \
    --timeout=1800s \
    -n novapay-prod
  
  echo "✓ Database migration completed"
elif [ "$MIGRATION_PHASE" = "CONTRACT" ]; then
  echo "❌ CONTRACT phase requires separate deployment with extra approvals"
  echo "   This cannot run alongside an application deployment"
  exit 1
fi

# 3c. Verify no rows are broken post-migration
kubectl exec -n novapay-shared deploy/postgresql -- psql -U novapay -c \
  "SELECT COUNT(*) as unmigrated FROM customer_profiles WHERE encrypted_email IS NULL AND email IS NOT NULL;"
# Expected: 0 unmigrated rows (for MIGRATE phase completion)
```

**Decision gate:** If migration fails or shows errors → STOP. Page DBA. Do NOT continue.

---

### Step 4: Deploy New Version (Green Environment) (5 minutes)

```bash
# 4a. Update image tag in GitOps repo
git checkout main
git pull origin main

# Update Helm values for production
sed -i "s|tag:.*|tag: ${IMAGE_TAG}|" pipeline/helm/values-production.yaml
git add pipeline/helm/values-production.yaml
git commit -m "deploy: production release ${IMAGE_TAG} [deploy-$(date +%Y%m%d%H%M)]"
git push origin main

# 4b. ArgoCD syncs automatically from Git — watch progress
argocd app sync novapay-production \
  --server $ARGOCD_SERVER \
  --auth-token $ARGOCD_TOKEN

# 4c. Watch rollout (canary Phase 1: 1% traffic)
kubectl rollout status deployment/novapay-canary -n novapay-prod --timeout=300s

# 4d. Verify all canary pods are healthy and running correct image
kubectl get pods -n novapay-prod -l app=novapay,version=canary \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.containers[0].image}{"\n"}{end}'
# Expected: all pods show correct IMAGE_TAG

# 4e. Version consistency check — CRITICAL (Knight Capital prevention)
./scripts/verify-version-consistency.sh "$IMAGE_TAG" "novapay-prod"
# Expected: "All N pods running target version ✓"
```

**Decision gate:** If pods fail to start or version mismatch → immediate rollback (Section 6). Raise SEV-2.

---

### Step 5: Pre-Traffic Smoke Tests (3 minutes)

Run all 15 critical path tests against the canary pods directly (before routing any customer traffic):

```bash
# 5a. Run smoke test suite against canary pods directly (internal routing, not customer-facing)
./scripts/smoke-tests.sh \
  --target "http://novapay-canary.novapay-prod.svc.cluster.local:8080" \
  --suite production-critical-path

# smoke-tests.sh runs these 15 tests:
# T01: GET /actuator/health → 200 OK
# T02: GET /actuator/health/readiness → 200 UP
# T03: POST /api/v1/auth/login (test credentials) → 200 + JWT token
# T04: GET /api/v1/accounts (with JWT) → 200 + account list
# T05: GET /api/v1/accounts/{id}/balance → 200 + balance
# T06: POST /api/v1/payments/initiate (test payment) → 202 Accepted
# T07: GET /api/v1/payments/{id}/status → 200 + status
# T08: POST /api/v1/upi/pay → 202 Accepted (mock UPI)
# T09: GET /api/v1/transactions → 200 + list
# T10: POST /api/v1/kyc/verify → 200 (mock KYC)
# T11: GET /api/v1/config/version → 200 + {"version":"$IMAGE_TAG"}
# T12: GET /actuator/prometheus → 200 + metrics
# T13: POST /api/v1/auth/logout → 200 OK
# T14: GET /api/v1/beneficiaries → 200 + list
# T15: POST /api/v1/notifications/send → 202 Accepted

echo "All 15 smoke tests must pass before routing customer traffic"
```

**Decision gate:** If any smoke test fails → rollback (Section 6). Do NOT route customer traffic.

---

### Step 6: Progressive Traffic Switch (Canary) (Phase 1: 15 min observation)

```bash
# 6a. Phase 1 — 1% canary traffic
kubectl patch virtualservice novapay-vs -n novapay-prod \
  --type json \
  -p '[
    {"op":"replace","path":"/spec/http/0/route/0/weight","value":99},
    {"op":"replace","path":"/spec/http/0/route/1/weight","value":1}
  ]'

echo "Phase 1 active: 1% traffic to canary. Monitoring for 15 minutes..."
echo "Watch dashboard: https://grafana.novapay.internal/d/canary-analysis"

# 6b. Monitor Phase 1 (15 minutes)
./scripts/monitor-canary.sh --phase 1 --duration 900

# 6c. Phase 2 — 10% (if Phase 1 passes)
kubectl patch virtualservice novapay-vs -n novapay-prod \
  --type json \
  -p '[
    {"op":"replace","path":"/spec/http/0/route/0/weight","value":90},
    {"op":"replace","path":"/spec/http/0/route/1/weight","value":10}
  ]'

echo "Phase 2 active: 10% traffic. Monitoring for 30 minutes..."
./scripts/monitor-canary.sh --phase 2 --duration 1800

# 6d. Full rollout (100%) — if all phases pass
kubectl patch virtualservice novapay-vs -n novapay-prod \
  --type json \
  -p '[
    {"op":"replace","path":"/spec/http/0/route/0/weight","value":0},
    {"op":"replace","path":"/spec/http/0/route/1/weight","value":100}
  ]'

echo "Full rollout complete. 24-hour bake period monitoring begins."
```

**Rollback trigger:** If error rate > 5% for 60s OR p99 latency > 2x baseline at any point → immediate rollback (Section 6).

---

### Step 7: Post-Deployment Verification (15 minutes bake)

```bash
# 7a. Confirm all pods running new version
kubectl get pods -n novapay-prod -l app=novapay \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].image}{"\n"}{end}'

# 7b. Check error rate returning to normal
curl -sf "http://prometheus.monitoring:9090/api/v1/query" \
  --data-urlencode 'query=rate(http_requests_total{namespace="novapay-prod",status=~"5.."}[5m])/rate(http_requests_total{namespace="novapay-prod"}[5m])' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('data',{}).get('result',[]); rate=float(r[0]['value'][1]) if r else 0; print(f'Current error rate: {rate*100:.3f}%'); exit(1 if rate > 0.001 else 0)"

# 7c. Check p99 latency within 10% of baseline
# View in Grafana: https://grafana.novapay.internal/d/api-performance

# 7d. Verify synthetic monitoring is green
# View in Grafana: https://grafana.novapay.internal/d/synthetic-monitoring

echo "✓ Deployment verification complete"
```

---

### Step 8: Finalise Release (5 minutes)

```bash
# 8a. Record deployment in audit log
cat << EOF >> deployment-log.json
{
  "deployment_id": "DEPLOY-$(date +%Y%m%d%H%M)",
  "image_tag": "$IMAGE_TAG",
  "commit_sha": "$(git rev-parse HEAD)",
  "deployed_by": "$USER",
  "approved_by_rm": "<Release Manager name>",
  "approved_by_sre": "<SRE Lead name>",
  "deployment_start": "<timestamp>",
  "deployment_complete": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "production",
  "strategy": "canary",
  "status": "SUCCESS"
}
EOF

# 8b. Tag the release in Git
git tag "release/$(date +%Y%m%d%H%M)-${IMAGE_TAG}" && git push origin --tags

# 8c. Notify stakeholders
# Post in #deployments Slack:
# ✅ Production deployment complete
# Version: $IMAGE_TAG
# Deployed: $(date)
# Approved by: [RM] + [SRE Lead]
# Monitoring: https://grafana.novapay.internal/d/deployment-overview

echo "Deployment finalised. Monitor for 24 hours before marking stable."
```

---

## Part C: Rollback Procedure

### Immediate Rollback (Category A — < 60 seconds)

Triggered automatically by Prometheus alerts. This section is for manual execution if needed:

```bash
# EXECUTE IMMEDIATELY — no approval needed for Category A
# Route 100% traffic back to stable (blue) environment

kubectl patch virtualservice novapay-vs -n novapay-prod \
  --type merge \
  -p '{
    "spec": {
      "http": [{
        "route": [
          {"destination": {"host": "novapay-blue", "port": {"number": 8080}}, "weight": 100},
          {"destination": {"host": "novapay-canary", "port": {"number": 8080}}, "weight": 0}
        ]
      }]
    }
  }'

# Verify rollback
sleep 15
kubectl get pods -n novapay-prod -l app=novapay,color=blue
echo "Verify error rate is recovering..."

# Raise SEV-2 incident
# 1. Go to PagerDuty and trigger SEV-2 manually, OR
# 2. Post in #incidents: "🚨 ROLLBACK EXECUTED — SEV-2 raised — [reason]"
```

### Verify Rollback Success

```bash
# Confirm all traffic on stable
kubectl get virtualservice novapay-vs -n novapay-prod \
  -o jsonpath='{.spec.http[0].route[*].weight}'
# Expected: 100 0 (100% blue, 0% canary)

# Confirm error rate returning to baseline (wait 2 minutes)
curl -sf "http://prometheus.monitoring:9090/api/v1/query" \
  --data-urlencode 'query=rate(http_requests_total{namespace="novapay-prod",status=~"5.."}[2m])/rate(http_requests_total{namespace="novapay-prod"}[2m])' \
  | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('data',{}).get('result',[]); print('Error rate:', r[0]['value'][1] if r else '0')"

# Re-run smoke tests against stable
./scripts/smoke-tests.sh --target "$STABLE_URL" --suite production-critical-path
```

---

## Part D: Quick Reference

### Key URLs
| Resource | URL |
|---|---|
| Grafana Engineering Dashboard | https://grafana.novapay.internal/d/engineering |
| Grafana Canary Analysis | https://grafana.novapay.internal/d/canary-analysis |
| ArgoCD | https://argocd.novapay.internal |
| PagerDuty | https://novapay.pagerduty.com |
| Prometheus | https://prometheus.monitoring.novapay.internal |
| Compliance Evidence | s3://novapay-compliance-audit/evidence/ |
| Pact Broker | https://pact.novapay.internal |

### Key Commands Quick Reference
```bash
# Check pod status
kubectl get pods -n novapay-prod

# Watch live logs
kubectl logs -f deploy/novapay-app -n novapay-prod

# Check VirtualService traffic weights
kubectl get virtualservice novapay-vs -n novapay-prod -o yaml | grep weight

# Force rollback (emergency)
./scripts/rollback-controller.sh "MANUAL_ROLLBACK" "critical"

# Check ArgoCD sync status
argocd app get novapay-production

# Scale up stable environment (if under load after rollback)
kubectl scale deployment novapay-blue --replicas=6 -n novapay-prod
```

### Blackout Calendar Quick Check
```
BLOCKED: 1st, 7th, 15th of month (salary days)
BLOCKED: 28th–31st of month (month-end processing)
BLOCKED: 10:00–12:00 IST daily (peak UPI)
BLOCKED: 17:00–20:00 IST daily (peak UPI)
BLOCKED: Diwali ±3 days, Eid ±2 days, Christmas Dec 24–26, Holi (day of)
BLOCKED: 48 hours after any P1 incident
```

---

*This runbook was last tested on Day 9 of the project. Reviewed and signed off by SRE Lead.*  
*Cross-reference: [Incident Playbook](incident-playbook.md) | [Rollback Spec](../docs/06-rollback-specification/rollback-spec.md)*