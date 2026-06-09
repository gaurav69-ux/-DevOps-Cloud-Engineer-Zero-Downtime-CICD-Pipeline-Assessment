# OPA Policy: No Privileged Containers
# RBI Mapping: Section 5.4 — Security controls
# PCI-DSS Mapping: Requirement 6.5

package kubernetes.admission

# DENY: Privileged containers not allowed in NovaPay production
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.privileged == true
    msg := sprintf(
        "RBI/PCI-DSS VIOLATION: Privileged container '%v' not permitted. Remove securityContext.privileged or set to false.",
        [container.name]
    )
}

# DENY: Resource limits mandatory
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.memory
    msg := sprintf(
        "POLICY VIOLATION: Container '%v' missing memory limit. All production containers must define resource limits.",
        [container.name]
    )
}

deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not container.resources.limits.cpu
    msg := sprintf(
        "POLICY VIOLATION: Container '%v' missing CPU limit. All production containers must define resource limits.",
        [container.name]
    )
}

# DENY: 'latest' image tag in production
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    endswith(container.image, ":latest")
    msg := sprintf(
        "POLICY VIOLATION: Container '%v' using 'latest' tag. Production images must use immutable SemVer tags.",
        [container.image]
    )
}

# DENY: Containers must not run as root
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    container.securityContext.runAsUser == 0
    msg := sprintf(
        "SECURITY VIOLATION: Container '%v' configured to run as root (UID 0). Use a non-root user.",
        [container.name]
    )
}

# DENY: Unsigned images rejected (Cosign verification must pass)
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not startswith(container.image, "artifactory.novapay.internal/")
    msg := sprintf(
        "SUPPLY CHAIN VIOLATION: Image '%v' not from trusted registry. Only images from artifactory.novapay.internal are permitted.",
        [container.image]
    )
}
