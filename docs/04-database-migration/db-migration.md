# Deliverable 4: Zero-Downtime Database Migration Strategy
**Project:** NovaPay Digital Bank — Zero-Downtime CI/CD Pipeline  
**Author:** Gaurav Durge


## 1. Purpose

This document defines the zero-downtime database migration strategy for NovaPay Digital Bank. The objective is to deploy schema changes without interrupting customer-facing services while maintaining data integrity, backward compatibility, and regulatory compliance.

---

# 2. Environment Overview

| Component        | Technology                       |
| ---------------- | -------------------------------- |
| Application      | Java 21 + Spring Boot 3.x        |
| Database         | PostgreSQL 16                    |
| Connection Pool  | pgBouncer                        |
| Cache            | Redis 7 Cluster                  |
| Message Queue    | RabbitMQ 3.13                    |
| Deployment       | Kubernetes                       |
| CI/CD            | GitHub Actions + ArgoCD          |
| Migration Tool   | Flyway                           |
| Online Migration | pgroll / Expand-Contract Pattern |

---

# 3. Migration Objectives

* Zero production downtime
* Zero data loss
* Backward compatibility between application versions
* Online schema evolution
* Safe rollback at every phase
* Complete audit trail for compliance
* Support deployments with five-nines availability targets

---

# 4. Expand–Contract Migration Pattern

The migration follows four phases.

## Phase 1 – Expand

Introduce new schema elements without affecting existing applications.

Actions:

* Add new tables or columns
* Create indexes concurrently
* Keep legacy schema intact
* Avoid destructive operations

Example:

```sql
ALTER TABLE customers
ADD COLUMN encrypted_email TEXT;

CREATE INDEX CONCURRENTLY idx_customers_encrypted_email
ON customers(encrypted_email);
```

Application Version:

* Existing Version (V1) → Fully functional
* New Version (V2) → Fully compatible

Rollback:

* Simply ignore newly added objects.

---

## Phase 2 – Application Upgrade

Deploy application version V2.

Behavior:

* Reads legacy columns
* Writes to legacy columns
* Supports new schema
* Feature flags disabled by default

Traffic is shifted using Blue-Green or Canary deployment.

---

## Phase 3 – Data Backfill

Historical records are migrated asynchronously.

Strategy:

* Batch Size: 10,000 rows
* Four parallel workers
* Pause 200 ms between batches
* Resume from checkpoints
* Automatic retry on transient failures
* Monitor CPU and replication lag continuously

Validation:

* Row count verification
* SHA/checksum comparison
* Random sampling
* Referential integrity checks

No table locking should occur.

---

## Phase 4 – Dual Write

Application writes to both old and new schema.

Read preference:

1. New column
2. Legacy column (fallback)

Monitoring continues until confidence is established.

---

## Phase 5 – Contract

After successful validation:

* Remove legacy code paths
* Drop obsolete columns
* Remove deprecated indexes
* Update documentation

This phase is irreversible and requires formal approval.

---

# 5. Version Compatibility Matrix

| Application Version | Legacy Schema | Expanded Schema | Contracted Schema |
| ------------------- | ------------- | --------------- | ----------------- |
| V(N-1)              | ✅             | ✅               | ❌                 |
| V(N)                | ✅             | ✅               | ❌                 |
| V(N+1)              | ❌             | ✅               | ✅                 |

Rule:
Never deploy a schema that breaks the immediately previous application version.

---

# 6. Governance Framework

## Required Approvals

* Database Administrator
* DevOps Lead
* Security Team
* Compliance Team
* Change Advisory Board

## Mandatory Checklist

* Backup verified
* Restore test completed
* Rollback plan approved
* Staging migration successful
* Performance benchmark completed
* Security review passed
* Audit ticket generated

---

# 7. Online Migration Tool Selection

## Primary Tool: Flyway

Responsibilities:

* Version-controlled migrations
* Ordered execution
* Auditability

## Online Migration Support: pgroll

Responsibilities:

* Non-blocking schema evolution
* Safe PostgreSQL changes
* Backward compatibility during deployments

---

# 8. Backfill Strategy for 100M+ Records

Backfill jobs execute independently from application traffic.

Process:

1. Read primary key range
2. Process 10,000 records
3. Commit transaction
4. Sleep briefly
5. Continue next batch

Adaptive throttling activates when:

* CPU > 70%
* Replication lag > 5 seconds
* Disk I/O exceeds threshold

Migration automatically pauses until conditions recover.

---

# 9. Rollback Plan

## During Expand

Rollback Time: < 1 minute

Actions:

* Stop deployment
* Ignore newly created schema
* Continue using legacy application

Risk: Minimal

---

## During Application Deployment

Rollback Time: < 5 minutes

Actions:

* Shift traffic to previous deployment
* Disable feature flags
* Maintain expanded schema

Risk: Low

---

## During Backfill

Rollback Time: Immediate

Actions:

* Stop batch workers
* Preserve migrated records
* Resume later if required

Risk: None

---

## During Dual Write

Rollback Time: < 10 minutes

Actions:

* Disable writes to new schema
* Continue legacy writes
* Keep migrated data intact

Risk: Low

---

## During Contract

Rollback is not recommended after destructive schema removal.

Contract execution requires:

* 100% migration completion
* Seven days of stable production monitoring
* Approval from DBA and CAB

---

# 10. Monitoring and Success Criteria

The migration is considered successful only if all of the following hold:

* Zero customer downtime
* Zero failed financial transactions
* No increase in error rate
* Database latency increase below 5%
* Successful smoke tests
* Data validation passes
* Rollback remains available until contract completion

---

# 11. Compliance Controls

Every migration records:

* Migration ID
* Execution timestamp
* Executor identity
* Git commit hash
* Approval reference
* Environment
* Validation status
* Rollback status

Logs are retained for audit purposes.

---

# 12. Best Practices

* Never perform destructive schema changes before application migration.
* Use feature flags for gradual activation.
* Execute migrations first in Development, Staging, and Pre-Production before Production.
* Continuously monitor replication lag, query latency, and error rates.
* Keep rollback procedures tested and documented.

---

# 13. Conclusion

NovaPay adopts the Expand–Contract methodology to achieve zero-downtime schema evolution. By combining backward-compatible changes, controlled backfill, dual-write mechanisms, governance approvals, and continuous monitoring, the platform can safely evolve its database while maintaining service availability and meeting stringent banking reliability expectations.
