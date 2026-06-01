# Kubescape Security Findings — Accepted Risks

This document records Kubescape scan findings that have been reviewed and accepted as intentional design decisions or third-party constraints. Each entry includes the control, the affected resource, and the rationale for acceptance rather than remediation.

---

## Accepted Findings — 2026-05-27

### Finding 1: Secrets Stored in Environment Variables (CIS-4.4.1)

**Control:** Secrets stored in environment variables
**Framework:** CIS Kubernetes Benchmark 4.4.1
**Affected resource:** `Deployment/grafana` in namespace `observability`
**Severity:** Medium

**Description:**
The Grafana Helm chart injects the admin password into the pod as the `GF_SECURITY_ADMIN_PASSWORD` environment variable. This is internal chart behavior triggered by the `adminPassword` values key and cannot be changed without forking the upstream chart.

**Why accepted:**
- The secret is sourced from a Kubernetes `Secret` object (`grafana-admin-secret`) via Flux's `valuesFrom`, not hardcoded in any manifest.
- The password value (`changeme`) is a placeholder credential for a local KinD lab cluster with no external exposure.
- Remediation would require either overriding chart internals (not supported) or switching to a volume-mounted secret approach, which the Grafana chart does not natively support for admin credentials.
- Risk is contained to the `observability` namespace in a non-production environment.

**Acceptable mitigation:** Secret is stored as a Kubernetes `Secret`, not in plaintext in a ConfigMap or YAML. A `ClusterSecurityException` CR may be added to suppress this finding in future scans once the Kubescape operator is fully stable.

---

### Finding 2: Workload Exposed to Internet via Gateway API

**Control:** Exposure to internet via load balancer / Gateway API
**Framework:** NSA Kubernetes Hardening Guide
**Affected resources:** HTTPRoutes in namespace `demo` (httpbin), `observability` (Grafana, Prometheus)
**Severity:** Medium

**Description:**
Kubescape flags workloads whose traffic is routed through a Gateway API `HTTPRoute` as potentially exposed to external networks. The cluster's Envoy Gateway `GatewayClass` has an externally-reachable listener, and HTTPRoutes for Grafana, Prometheus, and the httpbin demo app are attached to it.

**Why accepted:**
- This is intentional. The KinD cluster is accessed from `localhost` only via `extraPortMappings` in the node configuration. There is no actual public IP or cloud load balancer involved.
- The "internet exposure" is limited to `localhost:8080` on the developer's machine — no external network interface is exposed.
- The httpbin deployment exists solely as a demo workload to generate observable traffic through the Istio service mesh.
- Grafana and Prometheus are internal observability tools. Access is restricted to the developer's local machine by the KinD port mapping configuration.

**Acceptable mitigation:** The cluster topology itself (KinD with extraPortMappings to localhost) prevents any real external exposure. A `ClusterSecurityException` CR may be added to suppress this finding in automated scans once the exception API is confirmed stable for this version of the Kubescape operator.
