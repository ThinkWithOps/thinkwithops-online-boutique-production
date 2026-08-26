# Runbook: PodCrashLooping / PodNotReady

**Alerts:**
- `PodCrashLooping` (severity: critical) — a container restarted more than 3 times in 15 minutes
- `PodNotReady` (severity: warning) — a pod has not reached `Ready` for 10+ minutes

## 1. Confirm scope

```bash
kubectl -n online-boutique get pods -o wide
kubectl -n online-boutique get pod <pod-name> -o jsonpath='{.status.containerStatuses[*].restartCount}'
```

## 2. Get the reason

```bash
./scripts/debug/pod-crash.sh <pod-name>
```

This script runs, in order: `kubectl describe pod` (check the `Last State` / `Reason` field first — `OOMKilled`, `Error`, `CrashLoopBackOff` all mean different things), then `kubectl logs --previous` (the crashed container's last output, not the current restart's), then a live log tail.

Common causes in this app:

- **OOMKilled**: container hit its memory limit. `kubectl -n online-boutique describe pod <pod-name> | grep -A3 "Last State"`. Fix: raise `resources.limits.memory` for that service in `helm-chart/values.yaml` / `values-aws-production.yaml`, or find the actual leak.
- **CrashLoopBackOff from a bad config/env var**: check `kubectl -n online-boutique logs --previous <pod-name>` for a startup error — missing env var, bad gRPC target address, etc.
- **Liveness probe failing**: the process is up but not responding on the expected port/path in time. `kubectl -n online-boutique describe pod <pod-name> | grep -A5 Liveness`.
- **ImagePullBackOff** (shows as NotReady, not crash-looping): wrong image tag/ECR auth. `kubectl -n online-boutique describe pod <pod-name> | grep -A3 Events`.
- **cartservice specifically**: crash-looping here is very often a Redis connectivity issue at startup, not a code bug — check `redis-cart` is `Running` first.

## 3. Mitigate

- **OOMKilled**: bump the memory limit and `kubectl -n online-boutique rollout restart deployment/<service-name>`.
- **Bad config from a recent deploy**: `kubectl -n online-boutique rollout undo deployment/<service-name>`.
- **Dependency down** (e.g. Redis): fix the dependency; the crash-looping pod will recover on its own once it can connect.

## 4. Resolve

`PodCrashLooping` clears once the restart count stops climbing for 15 minutes. `PodNotReady` clears once the pod reports `Ready`. Don't manually silence either — if you've applied a fix, watch `kubectl get pods -w` until it settles instead.

## 5. Follow-up

A pod that's crash-looped more than once for the same underlying reason within a week is a sign the fix above was a workaround, not a root-cause fix — file it, don't just re-run the same mitigation each time.
