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

Install Argo Rollouts in the namespace expected by its ClusterRoleBinding:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts \
  -f https://github.com/argoproj/argo-rollouts/releases/download/v1.8.3/install.yaml
kubectl -n argo-rollouts rollout status deployment/argo-rollouts --timeout=180s
```

Do not apply this manifest without `-n argo-rollouts`: namespaced resources
otherwise land in `default`, while the bundled ClusterRoleBinding still points
at `system:serviceaccount:argo-rollouts:argo-rollouts`. The controller then
fails with `cannot get resource "configmaps"`.

ArgoCD v2.13.2 correctly reported the Rollout as Progressing, Degraded after
an abort, and Healthy after undo during the verified run; no external Lua
health-config URL is required. The previously documented upstream `master`
URL returned HTTP 404 and was removed.

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
