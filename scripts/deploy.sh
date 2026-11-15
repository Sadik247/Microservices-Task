#!/usr/bin/env bash
set -euo pipefail
kubectl apply -f k8s/
for d in user-service product-service order-service gateway-service; do
  kubectl -n microservices rollout status deployment/$d --timeout=120s
done
kubectl -n microservices get pods,svc,endpoints -o wide
