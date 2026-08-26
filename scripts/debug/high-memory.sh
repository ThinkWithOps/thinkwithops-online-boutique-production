#!/usr/bin/env bash
# Debug helper for a service running hot on memory / at risk of OOMKilled.
# Usage: ./scripts/debug/high-memory.sh <app-label> [namespace]
set -euo pipefail

APP="${1:?Usage: $0 <app-label> [namespace]}"
NAMESPACE="${2:-online-boutique}"

echo "=================================================================="
echo "Memory usage: app=$APP (namespace: $NAMESPACE)"
echo "=================================================================="

echo
echo "--- current usage (requires metrics-server) ---"
kubectl -n "$NAMESPACE" top pod -l "app=$APP" 2>&1 || echo "metrics-server not returning data — check: kubectl get deployment metrics-server -n kube-system"

echo
echo "--- configured requests/limits ---"
kubectl -n "$NAMESPACE" get pods -l "app=$APP" -o jsonpath='{range .items[*]}{.metadata.name}{"\n  requests: "}{.spec.containers[0].resources.requests}{"\n  limits:   "}{.spec.containers[0].resources.limits}{"\n"}{end}'

echo
echo "--- OOMKilled history ---"
kubectl -n "$NAMESPACE" get pods -l "app=$APP" \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.containerStatuses[0].lastState.terminated.reason}{"\n"}{end}' \
  | grep -i oom || echo "(no OOMKilled events found in current pod state)"

echo
echo "--- Prometheus query for the last hour of memory usage (run manually) ---"
echo 'kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090'
echo "then in the Prometheus UI:"
echo "  container_memory_working_set_bytes{namespace=\"$NAMESPACE\", pod=~\"$APP.*\"}"

echo
echo "Next steps:"
echo "  - If usage is consistently near the limit: raise resources.limits.memory"
echo "    for this service in helm-chart/values.yaml or values-aws-production.yaml"
echo "  - If usage climbs steadily over hours/days without dropping: likely a"
echo "    memory leak, not a sizing problem — check for growing goroutine/thread"
echo "    counts or unbounded caches in that service's recent commits"
echo "  - See docs/runbooks/pod-crash-looping.md if this has already OOMKilled"
