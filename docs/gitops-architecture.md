# V4 GitOps Architecture

Builds on [V3 — SRE Observability](../README.md) (tag `v3.0-sre-observability`).
Adds ArgoCD-driven GitOps delivery across three simulated environments on the
**same** minikube cluster -- not three clusters. Tag: `v4.0-gitops-argocd`.

## Resource requirement (found the hard way)

V3's `minikube start --cpus=4 --memory=8192` (actually running with a ~3.9GiB
container cap on this machine, per `docker stats`) was **not enough** once
ArgoCD (6 pods), Argo Rollouts, and Sealed Secrets were added on top of the
existing V3 stack + app namespace: `cri-dockerd` started timing out and pods
sat in `ContainerCreating`/`Pending` indefinitely under the combined load.
Fixed by resizing to:

```bash
minikube stop
minikube start --cpus=6 --memory=6500
```

`--memory=6500` (not more) because Docker Desktop's own backend VM on this
machine is capped at 7.66GiB total (`docker info`) -- asking minikube for
more than that doesn't fit and the container gets OOM-killed by the host
instead. If your Docker Desktop has more RAM allocated, scale this up
accordingly; if it has less, expect the same `ContainerCreating` stall this
repo hit until you either free up memory or shrink what runs at once (e.g.
generate only the dev Application first, see `docs/environment-promotion.md`).

## Why one cluster, three namespaces

The repo's minikube target already runs the full app + V3 observability stack
on a single laptop-class VM. Three real clusters would multiply that resource
cost for no architectural benefit this repo needs to demonstrate -- namespace
isolation plus a real AppProject restricting destinations proves the same
GitOps promotion model (independent sync policy, independent replica/scaling
config, independent Application health) that three clusters would, at a
fraction of the resource footprint. This is the same reasoning V3 used for
picking minikube over a second EKS cluster.

## Components

| Component | Role | Installed |
|---|---|---|
| ArgoCD | GitOps controller, ApplicationSet, sync waves, health checks | `argocd/install/README.md` |
| Argo Rollouts | Canary controller for `frontend` | referenced in `argocd/install/README.md` |
| Sealed Secrets | Controller plus generic workflow for future application secrets; no real payload is required or committed | `sealed-secrets/install/README.md` |
| Helm chart env overlays | Per-namespace replica/resource/autoscaling config | `helm-chart/values-{dev,staging,prod}.yaml` |

## Namespaces

- `online-boutique-dev` -- automated sync, selfHeal, prune all on. Fast feedback loop.
- `online-boutique-staging` -- manual sync only. Rehearses prod's canary/rollback without prod's blast radius.
- `online-boutique-prod` -- manual sync only, prune off. A stray manually-applied resource during an incident is never silently deleted.

## AppProject (`argocd/project.yaml`)

Restricts every generated Application to:
- **One source repo**: this GitHub repo, nothing else.
- **Three destinations**: the cluster-local API server, scoped to exactly the three namespaces above (not a wildcard).
- **A fixed resource whitelist**: core workload kinds + `argoproj.io/Rollout` + `bitnami.com/SealedSecret`. Core `Namespace` is the only cluster-scoped permission, required by `CreateNamespace=true`. ArgoCD, Argo Rollouts, and Sealed Secrets remain bootstrap infrastructure outside this project.

## ApplicationSet (`argocd/applicationset.yaml`)

A `list` generator produces one Application per environment (`online-boutique-dev/staging/prod`), each pointed at `helm-chart/` with `values.yaml` + `values-<env>.yaml` layered.

**The selfHeal nuance**: ArgoCD only acts on `selfHeal`/`prune` under an
`automated` sync policy. Dev's generated Application gets a full `automated:`
block via a `templatePatch` (needed because a bare `{{- if }}` cannot span
structured YAML fields directly in `template.spec` -- confirmed by a local
`yaml.safe_load` failure on the first draft of this file, then fixed with
ArgoCD's `templatePatch` string-templating feature). Staging/prod get no
`automated:` block at all, so "manual promotion" and "selfHeal enabled" are
both literally true: the field is set for when a human syncs, but nothing
happens without that human action.

## Sync waves

Applied via `argocd.argoproj.io/sync-wave` annotations directly in the Helm
templates (`helm-chart/templates/*.yaml`), since this repo has no central
annotations file that all workloads inherit from:

| Wave | Resources |
|---|---|
| (namespace) | Handled by ArgoCD's `CreateNamespace=true` sync option, ahead of any wave |
| `0` | `redis-cart` (cartservice's dependency) |
| `1` | adservice, currencyservice, emailservice, paymentservice, productcatalogservice, recommendationservice, shippingservice, loadgenerator -- no intra-app dependency |
| `2` | cartservice (depends on redis-cart from wave 0) |
| `3` | checkoutservice, frontend/frontend-rollout (depend on most of the above) |
| (monitoring) | V3's `observability/` stack stays outside this Helm chart's scope -- see Limitations |
| (ingress) | N/A -- no ingress controller installed on this minikube target |

## Argo Rollouts canary (frontend)

`helm-chart/templates/frontend-rollout.yaml` renders an `argoproj.io/v1alpha1`
`Rollout` instead of `templates/frontend.yaml`'s plain `Deployment`, gated by
`frontend.rollouts.enabled` (off by default; on in all three env overlays).
Steps: `setWeight: 10` → pause → `setWeight: 50` → pause → `setWeight: 100`,
configured per environment (`values-dev/staging/prod.yaml` — longest pauses in
prod, shortest in dev).

## Verified execution (2026-09-08)

The original Kubernetes v1.35.1 profile did not serve `/openapi/v2`. A fresh,
separate profile preserved the old cluster and resolved the ArgoCD schema-diff
blocker:

```text
$ minikube start -p v4-gitops --driver=docker --kubernetes-version=v1.30.0 --cpus=6 --memory=6500
$ kubectl get nodes
NAME        STATUS   ROLES           VERSION
v4-gitops   Ready    control-plane   v1.30.0
$ kubectl get --raw=/openapi/v2
{"swagger":"2.0","info":{"title":"Kubernetes","version":"v1.30.0"},...}
```

ArgoCD v2.13.2, Argo Rollouts v1.8.3, and Sealed Secrets v0.27.1 were installed.
After correcting Rollouts' namespace and disabling the unavailable local
LoadBalancer Service in V4 overlays, dev completed automated reconciliation:

```text
NAME                  SYNC STATUS   HEALTH STATUS   REVISION
online-boutique-dev   Synced        Healthy         1d3c10b6...

NAME           DESIRED   READY
adservice      5         1
SYNC        HEALTH
OutOfSync   Progressing

NAME           DESIRED   READY
adservice      1         1
SYNC     HEALTH    PHASE
Synced   Healthy   Succeeded
```

The 5→1 result is live proof of dev `selfHeal`. Staging/prod remained
`OutOfSync/Missing`, proving their manual-sync policy did not auto-deploy them.
Bad-image, Git-revert, canary, and abort/undo evidence is in
[`rollback.md`](rollback.md).

## Limitations (disclosed, not hidden — same discipline as V3)

- **No real SealedSecret is committed or decrypted end-to-end.** V4 uses no
  Slack integration and has no real application secret to seal. The controller
  reached Ready and the generic workflow is documented; inventing a fake
  production secret would not prove useful secret delivery.

- **No service mesh or ingress controller installed** on this minikube target,
  so the canary uses Rollouts' basic strategy without `trafficRouting`: weight
  is approximated by replica count against the existing frontend `Service`,
  not exact percentage-based traffic splitting. A 10% step with 1 replica out
  of 3 total is closer to 33% of real traffic, not 10%. Documented, not
  disguised.
- **selfHeal is not "always-on drift correction."** It only fires under
  automated sync (dev only). Staging/prod drift surfaces as `OutOfSync` and
  waits for a human.
- **The V3 observability stack (`observability/`) is not inside this Helm
  chart's ArgoCD-managed scope.** It continues to be applied the way V3
  documented (`kubectl apply`/Helm outside this GitOps flow). A second
  ArgoCD Application pointed at `observability/` as a `Directory` source is a
  natural next step, not done in this pass.
- **The GitOps CI workflow (`gitops-image-bump.yaml`) builds/pushes to ECR**
  (reusing the existing AWS OIDC role from V1), because that's the only image
  registry this repo has infra for. Local Minikube ECR pull authentication is
  not configured, so this delivery path was not verified end-to-end here.
  Also, the current workflow bumps a chart-wide tag after building only changed
  services; it needs per-service image overrides (or must build every service
  at the shared tag) before production use.
