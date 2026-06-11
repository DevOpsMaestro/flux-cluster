# iperf3 — Network Load Testing

Cluster: `flux-kind` · App namespace: `iperf3` · Config: `apps/base/iperf3/`

---

## What iperf3 Does

iperf3 is a network bandwidth measurement tool. It works on a client-server model: a server process listens on a port and waits for a client to initiate a test. When the client connects, both sides exchange data for a fixed duration and report the achieved throughput, along with diagnostics such as retransmit counts and congestion window size.

iperf3 is used in this cluster to measure how much sustained TCP bandwidth the Envoy Gateway data plane can carry and to verify that traffic-shaping policies (circuit breakers, connection caps) behave as expected under load.

---

## Network Path

When a test is initiated from the host Mac, the connection travels through four distinct layers before reaching the iperf3 server process:

```
Mac host (iperf3 client)
  │
  │  localhost:32111  (IPv4 — always use -4 or 127.0.0.1)
  ▼
Docker extraPortMapping
  │  hostPort 32111 → containerPort 9111 (flux-kind-control-plane)
  ▼
nginx nodeport-proxy DaemonSet  (envoy-ingress namespace, hostNetwork: true)
  │  stream { listen 9111; proxy_pass envoy-proxy.envoy-gateway-system:32111; }
  ▼
envoy-proxy ClusterIP Service  (envoy-gateway-system, port 32111)
  │
  ▼
Envoy Gateway data-plane pod  (envoy-gateway-system)
  │  TCPRoute: iperf3/iperf3 → iperf3 Service:32111
  ▼
iperf3 server pod  (iperf3 namespace, port 32111)
```

---

## Why Each Layer Exists

### Port 9111 instead of 32111 on the nginx DaemonSet

Cilium replaces kube-proxy using BPF programs installed in the kernel. As a side effect, those programs intercept `bind()` calls on the NodePort range (30000–32767), preventing any userspace process from binding directly to a port in that range. Because the nginx DaemonSet runs with `hostNetwork: true` and must bind a port on the node's network interface, it cannot use any port in the NodePort range.

Port 9111 sits below that range, so nginx binds there without conflict. The KinD cluster's `extraPortMapping` maps `hostPort 32111 → containerPort 9111`, preserving the user-facing port number on the Mac while keeping nginx clear of the NodePort range.

### nginx stream block

KinD has no cloud load-balancer controller, so a `Service` of type `LoadBalancer` remains `Pending` indefinitely. The nginx nodeport-proxy DaemonSet is used for all external traffic. Its `http {}` block handles HTTP traffic on port 8888; its `stream {}` block handles raw TCP on port 9111. The stream block performs a simple Layer 4 proxy pass to the Envoy proxy ClusterIP Service at `envoy-proxy.envoy-gateway-system.svc.cluster.local:32111`. No HTTP framing is added — iperf3 sends and receives raw TCP, and the stream block passes it through unmodified.

### Stable ClusterIP Service (`envoy-proxy`)

Envoy Gateway auto-provisions a Service named `envoy-<namespace>-<gateway>-<uid-hash>`. The hash suffix changes every time the cluster is rebuilt, so nginx cannot use that name for `proxy_pass`. A separate ClusterIP Service named `envoy-proxy` is defined in `apps/overlays/kind/envoy-gateway/proxy-service.yaml`. It selects the same proxy pods using stable labels (`app.kubernetes.io/component: proxy`, `gateway.envoyproxy.io/owning-gateway-name: main`) and exposes both port 80 (HTTP) and port 32111 (TCP iperf3). nginx always targets this stable name.

### Gateway TCPRoute

The main Gateway (defined in `apps/base/envoy-gateway/gateway.yaml`) has two listeners:

| Listener | Port | Protocol |
|---|---|---|
| `http` | 80 | HTTP |
| `tcp-iperf3` | 32111 | TCP |

The `TCPRoute` in `apps/base/iperf3/route.yaml` attaches to the `tcp-iperf3` listener via `sectionName: tcp-iperf3` and forwards all connections to the `iperf3` ClusterIP Service on port 32111. Envoy Gateway then routes each connection to a healthy pod using its load balancer.

---

## Traffic Shaping — BackendTrafficPolicy

A `BackendTrafficPolicy` in `apps/base/iperf3/traffic-policy.yaml` applies a circuit breaker and timeout to the iperf3 cluster:

| Setting | Value | Effect |
|---|---|---|
| `circuitBreaker.maxConnections` | 10 | Envoy rejects new upstream connections once 10 are active |
| `circuitBreaker.maxPendingRequests` | 5 | Envoy rejects pending connections once 5 are queued |
| `timeout.tcp.connectTimeout` | 10s | Upstream connection attempt times out after 10 seconds |

When `maxConnections` is exceeded, Envoy increments the `upstream_cx_overflow` counter and immediately resets the excess connections. This lets you observe circuit-breaker behaviour live using the Envoy admin API.

---

## Security Configuration

The `iperf3` namespace is isolated by a `default-deny` NetworkPolicy that blocks all ingress and egress by default. Three additional policies carve out only the paths that the iperf3 server legitimately needs:

| Policy | Allows |
|---|---|
| `allow-dns-egress` | UDP/TCP port 53 to `kube-system` (CoreDNS) |
| `allow-envoy-ingress` | TCP port 32111 from `envoy-gateway-system` |

The server pod itself has no privileges:

- `allowPrivilegeEscalation: false`
- `capabilities.drop: [ALL]`
- No service account token mounted (`automountServiceAccountToken: false`)
- Resource limits enforced (Kyverno `require-resource-limits` policy)

The corresponding NetworkPolicy in `infrastructure/controllers/envoy-gateway.yaml` (`allow-proxy-http-ingress`) allows ingress to the Envoy proxy pod on both port 10080 (HTTP) and port 32111 (TCP iperf3). Without the port 32111 entry, `default-deny` in `envoy-gateway-system` silently drops all iperf3 connections after nginx forwards them.

---

## Running Tests

Always use `-4` or `127.0.0.1` to force IPv4. `localhost` on macOS resolves to `::1` first; Docker only binds on `0.0.0.0`, so the IPv6 attempt returns "Connection refused" immediately.

### Single-stream bandwidth (baseline)

```bash
iperf3 -4 -c localhost -p 32111 -t 30
```

Expected: ~700–800 Mbits/sec sustained, 0 retransmits.

### Circuit-breaker test (exceeds maxConnections: 10)

```bash
iperf3 -4 -c localhost -p 32111 -P 20 -t 30
```

With 20 parallel streams, Envoy allows 10 upstream connections and overflows the remaining 10. The iperf3 client reports "control socket has closed unexpectedly" when the circuit breaker terminates connections mid-test. This is the expected outcome.

### Observe circuit-breaker overflow counter

```bash
PROXY_POD=$(kubectl get pods -n envoy-gateway-system \
  -l app.kubernetes.io/component=proxy \
  -o jsonpath='{.items[0].metadata.name}')

kubectl port-forward -n envoy-gateway-system "$PROXY_POD" 19000:19000 &
sleep 1

curl -s localhost:19000/stats \
  | grep "tcproute/iperf3/iperf3/rule/-1.upstream_cx_overflow"

kill %1
```

Expected after the `-P 20` test: `upstream_cx_overflow: 10` or higher.

---

## Verifying Route Status

```bash
# TCPRoute should be Accepted and ResolvedRefs: True
kubectl get tcproute -n iperf3 iperf3 \
  -o jsonpath='{.status.parents[0].conditions}' | python3 -m json.tool

# Gateway should be PROGRAMMED: True
kubectl get gateway -n envoy-ingress

# iperf3 pod should be 1/1 Running
kubectl get pods -n iperf3
```

---

## Configuration Reference

| Resource | File |
|---|---|
| Deployment + container | `apps/base/iperf3/deployment.yaml` |
| ClusterIP Service | `apps/base/iperf3/service.yaml` |
| TCPRoute | `apps/base/iperf3/route.yaml` |
| BackendTrafficPolicy | `apps/base/iperf3/traffic-policy.yaml` |
| NetworkPolicies | `apps/base/iperf3/networkpolicies.yaml` |
| Stable Envoy ClusterIP Service | `apps/overlays/kind/envoy-gateway/proxy-service.yaml` |
| nginx stream block | `apps/overlays/kind/istio/nodeport-proxy.yaml` |
| Envoy Gateway TCP listener + NetworkPolicy | `infrastructure/controllers/envoy-gateway.yaml` |
| KinD extraPortMapping | `scripts/setup-fluxcd-gitops-kind-multinode.sh` |
