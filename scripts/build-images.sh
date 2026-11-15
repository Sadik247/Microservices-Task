#!/usr/bin/env bash
# Build all images directly inside Minikube's Docker daemon (no registry needed)
set -euo pipefail
eval "$(minikube -p minikube docker-env)"
for s in user-service product-service order-service gateway-service; do
  echo ">> Building $s:1.0"
  docker build -t "$s:1.0" "Microservices/$s"
done
docker images | grep -E 'user-service|product-service|order-service|gateway-service'
