# Key Concepts

This document describes each technology in the cluster — what it is, why it exists, and how it fits into the overall architecture. It assumes familiarity with containers but not with Kubernetes or the surrounding ecosystem.

---

## Kubernetes Building Blocks

Six primitives underpin all resources in this cluster.

### Pod

The smallest deployable unit. A Pod consists of one or more containers that share a network interface and filesystem mounts. Pods are ephemeral — when they crash or are rescheduled, they are replaced with a new Pod at a new IP address.

### Deployment

Manages a set of identical, stateless Pods. Handles rolling updates, rollbacks, and replica count. A Deployment is the appropriate workload type when every Pod is interchangeable. (Grafana, Prometheus, Envoy Gateway, and most services in this cluster are Deployments.)

### DaemonSet

Runs exactly one Pod on every node. New nodes automatically receive the Pod; removed nodes lose it. A DaemonSet is the appropriate workload type for node-level agents that must run everywhere. (Cilium, Promtail, Tetragon, Falco, and BOINC are all DaemonSets in this cluster.)

### StatefulSet

Manages Pods that require a stable identity and dedicated persistent storage. Each Pod receives a numbered, stable DNS name (`pod-0`, `pod-1`) and its own PersistentVolume. StatefulSets are appropriate for databases and any workload that cannot treat all replicas as identical. (Loki and Prometheus are StatefulSets in this cluster.)

### Namespace

A virtual partition for grouping resources, applying access controls, and scoping policies. Namespaces are not a hard security boundary — Pods in different Namespaces can communicate unless a NetworkPolicy prevents it. This cluster uses approximately 15 Namespaces to separate concerns and target Kyverno policies per-namespace.

### Service

A stable network endpoint that routes traffic to a set of Pods. Pods come and go; the Service IP and DNS name remain constant. Three types are used in this cluster:

- **ClusterIP** — reachable only inside the cluster (default)
- **NodePort** — opens a port on every node, reachable from outside the cluster
- **Headless** (`clusterIP: None`) — DNS returns individual Pod IPs; used by StatefulSets so each replica is directly addressable by name

### Custom Resource Definition (CRD)

A CRD extends the Kubernetes API with a new resource type. Every `HelmRelease`, `Certificate`, `HTTPRoute`, and `ClusterPolicy` in this cluster is a CRD — installed by a Helm chart and managed like any native Kubernetes object. `kubectl get helmreleases -A` works because Flux registered the HelmRelease CRD at bootstrap time.

### PersistentVolume / PersistentVolumeClaim (PV / PVC)

A PVC is a request for storage (size, access mode). A PV is the actual storage that satisfies it. OpenEBS provisions PVs automatically using node-local directories when a PVC is created.

---

## GitOps — Flux

**GitOps** is a deployment model where Git is the single source of truth for what should be running in the cluster. Direct `kubectl apply` commands are not used — changes are committed to Git and a controller reconciles the cluster to match.

**Flux** is the GitOps controller. It polls the repository every minute, compares Git state to cluster state, and applies any difference. Key properties:

- Every change is tracked in Git history — full audit trail
- Drift is auto-corrected — manual `kubectl` edits are reverted on the next reconcile
- Rollback is `git revert` + push

**Reconciliation sequence:**

```
git push
  └─► Flux GitRepository (polls every 1 min, detects new commit)
        └─► Flux Kustomization (runs kustomize build, applies manifests)
              └─► Flux HelmRelease (calls helm upgrade with chart values)
                    └─► Pods running in the cluster
```

`flux get all -A` shows the current reconciliation state of every resource:

| Status | Meaning |
|--------|---------|
| `READY: True` | Cluster matches Git |
| `READY: False` + `RECONCILING` | Flux is actively working |
| `READY: False` + error message | A failure occurred — read the message |

---

## Helm and HelmRelease

**Helm** is a package manager for Kubernetes. A Helm **chart** is a parameterized collection of Kubernetes manifests — analogous to an npm package, but for Kubernetes. Values overrides are passed and Helm renders the final YAML.

A Flux **HelmRelease** is a CRD that instructs Flux to install and manage a Helm chart automatically. Instead of running `helm install` manually, a `HelmRelease` manifest is committed to Git; Flux handles install, upgrade, rollback, and version pinning. All chart overrides in this cluster reside in the `spec.values` block of the relevant `HelmRelease` file.

---

## CNI — Cilium

The **Container Network Interface (CNI)** assigns IP addresses to Pods and routes traffic between them. Without a CNI, every Pod remains `Pending` and nothing can communicate. Cilium is installed before Flux bootstraps so the CNI is live before anything else starts.

**Cilium** is an eBPF-based CNI that also replaces kube-proxy:

- Assigns Pod IPs and routes traffic over a VXLAN tunnel between KinD nodes
- Handles Service load balancing with eBPF programs (faster than iptables)
- Enforces Kubernetes NetworkPolicy
- Runs **Hubble**, a built-in observability layer that shows live traffic flows, dropped packets, and per-service metrics without any application code changes

eBPF programs execute inside the Linux kernel without modifying kernel source. Cilium uses them to intercept and process every network packet at the lowest possible level.

---

## Service Mesh — Istio

A **service mesh** adds a transparent security and observability layer between services. Istio injects a small **Envoy proxy sidecar** container into every application Pod. All traffic between Pods flows through these sidecars — never directly between application containers.

This provides:

- **mTLS** — every connection between Pods is encrypted and mutually authenticated. Both sides present a certificate before any data is exchanged.
- **Request metrics** — every call is measured (latency, error rate, throughput) automatically. Istio Grafana dashboards reflect this without any code changes.
- **Distributed tracing** — request spans are exported to Tempo via the OTel Collector.

**mTLS explained:** Standard TLS authenticates only the server (as with HTTPS in a browser). Mutual TLS also authenticates the caller. In Istio's mesh, every Pod carries a short-lived certificate issued by istiod. When Pod A calls Pod B, both verify each other's certificate. A compromised Pod cannot impersonate another service because it cannot forge that certificate.

In this cluster, Istio is **mesh only** — it handles mTLS between services but does not handle traffic entering from outside the cluster. That responsibility belongs to Envoy Gateway.

---

## Ingress — Envoy Gateway

**Ingress** is the path that gets external HTTP traffic into the cluster. This cluster uses the Kubernetes **Gateway API** (the modern replacement for the older `Ingress` resource).

**Envoy Gateway** implements Gateway API. The operator defines:

- A `Gateway` CR — "listen for HTTP on port 80"
- An `HTTPRoute` CR — "route requests with `Host: grafana.local` to the Grafana Service"

Envoy Gateway auto-provisions an Envoy proxy Deployment and NodePort Service. On KinD on macOS, an nginx DaemonSet handles the host-to-cluster port mapping (see the README for the full explanation).

To expose a new service, create an `HTTPRoute` in its namespace — see the README for the template.

---

## Certificate Management — cert-manager

TLS certificates expire. Manual renewal is error-prone and causes outages. **cert-manager** automates certificate issuance and renewal. It watches `Certificate` CRDs, requests certificates from a configured issuer (self-signed CA, Let's Encrypt, Vault, etc.), stores the result in a Kubernetes Secret, and renews automatically before expiry.

In this cluster, cert-manager is installed as a dependency for Istio's mTLS infrastructure and for future TLS automation needs. The two-phase install (CRDs-only HelmRelease first, controller second) eliminates a race condition where the controller would start before its own API types were registered.

---

## Persistent Storage — OpenEBS

Kubernetes does not manage storage itself — it delegates to a **CSI (Container Storage Interface)** driver. A CSI driver provisions `PersistentVolumes` automatically when a `PersistentVolumeClaim` is created.

**OpenEBS localpv** uses node-local directories under `/var/openebs/local/` as storage. It is fast and simple, but the data is tied to the node on which the Pod runs — if that node is removed, the data is lost with it. This is acceptable for a homelab cluster where durability is not a requirement.

---

## Admission Control — Kyverno

**Admission control** is a webhook that intercepts every object before it reaches the Kubernetes API server. Kyverno enforces policies on Pods, Deployments, and other resources as they are created or updated.

Two enforcement modes:

- **Audit** — violations are recorded in policy reports but the object is allowed through. Used to discover problems without blocking operations.
- **Enforce** — violations are rejected at the API server. The Pod never starts.

This cluster uses both modes. `require-resource-limits` and `disallow-privilege-escalation` are **Enforce** — Pods without CPU/memory limits are rejected at admission. `pod-security-baseline` and `disallow-latest-image-tag` are **Audit** — violations are reported but not blocked, allowing infrastructure components that legitimately require privileged access to run while their configurations are tracked in policy reports.

---

## eBPF Runtime Security — Tetragon

**Tetragon** enforces security policy at the Linux kernel syscall level using eBPF. While Kyverno prevents bad Pods from starting, Tetragon monitors what running Pods actually do. It can:

- Terminate a process that reads a sensitive file
- Block a network connection to a forbidden destination
- Record every `execve` syscall (process launch) across the entire cluster

Events are exported as JSON, collected by Promtail, stored in Loki, and visible in the **Tetragon kubectl exec audit** Grafana dashboard. TracingPolicies that define monitored behaviors reside in `infrastructure/configs/tracingpolicies.yaml`.

---

## Behavioral Detection — Falco

**Falco** also uses eBPF but focuses on detection rather than enforcement. It monitors syscalls and matches them against a library of rules. Suspicious behavior — a container spawning a shell, reading `/etc/shadow`, writing to a binary directory — triggers an alert.

Alerts flow through **Falcosidekick** (bundled as a subchart) directly to Loki, and also appear as Prometheus metrics. The **Falco — Runtime Security** Grafana dashboard shows live alerts and historical rule-match rates.

**Tetragon vs. Falco:** Tetragon enforces — it can terminate processes and block syscalls based on the TracingPolicies defined. Falco detects and alerts across a broad library of built-in rules but does not block. Running both provides hard enforcement on specific behaviors (Tetragon) and broad suspicious-activity logging (Falco).

---

## Compliance Scanning — Kubescape

**Kubescape** continuously audits the cluster's running configuration against industry security frameworks:

- **NSA Kubernetes Hardening Guide** — the US National Security Agency's Kubernetes security baseline
- **MITRE ATT&CK** — maps attacker techniques to misconfigurations (e.g., privilege escalation via hostPath, lateral movement via over-permissioned ServiceAccounts)

Unlike Kyverno (admission-time) and Falco (runtime), Kubescape scans the cluster's current state and produces a scored compliance report. The **Kubescape Security Posture** Grafana dashboard shows control pass/fail rates and trends over time.

Findings that have been reviewed and accepted as intentional are recorded in `docs/kubescape-security.md` with rationale so future readers can confirm the decision was deliberate.

---

## Secrets Encryption — SOPS + Age

**SOPS** (Secrets OPerationS) encrypts Kubernetes Secret manifests before they are committed to Git. **Age** is the encryption backend — a modern replacement for GPG with a simpler key format.

Encrypted values appear as `ENC[AES256_GCM,data:...,type:str]` in the YAML file. Only the `data` and `stringData` fields are encrypted; `kind`, `metadata`, and `apiVersion` remain readable. Flux's `kustomize-controller` decrypts secrets in memory at reconcile time using a private key stored in the cluster as the `sops-age` secret.

See [docs/sops-age-secrets.md](sops-age-secrets.md) for the complete setup guide and day-to-day workflow.

---

## Voluntary Distributed Computing — BOINC

**BOINC** (Berkeley Open Infrastructure for Network Computing) donates idle CPU cycles to scientific research. When the cluster is not under load, BOINC uses spare CPU to run computations and submits results to project servers over the internet.

This cluster participates in:

- **Rosetta@Home** — protein structure prediction for medical research
- **Einstein@Home** — gravitational wave and pulsar detection

BOINC runs as a DaemonSet (one pod per node). It is capped at 1 CPU core to keep peak temperatures below 65°C on the passively cooled MacBook Air M5.

See [docs/boinc.md](boinc.md) for operational details, status commands, and how to update project credentials.

---

## Dependency Automation — Renovate

**Renovate** automatically opens pull requests when new versions of dependencies are available — Helm chart versions, container image tags, GitHub Actions, and CLI tool pins in CI. It reads `renovate.json` at the repository root to determine what to track and how to handle each update type.

The automation is tiered by risk:

| Tier | What | Behavior |
|------|------|----------|
| Patch images | Direct container image tags (exact pins) | Grouped PR, automerged after CI passes (weekdays) |
| Minor Helm | Flux HelmRelease constraint bumps (`1.x → 2.x`) | Grouped PR every Monday, human review required |
| GitHub Actions | Action version bumps | Automerged after CI passes |
| Infra pins | `versions.env` and CI tool versions (Cilium, Istio, Kubescape, etc.) | PR opened, no automerge — these affect bootstrap |

**Why no patch PRs for most HelmReleases?** Most charts use a semver range constraint such as `1.17.x`. Flux resolves and deploys the latest matching chart automatically — there is nothing for Renovate to bump. Renovate opens a PR only when the constraint range itself changes (e.g., `1.17.x → 1.18.x`).

**Automerge safety:** Renovate waits for GitHub branch protection to pass before merging. The `validate` CI workflow (kustomize build + Kyverno tests + Kubescape scan) is a required check. A failing check keeps the PR open regardless of the automerge setting.

---

## Resource Metrics — Metrics Server

**Metrics Server** implements the Kubernetes Resource Metrics API (`metrics.k8s.io/v1beta1`). It is the component that enables `kubectl top nodes` and `kubectl top pods`, and it is required for the Horizontal Pod Autoscaler (HPA) and Vertical Pod Autoscaler (VPA) to function.

Metrics Server is distinct from Prometheus: Prometheus stores long-term time-series data for querying and alerting. Metrics Server holds only a short in-memory window (~15 seconds) of live resource usage, consumed directly by the Kubernetes API server. Both coexist and serve different consumers.

In this cluster, `--kubelet-insecure-tls` is required because KinD kubelet serving certificates are self-signed. In a production cluster this flag would be removed in favour of a proper kubelet CA. Istio sidecar injection is disabled in the `metrics-server` namespace because the API server connects to it without a sidecar, and enabling injection would require per-port exceptions.

---

## Demo Namespace — httpbin and load-generator

The `demo` namespace contains two workloads that exist purely to generate traffic through the Istio mesh:

- **httpbin** (`kennethreitz/httpbin`) — an HTTP echo server that responds to any GET/POST request. It is a traffic target, not a production application.
- **load-generator** (`curlimages/curl`) — sends requests to httpbin every 5 seconds, producing a continuous stream of HTTP metrics across the mesh.

Without this traffic, the Istio Grafana dashboards (Mesh, Service, Workload) display empty graphs. The load-generator ensures those dashboards always contain meaningful data.
