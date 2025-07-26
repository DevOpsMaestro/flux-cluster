#!/bin/bash
set -e

CLUSTER_NAME="generic-kind"
GITHUB_USER="DevOpsMaestro"
REPO_NAME="flux-cluster"
BRANCH="main"
CLUSTER_PATH="clusters/kind"
K8S_VER="v1.32.0"

printf "\n[1/5] Creating KinD cluster: $CLUSTER_NAME\n"
cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv4
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.96.0.0/12
  apiServerAddress: 127.0.0.1
  apiServerPort: 6443
nodes:
  - role: control-plane
    image: kindest/node:${K8S_VER}
    kubeadmConfigPatches:
    - |
      kind: InitConfiguration
      nodeRegistration:
        name: control-plane-0
  # - role: control-plane
  #   image: kindest/node:${K8S_VER}
  #   kubeadmConfigPatches:
  #   - |
  #     kind: InitConfiguration
  #     nodeRegistration:
  #       name: control-plane-1
  # - role: control-plane
  #   image: kindest/node:${K8S_VER}
  #   kubeadmConfigPatches:
  #   - |
  #     kind: InitConfiguration
  #     nodeRegistration:
  #       name: control-plane-2
  - role: worker
    image: kindest/node:${K8S_VER}
    kubeadmConfigPatches:
    - |
      kind: JoinConfiguration
      nodeRegistration:
        name: data-plane-0
  - role: worker
    image: kindest/node:${K8S_VER}
    kubeadmConfigPatches:
    - |
      kind: JoinConfiguration
      nodeRegistration:
        name: data-plane-1
  - role: worker
    image: kindest/node:${K8S_VER}
    kubeadmConfigPatches:
    - |
      kind: JoinConfiguration
      nodeRegistration:
        name: data-plane-2
EOF

printf "✅ Setup complete.\n"
