#!/bin/bash
set -e

CLUSTER_NAME="flux-kind"
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
  # - role: control-plane
  #   image: kindest/node:${K8S_VER}
  # - role: control-plane
  #   image: kindest/node:${K8S_VER}
  - role: worker
    image: kindest/node:${K8S_VER}
  - role: worker
    image: kindest/node:${K8S_VER}
  - role: worker
    image: kindest/node:${K8S_VER}
EOF

printf "✅ Setup complete.\n"
