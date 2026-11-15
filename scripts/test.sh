#!/usr/bin/env bash
# Validate inter-service communication from inside the cluster
set -euo pipefail
NS=microservices
kubectl -n $NS run curl-test --rm -i --restart=Never --image=curlimages/curl:8.10.1 --command -- sh -c '
set -e
echo "--- Direct service DNS ---"
curl -s http://user-service:3000/users; echo
curl -s http://product-service:3001/products; echo
curl -s http://order-service:3002/orders; echo
echo "--- Through gateway ---"
curl -s http://gateway-service:3003/health; echo
curl -s http://gateway-service:3003/api/users; echo
curl -s http://gateway-service:3003/api/products; echo
curl -s -X POST -H "Content-Type: application/json" -d "{\"userId\":1,\"productId\":2}" http://gateway-service:3003/api/orders; echo
curl -s http://gateway-service:3003/api/orders; echo
echo "--- FQDN ---"
curl -s http://user-service.microservices.svc.cluster.local:3000/health; echo
'
