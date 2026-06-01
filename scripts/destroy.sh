#!/bin/bash
set -e

# Source shared version pins so $CLUSTER_NAME and $K8S_VER are defined.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../versions.env
source "${SCRIPT_DIR}/../versions.env"

echo "🗑  Deleting KinD cluster: $CLUSTER_NAME"
kind delete cluster --name "$CLUSTER_NAME"

# Optional cleanup
read -p "🧹 Do you want to remove the local KinD node image? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo "🧽 Removing KinD node image (kindest/node:${K8S_VER})..."
  docker rmi "kindest/node:${K8S_VER}" 2>/dev/null || true
fi

echo "✅ Teardown complete."
exit 0
