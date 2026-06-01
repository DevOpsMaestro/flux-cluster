#!/bin/bash

# 1. Get all unique images from both containers and init-containers
echo "🔍 Identifying images in the cluster..."
IMAGES=$(kubectl get pods -A -o jsonpath='{.items[*].spec.containers[*].image} {.items[*].spec.initContainers[*].image}' | tr ' ' '\n' | sort -u)

if [ -z "$IMAGES" ]; then
    echo "❌ No images found. Is your cluster running?"
    exit 1
fi

echo "🚀 Starting local pulls..."
echo "--------------------------"

# 2. Pull each image to your laptop's Docker engine
for IMG in $IMAGES; do
    echo "📦 Pulling: $IMG"
    docker pull "$IMG" > /dev/null
done

echo "--------------------------"
echo "✅ Done! All cluster images are now cached in your local Docker."
