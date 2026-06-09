# OPA Policy: RBI IT Risk Management Compliance
# Maps to: RBI Master Direction on IT Governance, Risk, Controls and Assurance Practices
# Sections: 4.2, 4.3, 5.4, 6.1

package rbi.compliance

# RBI Section 5.4: Encryption of data in transit
# All services must enforce TLS 1.3 minimum
deny[msg] {
    input.kind == "Ingress"
    annotation := input.metadata.annotations["nginx.ingress.kubernetes.io/ssl-protocols"]
    contains(annotation, "TLSv1.1")
    msg := "RBI Section 5.4 VIOLATION: TLS 1.1 detected. Minimum required version is TLS 1.3."
}

deny[msg] {
    input.kind == "Ingress"
    annotation := input.metadata.annotations["nginx.ingress.kubernetes.io/ssl-protocols"]
    contains(annotation, "TLSv1.2")
    msg := "RBI Section 5.4 WARNING: TLS 1.2 detected. NovaPay policy requires TLS 1.3 minimum."
}

# RBI Section 6.1: Audit logging mandatory for all pods
deny[msg] {
    input.kind == "Pod"
    not input.metadata.labels["novapay/audit-logging"]
    msg := sprintf(
        "RBI Section 6.1 VIOLATION: Pod '%v' missing audit logging label. All production pods must enable audit logging.",
        [input.metadata.name]
    )
}

# RBI Section 4.3: Segregation of duties — namespace isolation
deny[msg] {
    input.kind == "RoleBinding"
    input.metadata.namespace == "novapay-prod"
    subject := input.subjects[_]
    subject.kind == "ServiceAccount"
    contains(input.roleRef.name, "admin")
    not contains(subject.name, "sre-")
    msg := sprintf(
        "RBI Section 4.3 VIOLATION: Non-SRE service account '%v' bound to admin role in production namespace.",
        [subject.name]
    )
}
