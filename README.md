# Microservices on Kubernetes (Minikube)

Four Node.js/Express microservices deployed to Minikube with Deployments, ClusterIP Services, a ConfigMap, resource limits and health probes.

| Service | Port | Endpoints | Calls |
|---|---|---|---|
| user-service | 3000 | `/health`, `/users` | – |
| product-service | 3001 | `/health`, `/products` | – |
| order-service | 3002 | `/health`, `GET/POST /orders` | – |
| gateway-service | 3003 | `/health`, `/api/users`, `/api/products`, `GET/POST /api/orders` | user, product, order |

```
            ┌──────────── namespace: microservices ────────────┐
 client ──► │ gateway-service:3003 (ClusterIP + NodePort 30003)│
            │      │ http://user-service:3000                  │
            │      ├─► user-service    (ClusterIP)             │
            │      ├─► product-service (ClusterIP)  :3001      │
            │      └─► order-service   (ClusterIP)  :3002      │
            └──────────────────────────────────────────────────┘
```

## Repository layout

```
Microservices/<svc>/   app.js, package.json, Dockerfile, .dockerignore
k8s/
  00-namespace.yaml          Namespace "microservices"
  01-configmap.yaml          Shared env: NODE_ENV, LOG_LEVEL, upstream URLs, NO_PROXY
  10-user-service.yaml       Deployment + ClusterIP Service
  11-product-service.yaml    Deployment + ClusterIP Service
  12-order-service.yaml      Deployment + ClusterIP Service
  13-gateway-service.yaml    Deployment + ClusterIP Service + NodePort Service
scripts/  build-images.sh, deploy.sh, test.sh
screenshots/
```

## Design decisions

- **Service names match the gateway code.** `gateway-service/app.js` hardcodes `http://user-service:3000`, `http://product-service:3001`, `http://order-service:3002`. The Services use exactly those names and ports, and everything sits in one namespace, so Kubernetes DNS resolves the short names.
- **ClusterIP for all services** gives cluster-internal discovery. Only the gateway also gets a `NodePort` (`gateway-service-external`, 30003) as an optional external entry point. Backends are never exposed.
- **Images** are built inside Minikube's Docker daemon (`eval $(minikube docker-env)`) and tagged `:1.0`. With `imagePullPolicy: IfNotPresent` no registry is needed.
- **Probes:** every app exposes `GET /health`, which both probes use. Readiness probes start at 5s and liveness probes at 15s, so a slow start isn't killed.
- **Resources:** requests are `50m` CPU / `64Mi` memory and limits are `200m` / `128Mi`, which is plenty for tiny Express apps.
- **Labels/selectors:** `app: <name>` is the selector. `tier` (frontend/backend) and `app.kubernetes.io/part-of` are there for grouping.
- **Gateway proxy handling:** axios honours `HTTP_PROXY`/`HTTPS_PROXY` environment variables. If Minikube runs behind a corporate proxy, the gateway's calls to other services would get routed to that proxy and fail. The gateway therefore gets `NO_PROXY`/`no_proxy` covering service names, `.svc`, `.cluster.local` and the Service/Pod CIDRs. Upstream URLs are also set as environment variables (`USER_SERVICE_URL`, …) from the ConfigMap.

## 1. Minikube setup

```bash
# Prereqs: Docker, kubectl, minikube
minikube start --driver=docker --cpus=2 --memory=4096
minikube status
kubectl get nodes
# (Behind a proxy:)
# minikube start --docker-env HTTP_PROXY=$HTTP_PROXY --docker-env HTTPS_PROXY=$HTTPS_PROXY \
#   --docker-env NO_PROXY=$NO_PROXY,192.168.49.0/24,10.96.0.0/12,10.244.0.0/16
```

## 2. Build images (inside Minikube)

```bash
./scripts/build-images.sh
# equivalent to:
eval $(minikube docker-env)
docker build -t user-service:1.0    Microservices/user-service
docker build -t product-service:1.0 Microservices/product-service
docker build -t order-service:1.0   Microservices/order-service
docker build -t gateway-service:1.0 Microservices/gateway-service
```

## 3. Deploy with `kubectl apply -f`

```bash
kubectl apply -f k8s/          # applies files in order (namespace first)
kubectl -n microservices rollout status deploy/gateway-service
kubectl -n microservices get pods -o wide
kubectl -n microservices get svc,endpoints
```

## 4. Testing

### a) Through service names (from inside the cluster)
```bash
./scripts/test.sh
# or manually:
kubectl -n microservices run curl-test --rm -it --restart=Never --image=curlimages/curl -- sh
curl http://user-service:3000/users
curl http://gateway-service:3003/api/products
curl -X POST -H 'Content-Type: application/json' -d '{"userId":1,"productId":2}' http://gateway-service:3003/api/orders
curl http://gateway-service:3003/api/orders
```

### b) With port-forward
```bash
kubectl -n microservices port-forward svc/gateway-service 3003:3003
# new terminal
curl http://localhost:3003/health
curl http://localhost:3003/api/users
curl http://localhost:3003/api/products
curl -X POST -H 'Content-Type: application/json' -d '{"userId":1,"productId":1}' http://localhost:3003/api/orders
curl http://localhost:3003/api/orders
```
Backends individually: `kubectl -n microservices port-forward svc/user-service 3000:3000`, and likewise for the others.

### c) NodePort (optional)
```bash
minikube service gateway-service-external -n microservices --url
curl $(minikube service gateway-service-external -n microservices --url)/api/users
```

### Expected output
```json
[{"id":1,"name":"John Doe"},{"id":2,"name":"Jane Smith"}]
[{"id":1,"name":"Laptop","price":999},{"id":2,"name":"Phone","price":699}]
{"id":1,"userId":1,"productId":2,"timestamp":"..."}
```

### Logs showing communication
```bash
kubectl -n microservices logs deploy/gateway-service
kubectl -n microservices logs -l tier=backend --prefix
```
The apps only log their startup line. Communication is proven by the gateway returning backend data and by `curl` from the test pod.

## 5. Troubleshooting

| Symptom | Cause / Fix |
|---|---|
| `ErrImagePull` / `ImagePullBackOff` | Images were built on the host Docker daemon, not Minikube's. Run `eval $(minikube docker-env)` and rebuild, or `minikube image load <img>:1.0`. Check with `minikube image ls`. |
| Pod `0/1 Running`, not Ready | Readiness probe failing. `kubectl -n microservices describe pod <pod>` → Events. Confirm the containerPort matches the app port. |
| `CrashLoopBackOff` | `kubectl -n microservices logs <pod> --previous`. Usually a missing npm dependency, so rebuild the image. |
| Gateway returns `{"error":"Error fetching users"}` | DNS/Service mismatch. Check `kubectl -n microservices get endpoints`: each Service must list a pod IP. Service names must be exactly `user-service`, `product-service`, `order-service`. Test DNS: `kubectl -n microservices run dns --rm -it --image=busybox:1.36 --restart=Never -- nslookup user-service`. |
| Gateway errors only behind a corporate proxy | `HTTP_PROXY` is leaking into the pod. Make sure `NO_PROXY` from the ConfigMap is applied (`kubectl -n microservices exec deploy/gateway-service -- env | grep -i proxy`). |
| `port-forward` "address already in use" | Use another local port: `port-forward svc/gateway-service 8080:3003`. |
| `OOMKilled` | Raise `resources.limits.memory`. |
| Orders vanish | Orders are kept in memory, so they reset when the pod restarts. That's expected. |

Clean up: `kubectl delete -f k8s/` or `minikube delete`.

## Screenshots

See `screenshots/`:
1. `01-get-pods.png`: `kubectl -n microservices get pods -o wide`
2. `02-get-svc.png`: `kubectl -n microservices get svc,endpoints`
3. `03-service-communication.png`: `./scripts/test.sh` output
4. `04-port-forward.png`: port-forward plus curl results
5. `05-logs.png`: `kubectl logs` for the gateway and backends
