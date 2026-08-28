# Observability stack (v2: autoscaling metrics, v3: full SRE/incident-response layer)

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
#    dashboard JSON stays in git). observability/grafana/values.yaml wires
#    up all three datasources at once (Prometheus, Loki, Tempo) -- this
#    supersedes the Prometheus-only inline --set command from earlier V2
#    docs, since Loki/Tempo didn't exist yet at that point.
helm install grafana grafana/grafana \
  --namespace monitoring \
  -f observability/grafana/values.yaml

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

---

## v3: SRE / observability + incident response (minikube target)

Adds centralized logging, distributed tracing, real RED metrics, alerting,
and incident-response docs/scripts on top of the v2 metrics stack above --
all local, no cloud dependency. Tag: `v3.0-sre-observability`.

| Piece | What it does |
|---|---|
| `loki/` | Loki + Promtail (`grafana/loki-stack` chart) -- centralized logs for all 11 services, filesystem storage |
| `tempo/` | Grafana Tempo (single-binary) -- distributed tracing, filesystem storage |
| `otel-collector/config.yaml` | Extended: traces now export to Tempo; a `spanmetrics` connector derives RED metrics (latency/error-rate) from spans, since the app has no native ones |
| `prometheus/alert-rules.yaml` | `PrometheusRule`: p95 latency > 500ms, error rate > 5%, pod crash-looping, pod not-ready |
| `alertmanager/` | Alertmanager route + Slack receiver, webhook supplied via Secret (never committed) |
| `../docs/runbooks/` | One runbook per alert above |
| `../scripts/debug/` | kubectl helper scripts for the 4 incident types the alerts cover |

### Prereq: get the app itself running on minikube

V1/V2's Helm install steps target ECR-hosted images on EKS. On minikube
there's no ECR/build step needed at all — `helm-chart/values.yaml`'s
default `images.repository` already points at Google's own public image
registry, so the base chart deploys as-is with no AWS overlay:

```sh
minikube start --cpus=4 --memory=8192   # observability stack below needs
                                          # the extra headroom -- Loki, Tempo,
                                          # Prometheus, Grafana, Alertmanager,
                                          # Promtail all running at once

kubectl create namespace online-boutique --dry-run=client -o yaml | kubectl apply -f -

helm install online-boutique helm-chart/ \
  --namespace online-boutique

kubectl -n online-boutique get pods -w   # wait for all 11 to be Running

# Access the storefront (minikube has no cloud LoadBalancer)
minikube service frontend-external -n online-boutique
# or: kubectl -n online-boutique port-forward svc/frontend-external 8080:80
```

No `values-aws-production.yaml` overlay, no IRSA annotations, no ECR login
-- those are AWS-specific and don't apply here. Once `kubectl get pods`
shows 11/11 `Running`, move on to the observability stack below.

### Install order (minikube)

Or run it in one shot: `./scripts/install-observability-stack.sh` (same steps below, scripted — idempotent, safe to re-run).

```sh
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# 1. Prometheus + Alertmanager + kube-state-metrics + node-exporter,
#    with the Slack-wired Alertmanager overlay
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f observability/alertmanager/slack-webhook-secret.example.yaml   # edit the URL first, or create the Secret directly (see file header)
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  -f observability/prometheus/values.yaml \
  -f observability/alertmanager/values.yaml
kubectl apply -f observability/prometheus/alert-rules.yaml

# 2. Loki + Promtail
helm install loki grafana/loki-stack \
  --namespace monitoring \
  -f observability/loki/values.yaml

# 3. Tempo
helm install tempo grafana/tempo \
  --namespace monitoring \
  -f observability/tempo/values.yaml

# 4. Apply the extended collector config and its local Deployment/Service
#    (traces -> Tempo, spanmetrics -> Prometheus)
kubectl create configmap otel-collector-config -n online-boutique \
  --from-file=config.yaml=observability/otel-collector/config.yaml \
  --dry-run=client -o yaml | kubectl apply --validate=false -f -
kubectl apply --validate=false -f observability/otel-collector/deployment.yaml
kubectl -n online-boutique rollout restart deployment/opentelemetrycollector
kubectl -n online-boutique rollout status deployment/opentelemetrycollector --timeout=2m

# 5. Turn on tracing IN the app itself -- helm-chart/values.yaml's
#    opentelemetryCollector.enabled=true wires COLLECTOR_SERVICE_ADDR,
#    OTEL_SERVICE_NAME, and ENABLE_TRACING into every service. Without this
#    step the collector/Tempo/spanmetrics pipeline above has nothing to
#    receive -- the app never sends OTLP traces on its own.
helm upgrade online-boutique helm-chart/ -n online-boutique --reuse-values \
  --set opentelemetryCollector.enabled=true --wait --timeout 5m

# 6. Grafana -- observability/grafana/values.yaml wires up all three
#    datasources at once (Prometheus, Loki, Tempo):
helm install grafana grafana/grafana \
  --namespace monitoring \
  -f observability/grafana/values.yaml
# then import observability/grafana/dashboard-autoscaling.json (Grafana UI ->
# Dashboards -> Import), plus build/import panels for logs (Loki) and
# traces (Tempo) as needed.
```

### Troubleshooting the installer on Windows/minikube

If the preflight fails with `x509: certificate signed by unknown authority`, first run:

```powershell
kubectl get pods -n online-boutique
kubectl auth can-i get pods -n online-boutique
```

When both fail against a loopback API endpoint such as `https://127.0.0.1:<port>`, temporarily disable AVG Web Shield/HTTPS scanning and retry immediately. If access returns, the cluster is healthy and AVG is replacing minikube's TLS certificate; add an exception for `kubectl`/loopback HTTPS. Do not use `minikube delete` for this symptom.

On the first install, Helm may exceed its five-minute wait while pulling Prometheus, Loki, Promtail, or Tempo images. Check `kubectl -n monitoring get pods` and recent events. If containers are progressing from `ContainerCreating` to `Running`, rerun the installer after the pulls finish; every step uses upgrade/apply semantics.

#### Application pods restart after installing observability

Check whether Kubernetes, rather than the application, is killing containers after probe timeouts:

```powershell
kubectl -n online-boutique get events --sort-by=.lastTimestamp
docker stats minikube --no-stream
docker inspect minikube --format "CPUs={{.HostConfig.NanoCpus}} Memory={{.HostConfig.Memory}}"
```

On a 2-CPU/4-GB profile, the application and observability stack can saturate the node, causing one-second gRPC/HTTP probes and even etcd requests to time out. Exit code `137` combined with `Container server failed liveness probe, will be restarted` indicates a probe-triggered kill; it is not by itself evidence of an application crash or OOM.

The Helm chart mitigates this by using five-second readiness/liveness timeouts and requiring six consecutive liveness failures before restart. `emailservice` and `recommendationservice` also have startup probes that allow up to five minutes for Python cold starts. Deploy probe changes sequentially when the node is already pressured, and temporarily scale synthetic traffic down if needed:

```powershell
kubectl -n online-boutique scale deployment/loadgenerator --replicas=0
helm upgrade online-boutique helm-chart/ -n online-boutique --reuse-values --wait --timeout 10m
kubectl -n online-boutique scale deployment/loadgenerator --replicas=1
kubectl -n online-boutique get pods
```

The Docker driver cannot resize CPU or memory for an existing Minikube profile. Do not delete a cluster containing work merely to clear restart counters; counters are historical and reset when replacement pods roll out. For a future disposable profile, allocate 4 CPUs and about 7.5 GB RAM before installing the full stack.

### Verifying it end to end

```bash
# Metrics: RED metrics now exist as real series, not a proxy
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090
# query: traces_spanmetrics_calls_total

# Logs: every service's logs queryable in one place
# Grafana -> Explore -> Loki -> {namespace="online-boutique", app="cartservice"}

# Traces: full request waterfall across services
# Grafana -> Explore -> Tempo -> search by service.name

# Alerts: force one to fire and confirm it reaches Slack
kubectl -n online-boutique delete pod -l app=cartservice --grace-period=0 --force
# wait for PodCrashLooping/PodNotReady to appear in:
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093
```

See `docs/runbooks/` for what to do once an alert actually fires, and
`scripts/debug/` for the kubectl commands each runbook points at.
