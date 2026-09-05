# ArgoCD install (V4, minikube)

Installed once per cluster, cluster-scoped infra -- not managed as a GitOps
Application itself (bootstrapping problem: something has to install ArgoCD
before ArgoCD can manage anything).

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/v2.13.2/manifests/install.yaml

kubectl -n argocd rollout status deploy/argocd-server --timeout=180s
```

Version pinned to `v2.13.2` (stable at time of writing) -- bump deliberately,
not via `stable` tag, so a re-run of this doc is reproducible.

## Access the UI/CLI

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
# browse https://127.0.0.1:8080 (self-signed cert, browser warning expected)

# initial admin password:
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 --decode; echo

argocd login 127.0.0.1:8080 --username admin --password <above> --insecure
```

## Land the project + apps

```bash
kubectl apply -f argocd/project.yaml
kubectl apply -f argocd/applicationset.yaml

kubectl get applications -n argocd
argocd app get online-boutique-dev
```

## Rollout health check for the frontend canary

ArgoCD's built-in resource health checks do not know about `argoproj.io/Rollout`
out of the box. Register Argo Rollouts' Lua health check via the shared
`argocd-cm` ConfigMap (needed for the ArgoCD UI to show `Progressing` /
`Healthy` / `Degraded` correctly during a canary, and for sync waves to gate on
Rollout health):

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-rollouts/master/manifests/argocd/argocd-application-health-config.yaml
```

That manifest patches `argocd-cm` with `resource.customizations.health.argoproj.io_Rollout` --
it's argo-rollouts' own published health-check Lua script, not something
authored in this repo.

## Uninstall / reset

```bash
kubectl delete -f argocd/applicationset.yaml
kubectl delete -f argocd/project.yaml
kubectl delete namespace argocd
```

Deleting the ApplicationSet does not delete the app namespaces or their
workloads by itself unless the generated Applications had
`syncPolicy.automated.prune` and finalizers set -- check
`kubectl get ns online-boutique-dev online-boutique-staging online-boutique-prod`
after and clean up manually if anything is left over.
