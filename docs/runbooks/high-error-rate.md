# Runbook: HighErrorRate

**Alert:** `HighErrorRate` (severity: critical)
**Fires when:** more than 5% of a service's requests return an error status for 5+ minutes, measured from `traces_spanmetrics_calls_total{status_code=...}` (see `observability/otel-collector/config.yaml`'s spanmetrics connector).

## 1. Confirm scope

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# open http://localhost:9090, query:
sum(rate(traces_spanmetrics_calls_total{status_code=~"STATUS_CODE_ERROR|2"}[5m])) by (service_name)
/
sum(rate(traces_spanmetrics_calls_total[5m])) by (service_name)
```

Identify: one service, or cascading across several (a downstream failure showing up as errors in every service that calls it)?

## 2. Narrow down the cause

```bash
kubectl -n online-boutique logs deploy/<service-name> --tail=200
./scripts/debug/pod-crash.sh <service-name>   # rules out crash-looping as the actual cause
```

Common causes in this app:

- **cartservice ↔ Redis connectivity**: if `redis-cart` is unreachable, cartservice errors on every add-to-cart/checkout call. `kubectl -n online-boutique get pods -l app=redis-cart`.
- **checkoutservice's downstream fan-out**: a single failing dependency (payment, shipping, email) surfaces as checkoutservice errors even though checkoutservice itself is healthy. Check the Tempo trace for the actual failing span, not just the outermost one.
- **Recent deploy**: `kubectl -n online-boutique rollout history deployment/<service-name>` — did this start right after an image update?
- **Resource limits / OOM**: an OOMKilled pod restarting mid-request looks like a burst of errors. Cross-check with `PodCrashLooping` — if both are firing together, fix the crash first (see `docs/runbooks/pod-crash-looping.md`).

## 3. Mitigate

- **Roll back** if a recent deploy is the trigger:
  ```bash
  kubectl -n online-boutique rollout undo deployment/<service-name>
  ```
- **Restart** if it's a stuck/wedged process rather than a code issue:
  ```bash
  kubectl -n online-boutique rollout restart deployment/<service-name>
  ```
- If the root cause is a downstream dependency, fix or restart that instead of the service the alert fired on.

## 4. Resolve

Clears automatically once the error ratio drops back under 5% for 5 consecutive minutes.

## 5. Follow-up

Critical-severity alerts route to `#online-boutique-alerts-critical` with a 30-minute repeat interval (see `observability/alertmanager/values.yaml`) — if this is still open after a rollback/restart, escalate rather than waiting out the repeat.
