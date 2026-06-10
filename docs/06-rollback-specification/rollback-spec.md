# Deliverable 6: Automated Rollback Specification
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge

## 1. Purpose

This document defines NovaPay's automated rollback strategy for Kubernetes-based deployments. The objective is to minimize customer impact by detecting faulty releases early and restoring the last known healthy version through automated or controlled rollback mechanisms.

---

# 2. Rollback Objectives

* Recover from failed deployments within target SLAs.
* Maintain zero planned downtime.
* Minimize failed financial transactions.
* Prevent cascading failures across services.
* Preserve data consistency.
* Generate complete audit logs for every rollback event.

---

# 3. Rollback Categories

## Category A – Immediate Automatic Rollback (< 60 Seconds)

These failures require no human intervention.

| Trigger                    | Threshold                            | Detection Method     | Action                      |
| -------------------------- | ------------------------------------ | -------------------- | --------------------------- |
| HTTP 5xx error rate        | > 5% for 2 minutes                   | Prometheus           | Immediate rollback          |
| Canary failure rate        | > 3% above baseline                  | Istio + Prometheus   | Abort rollout               |
| Pod CrashLoopBackOff       | ≥ 3 pods                             | Kubernetes           | Rollback deployment         |
| Readiness probe failures   | > 20% of replicas                    | Kubernetes           | Restore previous ReplicaSet |
| Startup failure            | New pods unavailable after 3 minutes | Kubernetes           | Automatic rollback          |
| Image verification failure | Invalid digest/signature             | Admission controller | Block release               |

Target Recovery Time: **less than 60 seconds**

---

## Category B – Escalated Rollback (< 15 Minutes)

Requires SRE or DevOps review before execution.

| Trigger                | Threshold              | Escalation         |
| ---------------------- | ---------------------- | ------------------ |
| Database latency       | > 300 ms for 5 minutes | SRE Team           |
| CPU utilization        | > 90% cluster-wide     | Platform Team      |
| Memory exhaustion      | > 90% sustained        | DevOps Lead        |
| RabbitMQ queue backlog | > 50,000 messages      | Operations Team    |
| Payment timeout rate   | > 10%                  | Incident Commander |

Target Recovery Time: **under 15 minutes**

---

## Category C – Manual Decision

Human approval is mandatory.

Examples:

* Database schema contract phase rollback
* Security breach investigation
* Regulatory freeze period
* Major infrastructure migration
* Disaster recovery failover
* Suspected data corruption

Approvals required:

* Incident Commander
* DevOps Lead
* DBA (if schema affected)
* Compliance Officer (when applicable)

---

# 4. Eight-Step Rollback Workflow

## Step 1 – Detect

Monitoring systems identify abnormal metrics or failed health checks.

Sources:

* Prometheus
* Alertmanager
* Kubernetes Events
* Grafana Dashboards

---

## Step 2 – Correlate

Combine alerts to eliminate false positives.

Examples:

* Error rate spike
* Increased latency
* Pod failures
* Infrastructure health

Only correlated failures initiate rollback.

---

## Step 3 – Freeze Deployment

Immediately stop:

* Progressive rollout
* Canary expansion
* ArgoCD sync
* Additional production releases

This prevents worsening the incident.

---

## Step 4 – Execute Rollback

Actions:

* Restore previous ReplicaSet
* Redirect traffic to stable version
* Disable feature flags
* Revert service routing

For Blue-Green deployments:
Switch traffic back to Blue.

For Canary deployments:
Return routing to stable deployment.

---

## Step 5 – Verify Recovery

Automatic smoke tests verify:

* Login
* Account lookup
* Balance inquiry
* Payment initiation
* Health endpoint
* Database connectivity

Failures trigger escalation.

---

## Step 6 – Monitor Metrics

Compare:

* Error rate
* Latency
* Throughput
* CPU
* Memory
* Database performance

Metrics should return to baseline before closing the incident.

---

## Step 7 – Notify Stakeholders

Automatically notify:

* DevOps Team
* SRE Team
* Engineering Leadership
* Security Team (if required)
* Compliance Team (if applicable)

Notification includes:

* Incident ID
* Rollback reason
* Deployment version
* Recovery status

---

## Step 8 – Create Incident Record

Generate:

* Timeline
* Root cause
* Trigger metrics
* Rollback duration
* Customer impact
* Lessons learned
* Preventive actions

Store records for audit and postmortem analysis.

---

# 5. Post-Rollback Verification

## Smoke Tests

* Authentication succeeds
* REST APIs respond correctly
* Payment processing operational
* RabbitMQ consumers healthy
* Redis connectivity verified
* PostgreSQL connections normal

---

## Metric Comparison

Compare against pre-deployment baseline:

| Metric            | Acceptance Criteria    |
| ----------------- | ---------------------- |
| HTTP Success Rate | ≥ 99.9%                |
| Error Rate        | < 1%                   |
| p95 Latency       | Within 10% of baseline |
| CPU               | < 70%                  |
| Memory            | < 75%                  |
| Pod Availability  | 100% Ready             |

---

## Customer Impact Assessment

Assess:

* Failed transactions
* User complaints
* Session interruptions
* Payment delays
* Data inconsistencies

If customer impact exists, trigger incident communications and remediation procedures.

---

# 6. Prometheus Alert Examples

```yaml
groups:
- name: rollback-rules
  rules:
    - alert: HighHttpErrorRate
      expr: rate(http_requests_total{status=~"5.."}[2m]) > 0.05
      for: 2m

    - alert: PodCrashLoop
      expr: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 2

    - alert: HighDatabaseLatency
      expr: histogram_quantile(0.95, db_query_duration_seconds_bucket) > 0.3

    - alert: HighCpuUsage
      expr: avg(rate(container_cpu_usage_seconds_total[5m])) > 0.9
```

---

# 7. Deployment Safety Rules

* Rollback automation must remain independent of the deployment workflow.
* Previous container images must always be retained.
* Feature flags should support rapid deactivation.
* Database contract migrations must not begin until rollback is no longer required.
* Every deployment must have a validated rollback path before production approval.

---

# 8. Recovery Targets

| Objective                 | Target                |
| ------------------------- | --------------------- |
| Category A Recovery       | < 60 seconds          |
| Category B Recovery       | < 15 minutes          |
| Rollback Success Rate     | ≥ 99%                 |
| Deployment Verification   | 100% automated        |
| Customer-visible Downtime | Zero planned downtime |

---

# 9. Conclusion

NovaPay’s rollback strategy combines automated monitoring, progressive delivery controls, and structured operational procedures to reduce Mean Time to Recovery (MTTR) while protecting customer transactions. By classifying incidents into automatic, escalated, and manual categories, the platform can respond proportionally to failures and maintain high availability in a regulated banking environment.
