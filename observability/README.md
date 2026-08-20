# Observability stack (v2: load testing & autoscaling)

Metrics stack backing `karpenter/`, `kubernetes-manifests-aws/hpa.yaml`, and
`k6/` -- lets you *watch* autoscaling happen during a load test instead of
just trusting it did.

## Install order

```sh
# 1. Prometheus + kube-state-metrics (pod/node/HPA object metrics)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f observability/prometheus/values.yaml

# 2. OTel collector config (traces from the app's existing
#    opentelemetrycollector Deployment, exported as Prometheus metrics too)
kubectl create configmap otel-collector-config -n online-boutique \
  --from-file=config.yaml=observability/otel-collector/config.yaml \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n online-boutique rollout restart deployment/opentelemetrycollector

# 3. Grafana (bundled in kube-prometheus-stack is disabled here so the
#    dashboard JSON stays in git; install standalone or re-enable it in
#    prometheus/values.yaml and skip this step)
helm install grafana grafana/grafana \
  --namespace monitoring \
  --set datasources."datasources\.yaml".apiVersion=1 \
  --set-string datasources."datasources\.yaml".datasources[0].name=Prometheus \
  --set-string datasources."datasources\.yaml".datasources[0].type=prometheus \
  --set-string datasources."datasources\.yaml".datasources[0].url=http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090

# Import the dashboard: Grafana UI -> Dashboards -> Import ->
# upload observability/grafana/dashboard-autoscaling.json
```

## What the dashboard shows

`dashboard-autoscaling.json` -- requests/sec, pod count per service, node
count, HPA current-vs-target CPU utilization, per-pod CPU & memory. Run
`k6/100k-users.js` against the frontend and watch panels 2/3 climb as HPA
and Karpenter react.

Note: the requests/sec panel proxies off `otelcol_receiver_accepted_spans`
(the app doesn't expose a native Prometheus `/metrics` requests-total
counter) -- close enough to see the load shape during a demo, not a
production-grade RED metric.
