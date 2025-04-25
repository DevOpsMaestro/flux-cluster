#!/bin/bash
set -e

CLUSTER_NAME="flux-kind"
GITHUB_USER="DevOpsMaestro"
REPO_NAME="flux-cluster"
BRANCH="main"
CLUSTER_PATH="clusters/kind"
K8S_VER="v1.33.0"

printf "\n[1/5] Creating KinD cluster: $CLUSTER_NAME\n"
cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
networking:
  ipFamily: ipv6
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
  # WARNING: It is _strongly_ recommended that you keep this the default
  # (127.0.0.1) for security reasons. However it is possible to change this.
  apiServerAddress: "127.0.0.1"
  # By default the API server listens on a random open port.
  # You may choose a specific port but probably don't need to in most cases.
  # Using a random port makes it easier to spin up multiple clusters.
  apiServerPort: 6443
nodes:
- role: control-plane
  image: "kindest/node:${K8S_VER}"
  name: "cp-one"
- role: control-plane
  image: "kindest/node:${K8S_VER}"
  name: "cp-two"
- role: control-plane
  image: "kindest/node:${K8S_VER}"
  name: "cp-three"
- role: worker
  image: "kindest/node:${K8S_VER}"
  name: "dp-one"
- role: worker
  image: "kindest/node:${K8S_VER}"
  name: "dp-two"
- role: worker
  image: "kindest/node:${K8S_VER}"
  name: "dp-three"
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
