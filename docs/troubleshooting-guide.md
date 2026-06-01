# Troubleshooting Guide

Cluster: `flux-kind` · KinD 1.35.0 · 1 control-plane + 2 workers
Stack: Flux CD · Cilium 1.17 · Hubble · cert-manager 1.17 · OpenEBS 4.2 · Istio 1.26 (mesh only) · Gateway API v1.2.1 · Envoy Gateway 1.4 · Tetragon 1.7 · Kyverno 3 · Kubescape 1.40 · Falco 8 · kube-prometheus-stack 72 · Grafana 8 · Grafana Tempo 1 · OpenTelemetry Collector 0 · SOPS + Age

---

## Table of Contents

0. [Flux reconciliation quick reference](#0-flux-reconciliation-quick-reference)
1. [Quick cluster health check](#1-quick-cluster-health-check)
2. [Accessing service UIs](#2-accessing-service-uis)
3. [Flux CD](#3-flux-cd)
4. [Cilium](#4-cilium)
5. [Hubble](#5-hubble)
6. [cert-manager](#6-cert-manager)
7. [OpenEBS](#7-openebs)
8. [Istio](#8-istio)
9. [Envoy Gateway](#9-envoy-gateway)
10. [Loki and Promtail](#10-loki-and-promtail)
11. [Tetragon](#11-tetragon)
12. [Kyverno](#12-kyverno)
13. [Falco](#13-falco)
14. [Prometheus](#14-prometheus)
15. [Grafana](#15-grafana)
16. [Flux GitHub notifications](#16-flux-github-notifications)
17. [Grafana Tempo](#17-grafana-tempo)
18. [OpenTelemetry Collector](#18-opentelemetry-collector)
19. [Kubescape](#19-kubescape)
20. [SOPS + Age](#20-sops--age)
21. [Common issues](#21-common-issues)

---

## 0. Flux reconciliation quick reference

```bash
# Re-fetch latest git source immediately (do this first after a push)
flux reconcile source git flux-system -n flux-system

# Re-fetch source + re-apply all kustomizations in one shot
flux reconcile source git flux-system -n flux-system && \
  flux reconcile kustomization flux-system --with-source -n flux-system

# Force reconcile a single HelmRelease
flux reconcile helmrelease <name> -n flux-system

# Force reconcile all HelmReleases in flux-system
flux get helmreleases -n flux-system --no-header | \
  awk '{print $1}' | \
  xargs -I {} flux reconcile helmrelease {} -n flux-system
```

---

## 1. Quick cluster health check

Run these first. If everything is green here, proceed to the per-technology sections.

```bash
# All pods across all namespaces — look for anything not Running/Completed
kubectl get pods -A

# All Flux resources — every source, helmrelease, kustomization
flux get all -A

# Node status and kernel version
kubectl get nodes -o wide
```

Expected output: all pods `Running` or `Completed`, all Flux resources `READY: True`, all nodes `Ready`.

---

## 2. Accessing service UIs

Grafana and Prometheus are exposed via Kubernetes Gateway API HTTPRoutes through Envoy Gateway. All other services still use `kubectl port-forward`.

Traffic path: `localhost:8080 → KinD extraPortMapping (containerPort 8888) → nginx nodeport-proxy (hostNetwork, port 8888) → envoy-proxy ClusterIP (envoy-gateway-system) → Envoy proxy → HTTPRoute → backend service`

### Prerequisite — /etc/hosts (one-time)

```bash
echo "127.0.0.1 grafana.local prometheus.local" | sudo tee -a /etc/hosts
```

### Quick reference

| UI | Access method | Local URL | Credentials |
|---|---|---|---|
| Grafana | Gateway API HTTPRoute | `http://grafana.local:8080` | admin / changeme |
| Prometheus | Gateway API HTTPRoute | `http://prometheus.local:8080` | none |
| Alertmanager | kubectl port-forward | `http://localhost:9093` | none |
| Hubble UI | kubectl port-forward | `http://localhost:12000` | none |

### Grafana

Direct browser access — no port-forward needed:

```text
http://grafana.local:8080
Username: admin
Password: changeme  (set in apps/base/grafana/helmrelease.yaml)
```

Pre-provisioned dashboards — navigate to **Dashboards** after login:

| Dashboard | Source |
|---|---|
| Node Exporter Full (home dashboard) | gnetId 1860 |
| Cilium Agent | gnetId 16611 |
| Cilium Operator | gnetId 16612 |
| Hubble | gnetId 16613 |
| Istio Control Plane | gnetId 7639 |
| Istio Mesh | gnetId 7636 |
| Istio Service | gnetId 7630 |
| Istio Workload | gnetId 7645 |
| cert-manager | gnetId 20842 |
| Kyverno | ConfigMap (gnetId 15804, patched) |
| Flux Cluster Stats | ConfigMap (flux2-monitoring-example) |
| Flux Control Plane | ConfigMap (flux2-monitoring-example) |
| Tetragon kubectl exec audit | ConfigMap (gnetId 20189, patched) — Loki datasource |
| Falco — Runtime Security | ConfigMap (Prometheus + Loki datasources) |
| Kubescape Security Posture | ConfigMap (Prometheus datasource) |
| OpenTelemetry Collector | ConfigMap (gnetId 15983, patched) |

### Prometheus

Direct browser access — no port-forward needed:

```text
http://prometheus.local:8080
Useful pages: Status > Targets (scrape health), Graph (ad-hoc queries)
```

### Alertmanager

```bash
kubectl port-forward -n observability svc/observability-kube-prometheus-alertmanager 9093:9093
# Open: http://localhost:9093
```

### Hubble UI

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Open: http://localhost:12000
# Shows live service map and per-namespace flow visualisation
```

Alternatively, the Cilium CLI handles the port-forward automatically:

```bash
cilium hubble ui
```

### Gateway and HTTPRoute health

```bash
# Gateway should show PROGRAMMED: True
kubectl get gateway -n envoy-ingress

# HTTPRoutes should show ACCEPTED: True
kubectl get httproute -A

# Detailed status on a specific route
kubectl get httproute grafana -n observability -o jsonpath='{.status.parents}' | python3 -m json.tool

# Envoy proxy pod — should be 1/1 Running
kubectl get pods -n envoy-ingress

# NodePort Service — confirm nodePort is 30080
kubectl get svc -n envoy-ingress
```

---

## 3. Flux CD

### Flux status

```bash
# Overall reconciliation state
flux get all -A

# Sources only (GitRepository, HelmRepository, HelmChart)
flux get sources all -A

# Kustomizations
flux get kustomizations -A

# HelmReleases
flux get helmreleases -A
```

### Flux logs

```bash
# All controllers at once
flux logs

# Filter to a specific controller kind
flux logs --kind=HelmRelease
flux logs --kind=Kustomization
flux logs --kind=GitRepository
```

### Force reconciliation

```bash
# Force Flux to re-pull git and reconcile everything
flux reconcile source git flux-system -n flux-system

# Force a specific kustomization
flux reconcile kustomization infrastructure-controllers -n flux-system
flux reconcile kustomization apps -n flux-system

# Force a specific HelmRelease (add --with-source to also re-pull the chart)
flux reconcile helmrelease cilium -n flux-system --with-source
```

### Inspect a failing HelmRelease

```bash
kubectl describe helmrelease <name> -n flux-system | grep -A 30 "Status:"
```

---

## 4. Cilium

### Cilium status

```bash
# High-level CNI health
cilium status --wait

# Per-node agent detail
kubectl exec -n kube-system ds/cilium -- cilium-dbg status

# All Cilium pods — every node should have a Running cilium agent and cilium-envoy
kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium -o wide
```

### Connectivity test

```bash
# Full mesh connectivity test — deploys test pods, runs ~50 checks, cleans up
cilium connectivity test
```

### kube-proxy replacement

```bash
# Confirm Cilium is handling kube-proxy duties
kubectl exec -n kube-system ds/cilium -- cilium-dbg status | grep -i "kube-proxy"
# Expected: KubeProxyReplacement: True
```

### Network policy

```bash
# List all CiliumNetworkPolicies in the cluster
kubectl get ciliumnetworkpolicies -A
kubectl get ciliumclusterwidenetworkpolicies
```

### Cilium logs

```bash
# Agent logs for a specific node
kubectl logs -n kube-system -l k8s-app=cilium --prefix | tail -50

# Operator logs
kubectl logs -n kube-system deploy/cilium-operator | tail -50
```

---

## 5. Hubble

### Hubble status

```bash
# Relay and UI pods
kubectl get pods -n kube-system -l app.kubernetes.io/name=hubble-relay
kubectl get pods -n kube-system -l app.kubernetes.io/name=hubble-ui

# Hubble relay health via CLI
hubble status
# If the above fails, port-forward first:
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &
hubble status --server localhost:4245
```

### Observe live traffic

```bash
# Port-forward if hubble CLI isn't already connected
kubectl port-forward -n kube-system svc/hubble-relay 4245:80 &

# Watch all flows cluster-wide
hubble observe --server localhost:4245

# Filter to a namespace
hubble observe --server localhost:4245 --namespace istio-test

# Show only dropped packets
hubble observe --server localhost:4245 --verdict DROPPED
```

### Hubble UI port-forward

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Open: http://localhost:12000
```

---

## 6. cert-manager

### cert-manager status

```bash
# All cert-manager pods (controller, cainjector, webhook)
kubectl get pods -n cert-manager

# API readiness check
cmctl check api
# Install cmctl if needed: brew install cmctl
```

### End-to-end certificate issuance test

```bash
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned-test
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: cm-test-cert
  namespace: default
spec:
  secretName: cm-test-cert-tls
  issuerRef:
    name: selfsigned-test
    kind: ClusterIssuer
  dnsNames:
    - example.local
EOF

# Wait for issuance — Ready=True confirms the full controller/webhook/cainjector path worked
kubectl wait --for=condition=Ready certificate/cm-test-cert -n default --timeout=60s
kubectl get certificate cm-test-cert -n default
kubectl get secret cm-test-cert-tls -n default   # must contain tls.crt and tls.key

# Clean up
kubectl delete certificate cm-test-cert -n default
kubectl delete secret cm-test-cert-tls -n default
kubectl delete clusterissuer selfsigned-test
```

### Inspect a failing certificate

```bash
kubectl describe certificate <name> -n <namespace>
kubectl describe certificaterequest -n <namespace>
kubectl describe order -n <namespace>           # ACME only
kubectl describe challenge -n <namespace>       # ACME only
```

### cert-manager logs

```bash
kubectl logs -n cert-manager deploy/cert-manager-cert-manager | tail -50
kubectl logs -n cert-manager deploy/cert-manager-cert-manager-cainjector | tail -50
kubectl logs -n cert-manager deploy/cert-manager-cert-manager-webhook | tail -50
```

---

## 7. OpenEBS

### OpenEBS status

```bash
# Provisioner pod
kubectl get pods -n openebs

# StorageClass — openebs-hostpath should be the default (marked with "(default)")
kubectl get storageclass
```

### End-to-end storage test

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: openebs-test-pvc
  namespace: default
spec:
  storageClassName: openebs-hostpath
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 100Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: openebs-test-pod
  namespace: default
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: busybox
      command: [sh, -c, "echo 'OpenEBS works!' > /data/test.txt && cat /data/test.txt"]
      volumeMounts:
        - mountPath: /data
          name: storage
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: openebs-test-pvc
EOF

kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/openebs-test-pvc -n default --timeout=60s
kubectl wait --for=condition=Ready pod/openebs-test-pod -n default --timeout=60s
kubectl logs openebs-test-pod -n default   # expected: "OpenEBS works!"

# Clean up
kubectl delete pod openebs-test-pod -n default
kubectl delete pvc openebs-test-pvc -n default
```

### OpenEBS logs

```bash
kubectl logs -n openebs deploy/openebs-openebs-localpv-provisioner | tail -50
```

---

## 8. Istio

### Istio status

```bash
# Mesh-wide config analysis — reports misconfigurations, missing labels, port naming issues
istioctl analyze --all-namespaces
# What it catches:
# Mismatched mTLS policies, broken HTTPRoute/VirtualService destinations,
# missing sidecar injection webhooks, or gateways referencing non-existent secrets.

# Confirm istiod is synced with all Envoy proxies (sidecars + auto-provisioned gateway)
istioctl proxy-status

# Check Sidecar and Mesh Readiness (experimental precheck)
istioctl experimental precheck
```

### Ingress connectivity test (Envoy Gateway)

```bash
# Quick end-to-end check without /etc/hosts (use Host header)
curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.local" http://localhost:8080/
# Expected: 302 (Grafana login redirect)

curl -s -o /dev/null -w "%{http_code}" -H "Host: prometheus.local" http://localhost:8080/
# Expected: 200 (Prometheus UI)

# Envoy proxy readiness endpoint
curl -s http://localhost:8080/healthz/ready
```

### mTLS functional test

```bash
# Create a namespace with sidecar injection enabled
kubectl create namespace istio-test
kubectl label namespace istio-test istio-injection=enabled

# Deploy client (sleep) and server (httpbin)
kubectl apply -n istio-test -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/sleep/sleep.yaml
kubectl apply -n istio-test -f https://raw.githubusercontent.com/istio/istio/release-1.26/samples/httpbin/httpbin.yaml

# Wait for 2/2 — the /2 confirms the Envoy sidecar was injected
kubectl wait --for=condition=ready pod -l app=sleep -n istio-test --timeout=90s
kubectl wait --for=condition=ready pod -l app=httpbin -n istio-test --timeout=90s
kubectl get pods -n istio-test

# Send a request through the mesh
kubectl exec -n istio-test deploy/sleep -- curl -s http://httpbin.istio-test:8000/get | head -20

# Confirm mTLS: the x-forwarded-client-cert header is added by Envoy only on mutual TLS connections
kubectl exec -n istio-test deploy/sleep -- \
  curl -s http://httpbin.istio-test:8000/headers | grep -i "x-forwarded-client-cert"

# Inspect the TLS mode Envoy is using for the httpbin upstream
istioctl proxy-config cluster -n istio-test deploy/sleep | grep httpbin

# Clean up
kubectl delete namespace istio-test
```

### Sidecar proxy debugging

```bash
# Inspect all listeners on a pod's Envoy proxy
istioctl proxy-config listener <pod-name> -n <namespace>

# Inspect routes
istioctl proxy-config route <pod-name> -n <namespace>

# Inspect TLS config for an upstream cluster
istioctl proxy-config cluster <pod-name> -n <namespace> --fqdn <service>.<namespace>.svc.cluster.local

# Full Envoy config dump
istioctl proxy-config all <pod-name> -n <namespace>
```

### Grafana dashboards blank after Mac wakes from sleep — mTLS cert expiry

**Symptom:** All Grafana dashboards show:
```
upstream connect error or disconnect/reset before headers. retried and the latest reset reason:
remote connection failure, transport failure reason: TLS_error:|268435581:SSL routines:
OPENSSL_internal:CERTIFICATE_VERIFY_FAILED
```

**Cause:** Docker Desktop pauses the Linux VM when the Mac sleeps. Istio issues 24-hour workload certificates to each Envoy sidecar and rotates them at the 80% mark (~19 h). If the VM is frozen through that window, the rotation goroutine never fires. Once the cert expires, Istio does not auto-renew it — the sidecar continues presenting an expired cert until the pod is restarted.

**Verify:**

```bash
# VALID CERT: false confirms the cert has expired
istioctl proxy-config secret -n observability deploy/observability-grafana | grep default
```

**Fix — restart all sidecar-injected pods (takes ~60 s):**

```bash
kubectl rollout restart deployment statefulset -n observability
kubectl rollout restart deployment -n demo
```

**Confirm certs are fresh:**

```bash
istioctl proxy-config secret -n observability deploy/observability-grafana | grep default
# VALID CERT should now be: true
```

### Istio logs

```bash
kubectl logs -n istio-system deploy/istiod | tail -50
```

OR

```bash
kubectl logs -n istio-system deploy/istiod | \
  egrep -i '(error|debug|trace)' | \
  grep -v "retry count: [1-4]" | \
  grep -v "webhook is not ready"
```

---

## 9. Envoy Gateway

### Envoy Gateway status

```bash
# Controller pod — should be Running in envoy-gateway-system
kubectl get pods -n envoy-gateway-system

# GatewayClass eg — defined in apps/base/envoy-gateway/gateway.yaml, ACCEPTED: True means EG is ready
kubectl get gatewayclass eg

# Gateway in envoy-ingress — PROGRAMMED: True means the data-plane is provisioned
kubectl get gateway -n envoy-ingress -o wide

# Auto-provisioned Envoy proxy pod — EG v1.4.x provisions in envoy-gateway-system
kubectl get pods -n envoy-gateway-system -l app.kubernetes.io/component=proxy

# Auto-provisioned NodePort Service — check nodePort is 30080
kubectl get svc -n envoy-ingress

# Stable ClusterIP Service used by nginx nodeport-proxy
kubectl get svc envoy-proxy -n envoy-gateway-system
```

### HTTPRoute attachment

```bash
# All HTTPRoutes — ACCEPTED column must be True
kubectl get httproute -A

# Detailed attachment status (Accepted + ResolvedRefs conditions)
kubectl get httproute grafana -n observability \
  -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool

kubectl get httproute prometheus -n observability \
  -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool
```

### End-to-end connectivity test

```bash
# Quick check without /etc/hosts (use Host header directly)
curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.local" http://localhost:8080/
# Expected: 302 (Grafana login redirect)

curl -s -o /dev/null -w "%{http_code}" -H "Host: prometheus.local" http://localhost:8080/
# Expected: 200

# Envoy proxy readiness endpoint
curl -s http://localhost:8080/healthz/ready
# Expected: 200 OK
```

### Envoy Gateway logs

```bash
# Controller logs
kubectl logs -n envoy-gateway-system deploy/envoy-gateway | tail -50

# Data-plane Envoy proxy logs (auto-provisioned pod — lives in envoy-gateway-system)
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/component=proxy | tail -50
```

### EnvoyProxy CR status

```bash
# Check if the EnvoyProxy CR is accepted by the controller
kubectl describe envoyproxy kindconfig -n envoy-ingress
```

### Adding a new service via HTTPRoute

Create an `HTTPRoute` in the service's namespace:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-namespace
spec:
  parentRefs:
    - name: main
      namespace: envoy-ingress
      sectionName: http
  hostnames:
    - "my-app.local"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /
      backendRefs:
        - name: my-service
          port: 8080
```

Then add `127.0.0.1 my-app.local` to `/etc/hosts`.

---

## 10. Loki and Promtail

### Status

```bash
# Loki StatefulSet — should be 1/1 Running
kubectl get pods -n observability -l app.kubernetes.io/name=loki

# Promtail DaemonSet — one pod per node (including control-plane)
kubectl get pods -n observability -l app.kubernetes.io/name=promtail -o wide

# Loki PVC — should be Bound
kubectl get pvc -n observability -l app.kubernetes.io/name=loki
```

### Verify Loki is ingesting logs

```bash
# Port-forward Loki directly
kubectl port-forward -n observability svc/observability-loki 3100:3100 &

# Query the last 5 minutes of Tetragon security events
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="tetragon", container="export-stdout"}' \
  --data-urlencode 'start=-5m' | jq '.data.result[].values | length'

# List all log streams Loki knows about
curl -s 'http://localhost:3100/loki/api/v1/labels' | jq .
```

### Promtail is shipping logs

```bash
# Check Promtail targets — each entry should show "ready"
kubectl port-forward -n observability \
  $(kubectl get pod -n observability -l app.kubernetes.io/name=promtail -o jsonpath='{.items[0].metadata.name}') \
  3101:3101 &
curl -s http://localhost:3101/targets | python3 -m json.tool | grep -c '"health":"up"'
```

### Query Tetragon events in Grafana

Open `http://grafana.local:8080`, go to **Explore**, select **Loki** datasource, then run:

```logql
{namespace="tetragon", container="export-stdout"}
```

Filter to `kubectl exec` events only:

```logql
{namespace="tetragon", container="export-stdout"} |= "PROCESS_EXEC" |= "kubectl"
```

The pre-provisioned **Tetragon kubectl exec audit** dashboard (ID 20189) shows this automatically.

### Logs

```bash
kubectl logs -n observability -l app.kubernetes.io/name=loki | tail -50
kubectl logs -n observability -l app.kubernetes.io/name=promtail | tail -50
```

---

## 11. Tetragon

### Tetragon status

```bash
# DaemonSet — one pod per node, all should be Running
kubectl get pods -n tetragon -o wide

# Operator pod
kubectl get pods -n tetragon -l app.kubernetes.io/name=tetragon-operator

# Confirm custom TracingPolicies are loaded (shell-exec-detection, sensitive-file-access)
kubectl get tracingpolicies
# Expected: shell-exec-detection and sensitive-file-access both ENABLED=true

# Verify shell-exec-detection fires (exec a shell in any pod and check logs)
kubectl exec -n demo deploy/httpbin -- /bin/sh -c "echo test" 2>/dev/null || true
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c export-stdout --tail=20 \
  | grep -i "process_kprobe\|shell\|execve" | head -5

# Verify sensitive-file-access fires (read /etc/shadow)
kubectl exec -n demo deploy/httpbin -- cat /etc/shadow 2>/dev/null || true
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c export-stdout --tail=20 \
  | grep -i "shadow\|openat" | head -5
```

### View security events

Tetragon exports events as JSON to stdout on the `export-stdout` container:

```bash
# Stream live events from all nodes
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c export-stdout -f

# Show recent events (last 50 lines)
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c export-stdout --tail=50

# Filter to process_exec events only (process launches)
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c export-stdout \
  | grep '"type":"PROCESS_EXEC"' | head -20
```

### Verify Prometheus metrics are being scraped

```bash
# Port-forward Prometheus (see §14), then query:
curl -s 'http://localhost:9090/api/v1/query?query=tetragon_events_total' | jq '.data.result'

# Confirm scrape targets are healthy
curl -s http://localhost:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.labels.job | test("tetragon")) | {job: .labels.job, health: .health}]'
```

### Tetragon logs

```bash
kubectl logs -n tetragon -l app.kubernetes.io/name=tetragon -c tetragon | tail -50
kubectl logs -n tetragon deploy/tetragon-operator | tail -50
```

---

## 12. Kyverno

### Kyverno status

```bash
# All four controllers — admission, background, cleanup, reports
kubectl get pods -n kyverno

# ClusterPolicies — READY: True, BACKGROUND: True for all five
# Validation policies: pod-security-baseline, disallow-latest-image-tag,
#   require-resource-limits (Enforce), disallow-privilege-escalation (Enforce)
# Mutation policy: mutate-jobs-disable-istio-injection (apps/base/kyverno/mutations.yaml)
kubectl get clusterpolicies
```

### View policy violations

Violations are in Audit mode — they are recorded but do not block requests:

```bash
# All cluster-wide policy reports
kubectl get clusteradmissionreports -A

# Detailed violations for a specific report
kubectl describe clusteradmissionreport <name> -n <namespace>

# Count violations by policy across the cluster
kubectl get clusteradmissionreports -A -o json \
  | jq '[.items[].spec.summary.fail] | add'
```

### Run policy unit tests

Offline — no cluster required. Tests all four validation ClusterPolicies against 9 representative pods (45 tests) and the mutation policy against 3 Job/Deployment fixtures (3 tests):

```bash
# Via Make (runs kyverno test under the hood):
make test-policies
# Requires: brew install kyverno

# Or run directly to see the full per-test table:
kyverno test apps/base/kyverno/tests/
```

Expected output: `48 tests passed and 0 tests failed`.

The direct `kyverno test` invocation is useful when iterating on policy changes — it prints a table showing every resource, which rule evaluated it, and whether the result matched the assertion (pass / fail / skip / excluded). The `make` wrapper is convenient for CI and quick smoke-checks.

Test layout:
- `apps/base/kyverno/tests/kyverno-test.yaml` — 45 tests across the four validation ClusterPolicies
- `apps/base/kyverno/tests/mutations/kyverno-test.yaml` — 3 tests for `mutate-jobs-disable-istio-injection`

### Kyverno logs

```bash
# Admission controller — most relevant for debugging policy decisions
kubectl logs -n kyverno deploy/kyverno-admission-controller | tail -50

# Background controller — handles existing resources
kubectl logs -n kyverno deploy/kyverno-background-controller | tail -50
```

---

## 13. Falco

### Falco status

```bash
# DaemonSet — one pod per node
kubectl get pods -n falco -o wide

# Falcosidekick (alert routing to Loki)
kubectl get pods -n falco -l app.kubernetes.io/name=falcosidekick

# Confirm modern_ebpf driver loaded (no kernel module, no init container)
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=5
# Expected: "Driver loaded: modern_ebpf" in the startup lines
```

### View recent alerts

```bash
# Stream live Falco alerts from all nodes
kubectl logs -n falco -l app.kubernetes.io/name=falco -f

# Recent alerts (last 50 lines)
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50

# Filter to critical/error priority only
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=200 \
  | grep -i 'Critical\|Error'
```

### Query Falco alerts in Grafana

Open `http://grafana.local:8080`, navigate to **Dashboards → Falco — Runtime Security**.

Or query Loki directly in **Explore**:

```logql
{namespace="falco", container="falco"}
```

Filter to a specific priority:

```logql
{namespace="falco", container="falco"} |= "Critical"
```

### Verify Falco metrics in Prometheus

```bash
# Port-forward Prometheus (see §14), then query:
curl -s 'http://localhost:9090/api/v1/query?query=falco_rules_matches_total' | jq '.data.result'

# Confirm scrape target is healthy
curl -s http://localhost:9090/api/v1/targets \
  | jq '[.data.activeTargets[] | select(.labels.job | test("falco")) | {job: .labels.job, health: .health}]'
```

### Live detection test

Requires: running cluster with Falco healthy.

```bash
make test-falco
```

This deploys `falcosecurity/event-generator:0.13.0` as a Job that fires the syscall action suite, then checks the Falco pod log on the same node for 4 expected rule matches. Cleans up the `falco-test` namespace on completion.

### Falco logs

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco | tail -50
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick | tail -50
```

---

## 14. Prometheus

### Prometheus status

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=prometheus
kubectl get pods -n observability -l app.kubernetes.io/name=kube-prometheus-stack-operator
```

### Prometheus UI

Direct browser access via Gateway API — no port-forward needed:

```text
http://prometheus.local:8080
```

Or via port-forward for direct API access:

```bash
kubectl port-forward -n observability svc/observability-kube-prometh-prometheus 9090:9090
# Open: http://localhost:9090
```

### Verify Cilium metrics are being scraped

```bash
# Port-forward first (see above), then query:
curl -s 'http://localhost:9090/api/v1/query?query=cilium_version' | jq '.data.result'
curl -s 'http://localhost:9090/api/v1/query?query=hubble_flows_processed_total' | jq '.data.result'

# Check scrape targets — Cilium should appear under Status > Targets in the UI
curl -s http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job | test("cilium")) | {job: .labels.job, health: .health}'
```

### Check scrape job health

```bash
# All configured scrape jobs and their status
curl -s http://localhost:9090/api/v1/targets | jq '[.data.activeTargets[] | {job: .labels.job, health: .health, lastError: .lastError}] | group_by(.health)'
```

### Verify OTel Collector self-metrics are being scraped

```bash
# Port-forward first (see above), then:
curl -s 'http://localhost:9090/api/v1/targets' \
  | python3 -c "import json,sys; [print(t['scrapeUrl'], t['health']) \
    for t in json.load(sys.stdin)['data']['activeTargets'] \
    if 'opentelemetry' in str(t['labels'])]"

# Or query a known OTel self-metric
curl -s 'http://localhost:9090/api/v1/query?query=otelcol_receiver_accepted_spans_total' \
  | jq '.data.result'
```

### Prometheus logs

```bash
kubectl logs -n observability -l app.kubernetes.io/name=prometheus --container=prometheus | tail -50
```

---

## 15. Grafana

### Grafana UI

Direct browser access via Gateway API — no port-forward needed:

```text
http://grafana.local:8080
Username: admin
Password: changeme  (set via adminPassword in apps/base/grafana/helmrelease.yaml)
```

Or via port-forward for API access:

```bash
kubectl port-forward -n observability svc/observability-grafana 3000:80
# Open: http://localhost:3000
```

### Grafana status

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=grafana
```

### Verify dashboards loaded

After opening the UI, navigate to **Dashboards** and confirm these 16 are present. Nine are downloaded from grafana.com at pod startup (requires internet access); seven are loaded from a ConfigMap and are always available offline.

| Dashboard | Source |
|---|---|
| Node Exporter Full (home dashboard) | gnetId 1860 — grafana.com |
| Cilium Agent | gnetId 16611 — grafana.com |
| Cilium Operator | gnetId 16612 — grafana.com |
| Hubble | gnetId 16613 — grafana.com |
| Istio Control Plane | gnetId 7639 — grafana.com |
| Istio Mesh | gnetId 7636 — grafana.com |
| Istio Service | gnetId 7630 — grafana.com |
| Istio Workload | gnetId 7645 — grafana.com |
| cert-manager | gnetId 20842 — grafana.com |
| Kyverno | ConfigMap — apps/base/grafana/dashboards/ (gnetId 15804, patched) |
| Flux Cluster Stats | ConfigMap — apps/base/grafana/dashboards/ |
| Flux Control Plane | ConfigMap — apps/base/grafana/dashboards/ |
| Tetragon kubectl exec audit | ConfigMap — apps/base/grafana/dashboards/ (Loki datasource) |
| Falco — Runtime Security | ConfigMap — apps/base/grafana/dashboards/ (Prometheus + Loki datasources) |
| Kubescape Security Posture | ConfigMap — apps/base/grafana/dashboards/ (Prometheus datasource) |
| OpenTelemetry Collector | ConfigMap — apps/base/grafana/dashboards/ (gnetId 15983, patched) |

### Verify Prometheus datasource

```bash
# Test the datasource via Grafana's API
kubectl port-forward -n observability svc/observability-grafana 3000:80 &
curl -s -u admin:changeme http://localhost:3000/api/datasources | jq '.[].name'
curl -s -u admin:changeme 'http://localhost:3000/api/datasources/proxy/1/api/v1/query?query=up' | jq '.status'
```

### Grafana logs

```bash
kubectl logs -n observability deploy/observability-grafana -c grafana | tail -50
```

---

## 16. Flux GitHub notifications

Flux posts commit status checks to GitHub via the notification controller. The Provider and Alerts live in `apps/base/notifications/`; the `github-token` secret is created by the bootstrap script (step 9).

### Check notification controller health

```bash
# Notification controller pod
kubectl get pods -n flux-system -l app=notification-controller

# Provider status — should show READY: True
kubectl get provider -n flux-system github

# Alert status — both should show READY: True
kubectl get alert -n flux-system
```

### Verify the github-token secret exists

```bash
kubectl get secret github-token -n flux-system
# If missing, re-run:
GITHUB_TOKEN="$(gh auth token)" kubectl create secret generic github-token \
  --namespace flux-system \
  --from-literal=token="${GITHUB_TOKEN}"
```

### Notification controller logs

```bash
kubectl logs -n flux-system deploy/notification-controller | tail -30

# Look for successful dispatches — event references the source commit SHA
kubectl logs -n flux-system deploy/notification-controller | grep -i "dispatching"

# Look for errors (missing secret, invalid token, etc.)
kubectl logs -n flux-system deploy/notification-controller | grep -i "error"
```

### Confirm commit statuses appear on GitHub

```bash
# After a reconcile, check the commit SHA for pending/success/failure statuses
gh api repos/DevOpsMaestro/flux-cluster/commits/$(git rev-parse HEAD)/statuses \
  | jq '.[0:3] | .[] | {state: .state, context: .context, updated_at: .updated_at}'
```

The token must have `repo:status` scope. `gh auth token` provides this scope automatically when authenticated via `gh auth login --scopes repo`.

---

## 17. Grafana Tempo

### Tempo status

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=tempo
kubectl get helmrelease tempo -n flux-system
```

### Tempo health check

```bash
kubectl port-forward -n observability svc/observability-tempo 3200:3200 &
curl -s http://localhost:3200/ready   # expects: ready
```

### Query traces via Tempo API

```bash
# List recent traces by service name
curl -s 'http://localhost:3200/api/search?tags=service.name%3Dhttpbin.demo' | python3 -m json.tool | head -40

# Total trace count (sanity check — should be > 0 after load-generator runs)
curl -s 'http://localhost:3200/api/search?limit=5' | jq '.traces | length'
```

### Verify Grafana Tempo datasource

```bash
kubectl port-forward -n observability svc/observability-grafana 3000:80 &
curl -s -u admin:changeme http://localhost:3000/api/datasources \
  | jq '.[] | select(.type=="tempo") | {name, url}'
# url should be: http://observability-tempo.observability.svc.cluster.local:3200
```

### Tempo logs

```bash
kubectl logs -n observability -l app.kubernetes.io/name=tempo --tail=50
```

---

## 18. OpenTelemetry Collector

### OTel Collector status

```bash
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector
kubectl get helmrelease opentelemetry-collector -n flux-system
```

### Verify spans are flowing in

```bash
# Port-forward Prometheus first (see §14), then:
curl -s 'http://localhost:9090/api/v1/query?query=otelcol_receiver_accepted_spans_total' \
  | jq '.data.result'
# Non-zero value confirms Envoy sidecars are delivering spans
```

### Verify spans are exported to Tempo

```bash
curl -s 'http://localhost:9090/api/v1/query?query=otelcol_exporter_sent_spans_total' \
  | jq '.data.result'
```

### OTel Collector logs

```bash
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector --tail=50
```

### Rendered pipeline config

```bash
kubectl get configmap -n observability \
  -l app.kubernetes.io/name=opentelemetry-collector -o yaml | grep -A 80 "config.yaml:"
```

### Envoy cluster stats — confirm sidecars are connecting

```bash
# exec into a demo pod and check the OTel exporter cluster
kubectl exec -n demo deploy/httpbin -c istio-proxy -- \
  curl -s http://localhost:15000/clusters | grep opentelemetry
# Look for cx_active > 0 and rq_success > 0
```

---

## 19. Kubescape

### Kubescape status

```bash
kubectl get pods -n kubescape
kubectl get helmrelease kubescape -n flux-system
```

### Run a manual scan

```bash
# Live cluster scan via Make (NSA + MITRE frameworks)
make test-kubescape

# Or run directly against the current context
kubescape scan framework nsa,mitre \
  --cluster-context "kind-flux-kind" \
  --format pretty-printer \
  --verbose
```

### View scan results in Grafana

Open `http://grafana.local:8080`, navigate to **Dashboards → Kubescape Security Posture**. The dashboard shows compliance scores for NSA and MITRE controls, resource-level findings, and historical trends sourced from the in-cluster Prometheus metrics that the kubescape `prometheus-exporter` pod exposes.

### Review accepted risk decisions

Controls that have been reviewed and deliberately accepted are recorded in `docs/kubescape-security.md` with the control ID, affected resource, and rationale. Check there before investigating a finding — it may already be a known accepted risk.

### Kubescape logs

```bash
# Main scanner
kubectl logs -n kubescape deploy/kubescape | tail -50

# Operator (manages scheduling and config)
kubectl logs -n kubescape deploy/operator | tail -50

# Prometheus exporter (exposes metrics to Prometheus)
kubectl logs -n kubescape deploy/prometheus-exporter | tail -50
```

---

## 20. SOPS + Age

See `docs/sops-age-secrets.md` for the complete setup guide, day-to-day workflow, and cluster rebuild procedure.

### Verify the sops-age secret is present

```bash
kubectl get secret sops-age -n flux-system
# If missing: make sops-load-key
```

### Verify Flux decrypted a secret successfully

```bash
# grafana-admin-secret is the reference encrypted secret in this project
kubectl get secret grafana-admin-secret -n flux-system
kubectl get secret grafana-admin-secret -n flux-system \
  -o jsonpath='{.data.admin-user}' | base64 -d
kubectl get secret grafana-admin-secret -n flux-system \
  -o jsonpath='{.data.admin-password}' | base64 -d
```

### Diagnose a decryption failure

If a Kustomization is stuck with a decryption error:

```bash
# Check the apps Kustomization status
flux get kustomization apps -n flux-system
kubectl describe kustomization apps -n flux-system | grep -A 10 "Status:"

# Confirm the sops-age secret contains a valid age key
kubectl get secret sops-age -n flux-system \
  -o jsonpath='{.data.age\.agekey}' | base64 -d | head -3
# Expected first line: "# created: ..."
# Expected second line: "# public key: age1..."
```

### Edit an existing encrypted secret

```bash
# Opens decrypted YAML in $EDITOR — re-encrypts automatically on save
sops apps/base/grafana/admin-secret.yaml
```

### Common issue: sops encrypt fails with GPG keyring error

A leftover `SOPS_PGP_FP` environment variable overrides `.sops.yaml` and forces SOPS to use a GPG key that no longer exists in the keyring.

```bash
# Confirm this is the cause
echo $SOPS_PGP_FP   # non-empty output means this is the issue

# Fix for the current session
unset SOPS_PGP_FP

# Fix permanently
sed -i '' '/SOPS_PGP_FP/d' ~/.zshrc
```

---

## 21. Common issues

### All Grafana dashboards blank after Mac wakes from sleep

**Symptom:** Every dashboard panel shows a TLS error mentioning `CERTIFICATE_VERIFY_FAILED`.
**Cause:** Docker Desktop's Linux VM pauses during Mac sleep, freezing Istio's cert-rotation goroutine. Workload certs are valid for 24 h; if the rotation window is missed the sidecar presents an expired cert until the pod restarts.
**Fix:**

```bash
kubectl rollout restart deployment statefulset -n observability
kubectl rollout restart deployment -n demo
```

See [§8 Istio — Grafana dashboards blank after Mac wakes from sleep](#8-istio) for full diagnosis steps and verification commands.

---

### Cilium agent fails to start on worker nodes

**Symptom:** `config` init container loops with `connection refused` to `127.0.0.1:6443`.
**Cause:** `k8sServiceHost: 127.0.0.1` only resolves to the API server on the control-plane node. Workers have no API server on localhost.
**Fix:** `k8sServiceHost` must be `flux-kind-control-plane` (the Docker bridge hostname), not `127.0.0.1`.

```bash
# Confirm the current value Cilium is using
kubectl get configmap cilium-config -n kube-system -o jsonpath='{.data.k8s-api-server}'
```

### HelmRelease stuck in "install failed" after timeout

```bash
# Force an immediate retry without waiting for the interval
flux reconcile helmrelease <name> -n flux-system

# Check why it failed
kubectl describe helmrelease <name> -n flux-system | grep -A 20 "Status:"
```

### Flux not picking up new commits

```bash
# Force git pull + full reconcile
flux reconcile source git flux-system
```

### Cilium-managed HelmRelease conflicts with pre-installed release

**Symptom:** Flux installs a second release (`kube-system-cilium`) instead of adopting the pre-installed `cilium` release.
**Fix:** `spec.releaseName: cilium` must be set in the Cilium HelmRelease so Flux targets the correct Helm release name.

```bash
# Verify which Helm releases exist in kube-system
helm list -n kube-system
```

### istioctl analyze reports unlabelled namespaces (IST0102)

**Fix:** All non-mesh namespaces should carry `istio-injection: disabled` on their Namespace resource. This is set in the relevant `infrastructure/controllers/*.yaml` and `apps/base/prometheus/namespace.yaml` files, and via a kustomize patch on `flux-system`.

### Istio port naming warning (IST0118)

**Symptom:** `Port name metrics does not follow Istio naming convention`.
**Fix:** cert-manager webhook services are patched via `postRenderers.kustomize.patches` in `infrastructure/controllers/cert-manager.yaml`. Grafana is fixed via `service.portName: http` in `apps/base/grafana/helmrelease.yaml`.

### localhost:8080 connects but immediately resets (Gateway unreachable)

**Symptom:** `curl localhost:8080` connects then gets `Connection reset by peer` after ~15s.
**Cause:** On macOS Docker Desktop + Cilium kube-proxy replacement, `localhost:8080` traffic arrives at the KinD container's loopback (`127.0.0.1`), not `eth0`. Cilium's NodePort BPF rules only handle traffic incoming on `eth0` (from the Docker bridge). The result is the TCP handshake completes (Docker's proxy accepts it) but the traffic is never forwarded to the NodePort backend.
**Current setup:** The nginx `nodeport-proxy` DaemonSet in `apps/overlays/kind/istio/nodeport-proxy.yaml` is the **active primary path** — it runs with `hostNetwork: true` on the control-plane, listens on port 8888 (outside the NodePort range), and proxies to the stable `envoy-proxy` ClusterIP Service in `envoy-gateway-system`. KinD maps `localhost:8080 → containerPort: 8888`.

If traffic still fails after confirming Flux is reconciled:

```bash
# Check the nginx nodeport-proxy pod
kubectl get pods -n envoy-ingress -l app=nodeport-proxy
kubectl logs -n envoy-ingress -l app=nodeport-proxy | tail -20

# Check the stable ClusterIP Service endpoints
kubectl get endpoints envoy-proxy -n envoy-gateway-system

# Check if the Envoy proxy pod is receiving traffic
kubectl logs -n envoy-gateway-system -l app.kubernetes.io/component=proxy | tail -20

# Test from inside the cluster (bypasses macOS Docker Desktop routing)
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" -H "Host: grafana.local" \
  http://envoy-proxy.envoy-gateway-system.svc.cluster.local/
```

### ServiceMonitor CRD not found during Cilium install

**Symptom:** `no matches for kind "ServiceMonitor" in version "monitoring.coreos.com/v1"`.
**Cause:** Circular dependency — ServiceMonitor CRD lives in the apps layer (kube-prometheus-stack), which depends on the infrastructure layer (Cilium).
**Fix:** Cilium's `serviceMonitor.enabled` is `false` for all three monitors. Prometheus scrapes Cilium via `additionalScrapeConfigs` in `apps/base/prometheus/helmrelease.yaml` instead.

### Falco not detecting expected rules

**Symptom:** `make test-falco` reports one or more rules not detected.

```bash
# 1. Check that the modern_ebpf driver loaded successfully
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep -i "driver"

# 2. Check if Falco itself is reporting any startup errors
kubectl describe pod -n falco -l app.kubernetes.io/name=falco | grep -A 10 "Events:"

# 3. Confirm the event-generator Job ran on a node that has a Falco pod
kubectl get pod -n falco-test -l job-name=falco-event-generator \
  -o jsonpath='{.items[0].spec.nodeName}'
kubectl get pods -n falco -o wide
# The node names must match

# 4. Widen the log window (the make target looks back to Job start time)
kubectl logs -n falco -l app.kubernetes.io/name=falco --since=10m \
  | grep -i "untrusted\|credential\|shell"
```

**Root cause if BTF is unavailable:** `modern_ebpf` requires kernel BTF support. KinD nodes on Linux expose the host kernel BTF at `/sys/kernel/btf/vmlinux`. If the host kernel predates 5.8 or was built without `CONFIG_DEBUG_INFO_BTF`, Falco will fail to load. Upgrade the host kernel or switch to a KinD node image with a newer kernel.
