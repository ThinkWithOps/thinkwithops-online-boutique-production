# k6 load tests

`100k-users.js` ramps virtual users 0 -> 100,000 against the frontend Service,
walking the browse -> add-to-cart -> checkout path. Pairs with
`kubernetes-manifests-aws/hpa.yaml` (pod-level scaling) and `karpenter/`
(node-level scaling) -- watch both scale out during the run.

## Run locally

```sh
FRONTEND_URL=http://<frontend-lb-or-ingress-hostname> k6 run k6/100k-users.js
```

Get the URL with `kubectl -n online-boutique get svc frontend-external` (or
the ALB Ingress hostname if using `addons/aws-load-balancer-controller`).

## Run in-cluster (recommended for the full 100k profile --
local machine/network is usually the real bottleneck otherwise)

```sh
kubectl create namespace k6 --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap k6-script -n k6 --from-file=k6/100k-users.js
kubectl run k6 -n k6 --image=grafana/k6:latest --restart=Never \
  --env="FRONTEND_URL=http://frontend.online-boutique.svc.cluster.local" \
  --overrides='{"spec":{"containers":[{"name":"k6","image":"grafana/k6:latest","command":["k6","run","/scripts/100k-users.js"],"volumeMounts":[{"name":"script","mountPath":"/scripts"}],"env":[{"name":"FRONTEND_URL","value":"http://frontend.online-boutique.svc.cluster.local"}]}],"volumes":[{"name":"script","configMap":{"name":"k6-script"}}]}}'
kubectl logs -n k6 -f k6
```
