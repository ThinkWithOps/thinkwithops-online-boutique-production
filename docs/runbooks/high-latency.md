# Runbook: HighRequestLatency

**Alert:** `HighRequestLatency` (severity: warning)
**Fires when:** p95 request latency for a service exceeds 500ms for 5+ minutes, measured from `traces_spanmetrics_latency_bucket` (derived from OTel spans by the collector's spanmetrics connector — see `observability/otel-collector/config.yaml`).

## 1. Confirm scope

```bash
# Which service, how bad, how long
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# open http://localhost:9090, query:
histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket[5m])) by (le, service_name))
```

Check Grafana's trace view (Tempo datasource) for the affected `service_name` — filter by latency, look at the slowest traces in the last 15 minutes to see which downstream call is dominating the span duration.

## 2. Narrow down the cause

```bash
./scripts/debug/slow-response.sh <service-name>
```

Common causes in this app, roughly in order of likelihood:

- **cartservice → Redis**: connection pool exhaustion or Redis itself under load. `kubectl -n online-boutique logs deploy/cartservice --tail=100`.
- **checkoutservice fan-out**: it calls cart, payment, shipping, and email sequentially — a slow downstream call blocks the whole checkout. Check the Tempo trace waterfall for which child span is longest.
- **CPU throttling**: pod hitting its CPU limit causes request queuing, which looks like latency, not errors.
  ```bash
  kubectl -n online-boutique top pod -l app=<service-name>
  ```
  Compare against the `resources.limits.cpu` set in `helm-chart/values.yaml` / `values-aws-production.yaml`.
- **HPA hasn't scaled yet**: check `kubectl get hpa -n online-boutique` — if replicas are maxed out and CPU is still climbing, this is a capacity problem, not a bug.

## 3. Mitigate

- If CPU-bound and HPA hasn't caught up yet: `kubectl -n online-boutique scale deployment/<service-name> --replicas=<n>` as a manual bridge while HPA/metrics-server catches up.
- If a downstream dependency (Redis, another service) is the actual bottleneck, the fix belongs there — this alert on the caller is a symptom, not the root cause.

## 4. Resolve

Alert clears automatically once p95 latency drops back under 500ms for 5 consecutive minutes — no manual silence needed unless investigation is still ongoing (in which case ack in Slack, don't silence blindly).

## 5. Follow-up

If this fires repeatedly for the same service, that's a signal the alert threshold or the service's resource requests need revisiting — not something to just keep re-acking.
