#!/usr/bin/env bash
# Installs the full V3 SRE/observability stack on top of an already-running
# online-boutique deployment on minikube: Prometheus + Alertmanager, alert
# rules, Loki + Promtail, Tempo, and the extended otel-collector config.
#
# Prereqs:
#   - minikube running, kubectl pointed at it
#   - the app itself already deployed in the online-boutique namespace
#     (helm install online-boutique helm-chart/ --namespace online-boutique)
#
# Usage:
#   ./scripts/install-observability-stack.sh
#
# Idempotent -- safe to re-run; uses `helm upgrade --install` throughout.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

echo "=================================================================="
echo "0/5 -- checking cluster connectivity"
echo "=================================================================="
if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "kubectl can't reach the cluster. Try:"
  echo "  minikube status"
  echo "  minikube update-context"
  exit 1
fi
echo "OK -- kubectl reaches $(kubectl config current-context) cluster."

echo
echo "=================================================================="
echo "1/5 -- namespace + Slack webhook secret"
echo "=================================================================="
# --validate=false: kubectl's client-side schema validation downloads the
# full OpenAPI spec from the apiserver on every apply -- on minikube this
# occasionally fails transiently even when the cluster itself is reachable
# (see docs/runbooks/pod-crash-looping.md-adjacent flakiness notes). The
# manifests here are static and known-good, so skipping validation is safe.
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply --validate=false -f -

if kubectl -n monitoring get secret alertmanager-slack-webhook >/dev/null 2>&1; then
  echo "Slack webhook secret already exists -- leaving it as-is."
else
  echo "No Slack webhook secret found."
  echo "  Applying the example placeholder -- Alertmanager will still fire"
  echo "  internally, but Slack delivery will fail until you replace the URL:"
  echo "    kubectl -n monitoring edit secret alertmanager-slack-webhook"
  kubectl apply --validate=false -f observability/alertmanager/slack-webhook-secret.example.yaml
fi

echo
echo "=================================================================="
echo "2/5 -- Helm repos"
echo "=================================================================="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts >/dev/null
helm repo update

echo
echo "=================================================================="
echo "3/5 -- Prometheus + Alertmanager + alert rules"
echo "=================================================================="
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f observability/prometheus/values.yaml \
  -f observability/alertmanager/values.yaml \
  --wait --timeout 5m

kubectl apply --validate=false -f observability/prometheus/alert-rules.yaml

echo
echo "=================================================================="
echo "4/5 -- Loki + Promtail, Tempo"
echo "=================================================================="
helm upgrade --install loki grafana/loki-stack \
  --namespace monitoring \
  -f observability/loki/values.yaml \
  --wait --timeout 5m

helm upgrade --install tempo grafana/tempo \
  --namespace monitoring \
  -f observability/tempo/values.yaml \
  --wait --timeout 5m

echo
echo "=================================================================="
echo "5/5 -- otel-collector config (traces -> Tempo, spanmetrics -> Prometheus)"
echo "=================================================================="
kubectl create configmap otel-collector-config -n online-boutique \
  --from-file=config.yaml=observability/otel-collector/config.yaml \
  --dry-run=client -o yaml | kubectl apply --validate=false -f -
kubectl apply --validate=false -f observability/otel-collector/deployment.yaml
kubectl -n online-boutique rollout restart deployment/opentelemetrycollector
kubectl -n online-boutique rollout status deployment/opentelemetrycollector --timeout=2m

echo
echo "=================================================================="
echo "Done. Verify:"
echo "=================================================================="
echo "  kubectl -n monitoring get pods"
echo "  kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090"
echo "  kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093"
echo
echo "If any monitoring pod crash-loops on minikube's limited resources,"
echo "see docs/runbooks/pod-crash-looping.md (probe timeoutSeconds/"
echo "initialDelaySeconds is the most likely cause, same as the app pods)."
