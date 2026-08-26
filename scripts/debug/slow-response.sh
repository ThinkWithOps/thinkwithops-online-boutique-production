#!/usr/bin/env bash
# Debug helper for a service with high latency (HighRequestLatency alert).
# Usage: ./scripts/debug/slow-response.sh <app-label> [namespace]
set -euo pipefail

APP="${1:?Usage: $0 <app-label> [namespace]}"
NAMESPACE="${2:-online-boutique}"

echo "=================================================================="
echo "Latency investigation: app=$APP (namespace: $NAMESPACE)"
echo "=================================================================="

echo
echo "--- CPU usage vs. limit (throttling shows up as latency, not errors) ---"
kubectl -n "$NAMESPACE" top pod -l "app=$APP" 2>&1 || echo "metrics-server not returning data"
kubectl -n "$NAMESPACE" get pods -l "app=$APP" -o jsonpath='{range .items[*]}{.metadata.name}{"\n  cpu limit: "}{.spec.containers[0].resources.limits.cpu}{"\n"}{end}'

echo
echo "--- HPA status (is it maxed out and still under pressure?) ---"
kubectl -n "$NAMESPACE" get hpa 2>&1 | grep -E "^NAME|$APP" || echo "(no matching HPA — check kubernetes-manifests-aws/hpa.yaml)"

echo
echo "--- recent restarts (a pod mid-restart looks slow to callers) ---"
kubectl -n "$NAMESPACE" get pods -l "app=$APP" -o jsonpath='{range .items[*]}{.metadata.name}{"\trestarts="}{.status.containerStatuses[0].restartCount}{"\n"}{end}'

echo
echo "--- p95 latency query (run in Prometheus UI) ---"
echo 'kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090'
echo "then:"
echo "  histogram_quantile(0.95, sum(rate(traces_spanmetrics_latency_bucket{service_name=\"$APP\"}[5m])) by (le))"

echo
echo "--- trace waterfall (find the actual slow downstream span) ---"
echo "Grafana -> Explore -> Tempo datasource -> search by service.name=\"$APP\","
echo "sort by duration descending, open the slowest trace in the last 15m."

echo
echo "Next: see docs/runbooks/high-latency.md"
