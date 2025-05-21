# ISTIO Basic Notes.md

For the ISTIO in KinD deployment, run:

```bash
setup-istio-flux-kind-ingress.sh

```

To watch flux for the deployment and reconcilation, run:

```bash
watch -n 6 "flux get all -A"

```

After the Flux reconciliation is finished, run:

```bash
istioctl analyze -n istio-system

kubectl -n istio-system get pods -l app=istiod

curl -I http://localhost:8080/healthz/ready

```

