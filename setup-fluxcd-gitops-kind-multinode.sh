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

if ! command -v flux &> /dev/null; then
  printf "[2/5] Installing Flux CLI...\n"
  brew install fluxcd/tap/flux
else
  printf "[2/5] Flux CLI already installed\n"
fi

if ! command -v gh &> /dev/null; then
  printf "[3/5] Installing GitHub CLI...\n"
  brew install gh
fi

## Comment out the 'gh auth login' after the first time if you don't need it.
printf "[4/5] Authenticating GitHub CLI...\n"
#gh auth login

## You will need to have your GitHub Personal Access Token (PAT) in your paste buffer for this step.
printf "[5/5] Bootstrapping Flux to GitHub repo: $GITHUB_USER/$REPO_NAME\n"
flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$REPO_NAME" \
  --branch="$BRANCH" \
  --path="$CLUSTER_PATH" \
  --personal

printf "✅ Setup complete. FluxCD is now watching '$CLUSTER_PATH' in your repo.\n"
