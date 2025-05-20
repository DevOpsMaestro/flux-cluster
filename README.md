# flux-cluster

2025 fluxcd cluster to deploy in KinD

For the basic KinD deployment, run:

**Note:** uncomment the line with `gh auth login` the first time in both scripts to have Git Helper (gh) assist you in getting your Token setup correctly.

```bash
setup-fluxcd-gitops-kind-multinode.sh

```

&nbsp;

## Istio

For the ISTIO in KinD deployment, run:

```bash
setup-istio-flux-kind-ingress.sh

```

Notes on basic deployment

[ISTIO Basic Notes](https://github.com/DevOpsMaestro/flux-cluster/blob/main/ISTIO_basic_notes.md)

Notes on advanced changes

[ISTIO Advanced Notes](https://github.com/DevOpsMaestro/flux-cluster/blob/main/ISTIO_advanced_notes.md)
