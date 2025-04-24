#!/bin/bash
set -e

CLUSTER_NAME="flux-kind"
GITHUB_USER="DevOpsMaestro"
REPO_NAME="flux-cluster"
BRANCH="main"
CLUSTER_PATH="clusters/kind"

printf "\n[1/5] Creating KinD cluster: $CLUSTER_NAME\n"
cat <<EOF | kind create cluster --name "$CLUSTER_NAME" --config=-
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
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

printf "[4/5] Authenticating GitHub CLI...\n"
gh auth login

printf "[5/5] Bootstrapping Flux to GitHub repo: $GITHUB_USER/$REPO_NAME\n"
flux bootstrap github \
  --owner="$GITHUB_USER" \
  --repository="$REPO_NAME" \
  --branch="$BRANCH" \
  --path="$CLUSTER_PATH" \
  --personal

printf "✅ Setup complete. FluxCD is now watching '$CLUSTER_PATH' in your repo.\n"
