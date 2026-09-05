# V4 Rollback Procedures

Two independent rollback paths in this GitOps setup: reverting a git commit
(ArgoCD-level) and aborting a canary rollout (Argo Rollouts-level). They solve
different problems -- know which one applies.

## Path 1 -- Git revert (bad config/image landed and ArgoCD synced it)

If a bad `images.tag` or Helm value change merged and an environment picked it
up (auto for dev, or a staging/prod sync already ran):

```bash
git log --oneline -5 -- helm-chart/values-dev.yaml   # find the bad commit
git revert <bad-commit-sha>
git push
```

- **Dev**: automated sync picks up the revert on its own. Watch it recover:
  ```bash
  argocd app get online-boutique-dev --watch
  ```
- **Staging/prod**: manual sync required, same as any other promotion:
  ```bash
  argocd app sync online-boutique-staging   # or -prod
  ```

Expected before/after: `argocd app get` shows `Degraded` (pods
`ImagePullBackOff`/`CrashLoopBackOff` from the bad tag) → after the revert
syncs → `Synced` / `Healthy`.

## Path 2 -- Abort/rollback a canary in progress (frontend only)

While `kubectl argo rollouts get rollout frontend -n <ns> --watch` shows a
step in progress (`setWeight` 10 or 50, not yet 100):

```bash
# Abort immediately -- routes 100% of traffic back to the last stable ReplicaSet.
kubectl argo rollouts abort frontend -n <ns>

# Then explicitly roll back the Rollout resource itself to the previous revision.
kubectl argo rollouts undo frontend -n <ns>

# Confirm.
kubectl argo rollouts get rollout frontend -n <ns>
```

`abort` stops the canary promotion; `undo` is what actually moves the
`Rollout`'s desired state back to the prior stable revision so the next sync
doesn't just re-attempt the same bad promotion. Run both.

## Which path for which failure

| Symptom | Path |
|---|---|
| New image doesn't start at all (`ImagePullBackOff`, `CrashLoopBackOff`), whole environment Degraded | Path 1 (git revert) |
| Frontend canary mid-promotion, new version is up but behaving badly (error rate, latency -- checkable live in the V3 Grafana dashboards) | Path 2 (abort + undo) |
| Both at once (bad canary AND you already promoted past it) | Path 2 first (stop the bleeding), then Path 1 (fix the source of truth so the next sync doesn't repeat it) |

## Monitoring stays up throughout

The V3 stack (Grafana/Prometheus/Loki/Tempo) is not managed by ArgoCD and is
unaffected by any of the above -- it keeps scraping/collecting from whatever
pods exist in each namespace during a rollback or abort. Use it to confirm
recovery, not just `kubectl`/`argocd` status:

```bash
kubectl -n monitoring port-forward svc/grafana 3000:80
# browse http://127.0.0.1:3000 -- request rate/error rate/latency panels
# should show the dip-and-recover shape across a bad-deploy-then-rollback cycle
```
