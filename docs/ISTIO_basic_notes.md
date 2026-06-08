# Istio — Daily Admin Reference

Cluster: `flux-kind` · Istio 1.30 · istiod in `istio-system`

---

## Health checks

```bash
# Validate the full installation against the cluster
istioctl verify-install

# Detect misconfigurations, missing injection labels, port naming issues
istioctl analyze --all-namespaces

# istiod pod status
kubectl get pods -n istio-system

# Confirm all sidecar proxies are in sync with istiod
istioctl proxy-status
```

---

## Sidecar injection

```bash
# Enable injection for a namespace
kubectl label namespace <namespace> istio-injection=enabled

# Disable injection for a namespace (explicit — suppresses istioctl analyze warnings)
kubectl label namespace <namespace> istio-injection=disabled

# Check injection labels across all namespaces
kubectl get namespaces --show-labels | grep istio-injection

# Restart pods in a namespace to pick up injection after enabling it
kubectl rollout restart deployment -n <namespace>
```

---

## Traffic visibility

```bash
# Show all inbound/outbound listeners on a pod's Envoy proxy
istioctl proxy-config listener <pod-name> -n <namespace>

# Show routes
istioctl proxy-config route <pod-name> -n <namespace>

# Show upstream clusters and their TLS mode
istioctl proxy-config cluster <pod-name> -n <namespace>

# Show TLS certificates loaded on a proxy
istioctl proxy-config secret <pod-name> -n <namespace>
```

---

## mTLS

```bash
# Check the effective PeerAuthentication policy for a namespace
kubectl get peerauthentication -n <namespace>

# Check cluster-wide PeerAuthentication (STRICT locks down the whole mesh)
kubectl get peerauthentication -A

# Confirm mTLS is active on a live connection — look for x-forwarded-client-cert in the response
kubectl exec -n <namespace> deploy/<client> -- \
  curl -s http://<service>.<namespace>.svc.cluster.local/headers | grep -i x-forwarded-client-cert
```

---

## Workload validation

```bash
# Validate all resources in a namespace for Istio compatibility
kubectl get all -n <namespace> -o yaml | istioctl validate -f -

# Describe the effective config Istio applies to a specific pod
istioctl experimental describe pod <pod-name> -n <namespace>
```

---

## Logs

```bash
# istiod control plane logs
kubectl logs -n istio-system deploy/istiod | tail -50

# Enable debug logging on a specific proxy (resets on pod restart)
istioctl proxy-config log <pod-name> -n <namespace> --level debug

# View proxy logs
kubectl logs <pod-name> -n <namespace> -c istio-proxy | tail -50
```

---

## Flux reconciliation

```bash
# Watch all Flux resources including Istio HelmReleases
watch -n 6 "flux get all -A"

# Force immediate reconciliation of Istio
flux reconcile helmrelease istio-base -n flux-system
flux reconcile helmrelease istiod -n flux-system
```
