#!/usr/bin/env bash
# Build images with the local Docker daemon (Docker Desktop), then load them into Minikube.
# Works with both docker and containerd Minikube runtimes
# (minikube docker-env is not supported on Windows with containerd).
set -euo pipefail
for s in user-service product-service order-service gateway-service; do
  echo ">> Building $s:1.0"
  docker build -t "$s:1.0" "Microservices/$s"
  minikube image load "$s:1.0"
done
minikube image ls | grep -E 'user-service|product-service|order-service|gateway-service'