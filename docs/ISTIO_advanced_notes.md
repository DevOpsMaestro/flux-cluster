# Istio — Advanced Admin Reference

Cluster: `flux-kind` · Istio 1.30 · Cilium CNI with `socketLB.hostNamespaceOnly: true`

---

## Table of Contents

1. [mTLS policy enforcement](#1-mtls-policy-enforcement)
2. [Authorization policy](#2-authorization-policy)
3. [Certificate management](#3-certificate-management)
4. [Traffic management](#4-traffic-management)
5. [Observability](#5-observability)
6. [Envoy proxy deep inspection](#6-envoy-proxy-deep-inspection)
7. [Performance and resource tuning](#7-performance-and-resource-tuning)
8. [Mesh-wide configuration](#8-mesh-wide-configuration)
9. [Security auditing](#9-security-auditing)
10. [Disaster recovery and rollback](#10-disaster-recovery-and-rollback)

---

## 1. mTLS policy enforcement

### Enforce STRICT mTLS across the entire mesh

```bash
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system   # cluster-wide scope
spec:
  mtls:
    mode: STRICT
EOF
```

> **Warning:** Apply STRICT mesh-wide only after confirming every workload has a sidecar (`istioctl proxy-status`). Any pod without a proxy will lose all inbound traffic.

### Enforce STRICT mTLS for a single namespace

```bash
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: <namespace>
spec:
  mtls:
    mode: STRICT
EOF
```

### Exempt a specific port from mTLS (e.g. a legacy health-check endpoint)

> **Important — two constraints for portLevelMtls:**
>
> 1. **Workload selector required.** `portLevelMtls` is silently ignored on namespace-default PeerAuthentications (no `selector`). Apply per-workload exceptions using a separate named PeerAuthentication with a `spec.selector.matchLabels` field targeting the specific workload.
> 2. **Port keys must be quoted strings.** Write `"8080":` not `8080:`. Some YAML parsers (and kustomize's JSON marshaller) treat a bare integer key as `map[interface{}]interface{}` rather than `map[string]interface{}`, which causes a type error when the manifest is patched or diffed. The Kubernetes API server accepts both forms, but quoting avoids the parser ambiguity in tooling.

```bash
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: <workload>-port-8080
  namespace: <namespace>
spec:
  selector:
    matchLabels:
      app: <workload>
  mtls:
    mode: STRICT
  portLevelMtls:
    "8080":
      mode: PERMISSIVE
EOF
```

### Audit mTLS mode for every workload in the mesh

```bash
# Shows effective mTLS mode per service — look for DISABLE or PERMISSIVE as risks
istioctl x authz check <pod-name> -n <namespace>

# Check what mode a proxy is actually negotiating
istioctl proxy-config cluster <pod-name> -n <namespace> -o json \
  | jq '.[] | select(.transportSocket) | {name: .name, tls: .transportSocket}'
```

---

## 2. Authorization policy

### Deny all traffic by default, then allow explicitly (zero-trust baseline)

```bash
# Step 1 — deny everything in the namespace
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: deny-all
  namespace: <namespace>
spec: {}
EOF

# Step 2 — allow only specific paths from specific principals
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-get-only
  namespace: <namespace>
spec:
  selector:
    matchLabels:
      app: <app-label>
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - cluster.local/ns/<source-namespace>/sa/<source-serviceaccount>
      to:
        - operation:
            methods: ["GET"]
            paths: ["/api/*"]
EOF
```

### Audit what AuthorizationPolicies are in effect

```bash
# List all policies cluster-wide
kubectl get authorizationpolicy -A

# Check which policy is evaluated for a specific request
istioctl x authz check <pod-name> -n <namespace>
```

### Test a policy without enforcing it (dry-run via AUDIT action)

```bash
kubectl apply -f - <<'EOF'
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: audit-policy
  namespace: <namespace>
spec:
  action: AUDIT
  rules:
    - to:
        - operation:
            methods: ["DELETE"]
EOF
# Denied requests are logged in the proxy but traffic still passes.
# Check: kubectl logs <pod> -c istio-proxy | grep "AuthzAudit"
```

---

## 3. Certificate management

### Inspect certificates loaded on a proxy

```bash
# View cert chain, expiry, and SAN for all certs on a pod
istioctl proxy-config secret <pod-name> -n <namespace>

# Detailed view of a specific cert
istioctl proxy-config secret <pod-name> -n <namespace> -o json \
  | jq '.dynamicActiveSecrets[] | {name: .name, expiry: .secret.tlsCertificate.certificateChain}'
```

### Check the root CA istiod is using

```bash
kubectl get secret istio-ca-secret -n istio-system -o jsonpath='{.data.ca-cert\.pem}' \
  | base64 -d | openssl x509 -text -noout | grep -E "Issuer|Subject|Not After"
```

### Force certificate rotation for a workload

```bash
# Delete the proxy secret — istiod will issue a fresh cert on the next xDS push
kubectl delete secret istio.default -n <namespace>
# Restart the workload to load the new cert immediately
kubectl rollout restart deployment/<name> -n <namespace>
```

### Verify cert-manager is issuing Istio workload certs (if integrated)

```bash
kubectl get certificaterequests -A | grep istio
kubectl get certificates -n istio-system
```

---

## 4. Traffic management

### DestinationRule — configure connection pool and outlier detection

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: <service>-dr
  namespace: <namespace>
spec:
  host: <service>.<namespace>.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
        http1MaxPendingRequests: 50
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 10s
      baseEjectionTime: 30s
      maxEjectionPercent: 50
EOF
```

### VirtualService — weighted traffic split (canary/blue-green)

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: <service>-vs
  namespace: <namespace>
spec:
  hosts:
    - <service>.<namespace>.svc.cluster.local
  http:
    - route:
        - destination:
            host: <service>.<namespace>.svc.cluster.local
            subset: stable
          weight: 90
        - destination:
            host: <service>.<namespace>.svc.cluster.local
            subset: canary
          weight: 10
EOF
```

### Fault injection — test resilience without changing application code

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: <service>-fault
  namespace: <namespace>
spec:
  hosts:
    - <service>.<namespace>.svc.cluster.local
  http:
    - fault:
        delay:
          percentage:
            value: 20
          fixedDelay: 3s
        abort:
          percentage:
            value: 5
          httpStatus: 503
      route:
        - destination:
            host: <service>.<namespace>.svc.cluster.local
EOF
```

### Retry policy

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: <service>-retry
  namespace: <namespace>
spec:
  hosts:
    - <service>.<namespace>.svc.cluster.local
  http:
    - retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: "5xx,reset,connect-failure"
      route:
        - destination:
            host: <service>.<namespace>.svc.cluster.local
EOF
```

---

## 5. Observability

### Access control plane metrics (Prometheus format)

```bash
# Port-forward istiod metrics endpoint (port 15014 — not 8080, which is the debug HTTP server)
kubectl port-forward -n istio-system deploy/istiod 15014:15014 &
curl -s http://localhost:15014/metrics | grep pilot_
```

### Key Prometheus queries (run against the observability namespace)

```bash
kubectl port-forward -n observability svc/observability-kube-prometh-prometheus 9090:9090 &

# Request success rate per destination service
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(istio_requests_total{reporter="destination",response_code!~"5.."}[5m])) by (destination_service_name) / sum(rate(istio_requests_total{reporter="destination"}[5m])) by (destination_service_name)'

# P99 request latency per service
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=histogram_quantile(0.99, sum(rate(istio_request_duration_milliseconds_bucket{reporter="destination"}[5m])) by (le, destination_service_name))' \
  | jq '.data.result[] | {service: .metric.destination_service_name, p99_ms: .value[1]}'

# mTLS ratio — should be 1.0 for all services under STRICT mode
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(istio_requests_total{connection_security_policy="mutual_tls"}[5m])) by (destination_service_name) / sum(rate(istio_requests_total[5m])) by (destination_service_name)' \
  | jq '.data.result[] | {service: .metric.destination_service_name, mtls_ratio: .value[1]}'
```

### Enable access logging on specific workloads

```bash
kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: access-log
  namespace: <namespace>
spec:
  accessLogging:
    - providers:
        - name: envoy
EOF
# Logs appear in: kubectl logs <pod> -c istio-proxy
```

### Distributed tracing (if a trace backend is configured)

```bash
# Set trace sampling to 100% for a namespace temporarily
kubectl apply -f - <<'EOF'
apiVersion: telemetry.istio.io/v1alpha1
kind: Telemetry
metadata:
  name: tracing-100pct
  namespace: <namespace>
spec:
  tracing:
    - randomSamplingPercentage: 100.0
EOF
```

---

## 6. Envoy proxy deep inspection

### Full xDS config dump for a proxy

```bash
# Dump everything Envoy has received from istiod
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s http://localhost:15000/config_dump | jq .
```

### Live cluster health and connection stats

```bash
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s http://localhost:15000/clusters | grep -E "health|cx_active|rq_active"
```

### Inspect active listeners on the proxy admin port

```bash
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s http://localhost:15000/listeners
```

### Reset stats on a proxy (useful to isolate a time window)

```bash
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s -X POST http://localhost:15000/reset_counters
```

### Check Envoy's readiness and live stats

```bash
# Readiness (used by the kubelet probe)
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s http://localhost:15021/healthz/ready

# General stats
kubectl exec <pod-name> -n <namespace> -c istio-proxy -- \
  curl -s http://localhost:15000/stats | grep -E "upstream_cx|downstream_cx|retry"
```

---

## 7. Performance and resource tuning

### Check how many proxies istiod is managing

```bash
kubectl exec -n istio-system deploy/istiod -- \
  curl -s http://localhost:8080/debug/endpointz | jq 'length'
```

### Identify proxies that are out of sync with istiod

```bash
# SYNCED = up to date; STALE = lagging behind xDS push
istioctl proxy-status | grep -v SYNCED
```

### Force an xDS push to all proxies

```bash
# Restart istiod — it will re-push full config to all connected proxies
kubectl rollout restart deploy/istiod -n istio-system
```

### Tune sidecar scope to reduce xDS payload (large clusters)

```bash
# Restrict a workload to only the services it actually calls
kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: Sidecar
metadata:
  name: scoped-sidecar
  namespace: <namespace>
spec:
  workloadSelector:
    labels:
      app: <app-label>
  egress:
    - hosts:
        - "./<service-a>.<namespace>.svc.cluster.local"
        - "./<service-b>.<namespace>.svc.cluster.local"
        - "istio-system/*"
EOF
```

---

## 8. Mesh-wide configuration

### Inspect the active MeshConfig

```bash
kubectl get configmap istio -n istio-system -o jsonpath='{.data.mesh}' | yq .
```

### Change the default trace sampling rate mesh-wide

```bash
kubectl get configmap istio -n istio-system -o json \
  | jq '.data.mesh |= (. | gsub("traceSampling: [0-9.]+"; "traceSampling: 1.0"))' \
  | kubectl apply -f -
# This cluster sets traceSampling via istiod Helm values (pilot.traceSampling: 10.0).
# Prefer editing infrastructure/controllers/istio.yaml and letting Flux reconcile the change.
```

### List all Istio CRDs installed in the cluster

```bash
kubectl get crd | grep istio.io
```

### Check which Istio version each proxy is running

```bash
# Mismatched versions between istiod and proxies indicate an incomplete rollout
istioctl proxy-status | awk '{print $5}' | sort | uniq -c | sort -rn
```

---

## 9. Security auditing

### Find all workloads without a sidecar (not in the mesh)

```bash
# Pods missing the istio-proxy container — these bypass all mTLS and AuthorizationPolicies
kubectl get pods -A -o json \
  | jq -r '.items[] | select(all(.spec.containers[]; .name != "istio-proxy")) | "\(.metadata.namespace)/\(.metadata.name)"' \
  | sort -u
```

### Verify no service is accepting plain-text traffic under STRICT mode

```bash
# Any non-zero result means plain-text traffic is reaching a STRICT-mode workload
kubectl port-forward -n observability svc/observability-kube-prometh-prometheus 9090:9090 &
curl -sG 'http://localhost:9090/api/v1/query' \
  --data-urlencode 'query=sum(rate(istio_requests_total{connection_security_policy="none"}[5m])) by (destination_service_name)' \
  | jq '.data.result'
```

### Audit JWT/OIDC authentication policies

```bash
kubectl get requestauthentication -A
kubectl describe requestauthentication <name> -n <namespace>
```

### Check RBAC policies that govern Istio resource access

```bash
# Who can create/modify AuthorizationPolicies and PeerAuthentications
kubectl get clusterrolebinding -o json \
  | jq -r '.items[] | select(.roleRef.name | test("istio")) | "\(.metadata.name): \(.subjects[]?.name)"'
```

---

## 10. Disaster recovery and rollback

### Roll back istiod to the previous version via Flux

```bash
# Pin the chart to the previous patch version in infrastructure/controllers/istio.yaml,
# then force Flux to reconcile immediately
flux reconcile helmrelease istiod -n flux-system --with-source

# Monitor the rollout
kubectl rollout status deploy/istiod -n istio-system
```

### Drain a namespace from the mesh (emergency — removes all sidecars)

```bash
# Disable injection and restart all pods to drop the sidecars
kubectl label namespace <namespace> istio-injection=disabled --overwrite
kubectl rollout restart deployment -n <namespace>
# All traffic in the namespace will now bypass Istio — mTLS and AuthorizationPolicies no longer apply
```

### Verify istiod recovers after a restart (proxies re-sync)

```bash
kubectl rollout restart deploy/istiod -n istio-system
kubectl rollout status deploy/istiod -n istio-system

# Watch proxy sync status recover — all should return to SYNCED within ~60s
watch -n 5 "istioctl proxy-status | grep -c SYNCED"
```

### Export the full mesh state for offline analysis

```bash
# Dump all Istio custom resources to a single file
kubectl get \
  virtualservices,destinationrules,gateways,serviceentries,\
  peerauthentications,authorizationpolicies,requestauthentications,\
  sidecars,telemetries \
  -A -o yaml > istio-mesh-state-$(date +%F).yaml
```
