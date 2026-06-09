# OPA Policy: PCI-DSS v4.0 Compliance Controls
# Maps to: PCI-DSS Requirements 6.2, 6.5, 10.2
# Author: [Your Full Name]

package pcidss.compliance

# PCI-DSS Req 6.5: Insecure direct object references prevented
# All production services must have readiness + liveness probes
deny[msg] {
    input.request.kind.kind == "Deployment"
    container := input.request.object.spec.template.spec.containers[_]
    not container.readinessProbe
    msg := sprintf(
        "PCI-DSS 6.5 VIOLATION: Container '%v' missing readiness probe. Health checks mandatory for production deployments.",
        [container.name]
    )
}

deny[msg] {
    input.request.kind.kind == "Deployment"
    container := input.request.object.spec.template.spec.containers[_]
    not container.livenessProbe
    msg := sprintf(
        "PCI-DSS 6.5 VIOLATION: Container '%v' missing liveness probe. Health monitoring mandatory for production deployments.",
        [container.name]
    )
}

# PCI-DSS Req 10.2: Audit log recording — all pods must have logging sidecar or annotation
deny[msg] {
    input.request.kind.kind == "Pod"
    namespace := input.request.object.metadata.namespace
    namespace == "novapay-prod"
    not input.request.object.metadata.annotations["novapay/audit-log-enabled"]
    msg := sprintf(
        "PCI-DSS 10.2 VIOLATION: Pod '%v' in production namespace missing audit logging annotation. All production pods must enable audit logging.",
        [input.request.object.metadata.name]
    )
}

# PCI-DSS Req 6.2: No images from untrusted sources
deny[msg] {
    input.request.kind.kind == "Pod"
    container := input.request.object.spec.containers[_]
    not startswith(container.image, "artifactory.novapay.internal/")
    not startswith(container.image, "registry.k8s.io/")  # Allow K8s system images
    msg := sprintf(
        "PCI-DSS 6.2 VIOLATION: Container '%v' using image from untrusted source: %v. Only images from approved registries permitted.",
        [container.name, container.image]
    )
}

# PCI-DSS Req 6.5: No host path mounts in production
deny[msg] {
    input.request.kind.kind == "Pod"
    volume := input.request.object.spec.volumes[_]
    volume.hostPath
    input.request.object.metadata.namespace == "novapay-prod"
    msg := sprintf(
        "PCI-DSS 6.5 VIOLATION: HostPath volume '%v' not permitted in production. Use PersistentVolumeClaims.",
        [volume.name]
    )
}
