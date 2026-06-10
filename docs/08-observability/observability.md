# Deliverable 8: Observability Strategy & DORA Metrics
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge

## 1. Purpose

This document defines the observability architecture for NovaPay's zero-downtime CI/CD platform. It provides real-time monitoring of application health, infrastructure, deployments, compliance, and business-critical operations to ensure rapid incident detection and regulatory readiness.

---

# 2. Observability Stack

| Component           | Tool                    |
| ------------------- | ----------------------- |
| Metrics Collection  | Prometheus              |
| Visualization       | Grafana                 |
| Log Aggregation     | Grafana Loki            |
| Distributed Tracing | OpenTelemetry + Jaeger  |
| Alert Routing       | Alertmanager            |
| Kubernetes Metrics  | kube-state-metrics      |
| Node Monitoring     | Node Exporter           |
| CI/CD Metrics       | GitHub Actions Exporter |
| SLO Monitoring      | Sloth                   |

---

# 3. Observability Architecture

```
Application Services
        │
        ▼
OpenTelemetry SDK
        │
        ▼
Prometheus ───────► Alertmanager
        │                 │
        │                 ▼
        │           Email / Slack / PagerDuty
        │
        ▼
Grafana Dashboards
        │
        ▼
Engineering │ Management │ Compliance Teams
```

---

# 4. DORA Metrics

NovaPay tracks the four standard DORA metrics.

| Metric                       | Definition                     | Target           |
| ---------------------------- | ------------------------------ | ---------------- |
| Deployment Frequency         | Successful production releases | Multiple per day |
| Lead Time for Changes        | Commit to production           | Under 2 hours    |
| Mean Time to Recovery (MTTR) | Detection to recovery          | Under 15 minutes |
| Change Failure Rate          | Failed deployments             | Less than 5%     |

These metrics are collected automatically from GitHub Actions, ArgoCD, and Kubernetes events.

---

# 5. Pipeline Metrics

## Build Metrics

* Build duration
* Build success rate
* Test execution time
* Code coverage percentage

## Security Metrics

* Critical vulnerabilities detected
* High vulnerabilities detected
* SAST failures
* DAST failures
* Dependency scan failures

## Deployment Metrics

* Deployment duration
* Rollback count
* Deployment success rate
* Canary promotion success
* Blue-Green switch duration

## Infrastructure Metrics

* Kubernetes pod readiness
* Cluster CPU utilization
* Cluster memory utilization
* Disk usage
* Network latency

## Application Metrics

* HTTP request rate
* HTTP 5xx error rate
* API response latency (p95)
* Active sessions
* Database query latency
* Queue depth

## Compliance Metrics

* Policy violations
* Failed admission controls
* Unauthorized deployments
* Audit log completeness

---

# 6. Dashboard 1 – Engineering Operations

Purpose: Real-time operational visibility.

Widgets:

* Service health status
* Active deployments
* Pod readiness
* CPU and memory usage
* API latency
* HTTP error rate
* Deployment history
* Rollback events
* Build pipeline status
* Database performance

Refresh interval: 15 seconds.

Primary audience:

* DevOps Engineers
* SRE Team
* Platform Engineers

---

# 7. Dashboard 2 – Executive Management

Purpose: Weekly and monthly reporting.

Widgets:

* Deployment frequency
* MTTR trend
* Change failure rate
* Lead time trend
* Release success percentage
* Security issues resolved
* Compliance score
* Incident count by severity
* Availability percentage

Refresh interval: Daily.

Primary audience:

* Engineering Managers
* CTO
* Technology Risk Committee

---

# 8. Dashboard 3 – Regulatory & Audit

Purpose: Compliance reporting and audit readiness.

Widgets:

* Deployment approvals
* Compliance gate status
* Policy violations
* Security scan results
* Change history
* Audit log completeness
* Rollback history
* Production change records
* User access review status

Refresh interval: Hourly.

Primary audience:

* Compliance Team
* Internal Audit
* Risk Management

---

# 9. Alert Severity Levels

| Severity | Example Trigger                           | Notification              |
| -------- | ----------------------------------------- | ------------------------- |
| Critical | Production outage, payment failures       | PagerDuty + Slack + Email |
| High     | Error rate > 5%, failed deployment        | Slack + Email             |
| Medium   | High CPU, queue growth                    | Slack                     |
| Low      | Disk nearing capacity, warning thresholds | Dashboard notification    |

---

# 10. Sample Alert Rules

## High Error Rate

```yaml id="k3p9vc"
- alert: HighHttpErrorRate
  expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.05
  for: 2m
```

## Pod Crash Loop

```yaml id="ffjlwm"
- alert: CrashLoopBackOff
  expr: kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"} > 0
```

## High Database Latency

```yaml id="w52ghg"
- alert: DatabaseLatency
  expr: histogram_quantile(0.95, db_query_duration_seconds_bucket) > 0.3
```

---

# 11. Escalation Policy

1. Alert generated by Prometheus.
2. Alertmanager classifies severity.
3. Notification sent to Slack.
4. Critical alerts trigger PagerDuty.
5. Incident Commander assigned.
6. Rollback initiated if deployment-related.
7. Post-incident review scheduled after resolution.

---

# 12. Service Level Objectives (SLOs)

| Service               | Target           |
| --------------------- | ---------------- |
| API Availability      | 99.999%          |
| Payment API Success   | 99.95%           |
| Deployment Success    | 99%              |
| Rollback Recovery     | Under 15 minutes |
| Smoke Test Success    | 100%             |
| Pipeline Availability | 99.9%            |

---

# 13. Log Retention Policy

| Log Type         | Retention |
| ---------------- | --------- |
| Application Logs | 90 days   |
| Security Logs    | 1 year    |
| Audit Logs       | 7 years   |
| Deployment Logs  | 1 year    |
| CI/CD Logs       | 180 days  |

Logs are immutable and centrally stored for audit purposes.

---

# 14. Anomaly Detection

Automated monitoring flags unusual patterns such as:

* Sudden spike in HTTP 5xx responses
* Unexpected increase in deployment failures
* Sharp rise in database latency
* Unusual authentication failures
* Rapid growth in queue backlog
* Significant deviation in resource consumption

Detected anomalies generate alerts for engineering review.

---

# 15. Key Performance Indicators

* Deployment success rate ≥ 99%
* Mean Time to Recovery < 15 minutes
* Lead time from commit to production < 2 hours
* Error rate < 1%
* Availability ≥ 99.999%
* Policy compliance = 100%
* Zero unauthorized production deployments

---

# 16. Conclusion

NovaPay’s observability platform combines metrics, logs, traces, dashboards, and automated alerting to provide comprehensive visibility into application health, infrastructure performance, and deployment reliability. The defined dashboards and metrics support engineering operations, executive reporting, and regulatory compliance while enabling rapid detection and resolution of production issues.
