# Stage 5: Integration & Contract Testing

**Tool:** Pact + JUnit 5 + k6  
**SLA Target:** < 15 minutes  
**RBI Mapping:** Section 4.2 — Change management  
**PCI-DSS Mapping:** Requirement 6.5 — Change management processes

## Purpose
Verify services integrate correctly and API contracts between NovaPay microservices are not broken.

## Inputs
- Docker image from Stage 2
- Pact contract files from Pact Broker
- Ephemeral Kubernetes namespace
- Test PostgreSQL with Flyway migrations

## Outputs
- Pact verification results
- Integration test results
- Performance baseline metrics (p99 latency)
- API backward compatibility report

## Quality Gates & Thresholds
- Contract tests: 100% pass rate
- Integration tests: 100% pass rate
- p99 latency: < 500ms under 2x prod load
- Breaking API changes: Blocked
- Backward compatibility: Must maintain V(N-1) support

## Failure Mode & Remediation
**On failure:** PR blocked. Contract diff published to PR comment showing exactly which consumer expectations were violated. Developer must fix API or version the endpoint.

## Configuration Reference
See [architecture.md](../architecture.md#stage-5) for full specification.
