# V4 Environment Promotion

How a change moves dev → staging → prod under the ArgoCD setup in
`docs/gitops-architecture.md`.

## Dev (automatic)

1. A commit lands on `main` touching `src/**`. `.github/workflows/gitops-image-bump.yaml` builds, Trivy-scans, pushes the image, and opens a PR bumping `helm-chart/values-dev.yaml`'s `images.tag`.
2. Merging that PR is the only human action. ArgoCD's `online-boutique-dev` Application (`automated: {selfHeal: true, prune: true}`) picks up the change and syncs on its own.
3. Verify:
   ```bash
   kubectl config set-context --current --namespace=online-boutique-dev
   argocd app get online-boutique-dev
   kubectl get pods -n online-boutique-dev
   ```

## Dev → Staging (manual)

Nothing auto-promotes past dev. Promotion is a deliberate values bump + sync:

```bash
# 1. Copy the proven image tag from dev's values file into staging's.
yq eval '.images.tag' helm-chart/values-dev.yaml
yq -i '.images.tag = "<tag from above>"' helm-chart/values-staging.yaml
git add helm-chart/values-staging.yaml
git commit -m "promote <tag> to staging"
git push

# 2. Staging does NOT auto-sync -- trigger it explicitly.
argocd app sync online-boutique-staging
argocd app wait online-boutique-staging --health --timeout 180
```

Confirm the canary in staging behaves as expected (see `docs/rollback.md` for
the abort/rollback procedure) before touching prod.

## Staging → Prod (manual, deliberate)

Same pattern, one step slower and more careful:

```bash
yq eval '.images.tag' helm-chart/values-staging.yaml
yq -i '.images.tag = "<tag from above>"' helm-chart/values-prod.yaml
git add helm-chart/values-prod.yaml
git commit -m "promote <tag> to prod"
git push

argocd app sync online-boutique-prod
argocd app wait online-boutique-prod --health --timeout 300
```

Prod's canary steps use the longest pauses of the three environments
(`values-prod.yaml`) precisely so there's time to watch
`kubectl argo rollouts get rollout frontend -n online-boutique-prod --watch`
between weight increases and abort before 100% if anything looks wrong.

## What "promotion" does NOT do here

- It does not copy replica counts, resource limits, or autoscaling config
  between environments -- those stay independently set per
  `values-{dev,staging,prod}.yaml` on purpose (prod's scale profile isn't
  meant to match dev's).
- It does not touch the V3 observability stack (`observability/`) -- that's
  outside this GitOps flow's scope (see Limitations in
  `docs/gitops-architecture.md`).
- It never runs `kubectl apply`/`helm upgrade` directly against the cluster
  from CI -- every environment change lands via a git commit that ArgoCD then
  syncs (automatically for dev, manually for staging/prod).
