#!/bin/bash
set -e

CLUSTER_NAME="flux-kind"
echo "🗑  Deleting KinD cluster: $CLUSTER_NAME"
kind delete cluster --name "$CLUSTER_NAME"

# Optional cleanup
read -p "🧹 Do you want to prune local Docker images? [y/N]: " confirm

if [[ "$confirm" =~ ^[Yy]$ ]]; then
  echo "🧽 Pruning local Docker images..."
  # List and remove KinD-related images (optional, only if needed)
  docker image prune -f
fi

echo "✅ Teardown complete."

exit 0
