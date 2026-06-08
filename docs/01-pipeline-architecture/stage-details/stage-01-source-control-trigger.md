# Stage 1: Source Control & Trigger

**Tool:** GitHub Enterprise  
**SLA Target:** < 30 seconds  
**RBI Mapping:** Section 4.3 — Segregation of duties  
**PCI-DSS Mapping:** Requirement 6.5 — Change management

## Purpose
Enforce code integrity at the entry point. Every commit is verified, signed, and traceable.

## Inputs
- Developer git push or pull request
- GPG/SSH signed commit
- Branch: feature/*, hotfix/*, release/*

## Outputs
- Webhook trigger to GitHub Actions
- Commit metadata (SHA, author, timestamp)
- Branch protection verification result

## Quality Gates & Thresholds
- Signed commit: REQUIRED — unsigned commits rejected
- Branch protection: Direct push to  = blocked
- Minimum reviewers: 1 (cannot be commit author)
- GPG/SSH key: Must match registered developer key

## Failure Mode & Remediation
**On failure:** PR blocked with descriptive status check message. Developer notified via GitHub notification and Slack . No escalation required — developer self-serves.

## Configuration Reference
See [architecture.md](../architecture.md#stage-1) for full specification.
