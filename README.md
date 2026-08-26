# Online Boutique — Production AWS EKS Deployment

> A production-grade AWS DevOps layer (Terraform, EKS, ECR, Helm, GitHub Actions OIDC CI/CD) built on top of Google's Online Boutique microservices demo.

![Terraform](https://img.shields.io/badge/Terraform-1.6+-844FBA?style=flat&logo=terraform&logoColor=white)
![AWS EKS](https://img.shields.io/badge/AWS-EKS-FF9900?style=flat&logo=amazoneks&logoColor=white)
![ECR](https://img.shields.io/badge/AWS-ECR-FF9900?style=flat&logo=amazonaws&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-1.30-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Helm](https://img.shields.io/badge/Helm-3.15+-0F1689?style=flat&logo=helm&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/CI%2FCD-GitHub_Actions_OIDC-2088FF?style=flat&logo=githubactions&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-Multi--stage-2496ED?style=flat&logo=docker&logoColor=white)
![HPA](https://img.shields.io/badge/HPA-Pod_Autoscaling-326CE5?style=flat&logo=kubernetes&logoColor=white)
![Karpenter](https://img.shields.io/badge/Karpenter-Node_Autoscaling-4285F4?style=flat&logo=kubernetes&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-Monitoring-E6522C?style=flat&logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-Dashboards-F46800?style=flat&logo=grafana&logoColor=white)
![k6](https://img.shields.io/badge/k6-Load_Testing-7D64FF?style=flat&logo=k6&logoColor=white)
![Loki](https://img.shields.io/badge/Loki-Logging-F46800?style=flat&logo=grafana&logoColor=white)
![Tempo](https://img.shields.io/badge/Tempo-Tracing-F46800?style=flat&logo=grafana&logoColor=white)
![Alertmanager](https://img.shields.io/badge/Alertmanager-Slack_Alerts-E6522C?style=flat&logo=prometheus&logoColor=white)
![Minikube](https://img.shields.io/badge/Minikube-Local_Cluster-326CE5?style=flat&logo=kubernetes&logoColor=white)
![License](https://img.shields.io/badge/App_License-Apache_2.0-green?style=flat)

---

## Table of Contents

- [Project Description](#project-description)
- [Video Series](#video-series)
- [Attribution](#attribution)
- [V1 Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Microservices](#microservices)
- [V1 — EKS Deployment](#v1--eks-deployment)
- [Prerequisites](#prerequisites)
- [How to Deploy](#how-to-deploy)
- [Project Structure (AWS layer)](#project-structure-aws-layer)
- [V2 — Load Testing + Autoscaling](#v2--load-testing--autoscaling)
- [V2 Architecture](#v2-architecture)
- [V3 — SRE / Observability + Incident Response](#v3--sre--observability--incident-response)
- [Cost Notes](#cost-notes)
- [What This Teaches](#what-this-teaches)
- [Challenges](#challenges)
- [Cleanup](#cleanup)
- [Command Reference](#command-reference)
- [GCP Path (original, untouched)](#gcp-path-original-untouched)

---

## Project Description

This repo takes Google's **Online Boutique** — an 11-service gRPC microservices e-commerce demo in Go, C#, Node.js, Python, and Java — and adds a full production AWS deployment layer around it, without touching a single line of application code.

Everything under `terraform-aws/`, `addons/`, `kubernetes-manifests-aws/`, `helm-chart/values-aws-production.yaml`, and `.github/workflows/aws-eks-deploy.yaml` is new, purpose-built infrastructure-as-code. The original GCP/GKE deployment assets (`terraform/`, `kubernetes-manifests/`, `helm-chart/templates/`) ship unmodified alongside it, so both cloud targets coexist in the same repo.

Built and verified end-to-end on a real AWS account: VPC → EKS cluster → ECR → Helm release → 11/11 pods `Running`, reachable via a live frontend URL (plain Kubernetes `LoadBalancer` Service — no ALB Ingress installed this run, see [Architecture](#architecture)).

---

## Video Series

| Part | Tag | Video | Focus |
|---|---|---|---|
| V1 | [`v1.0-eks-deployment`](https://github.com/ThinkWithOps/thinkwithops-online-boutique-production/releases/tag/v1.0-eks-deployment) | [Watch](https://youtu.be/qjnJab8mqcI) | VPC → EKS → ECR → Helm, GitHub Actions OIDC CI/CD, first live deploy |
| V2 | [`v2.0-load-testing-autoscaling`](https://github.com/ThinkWithOps/thinkwithops-online-boutique-production/releases/tag/v2.0-load-testing-autoscaling) | [Watch](https://youtu.be/mjGCdLFqZ7k) | HPA, Karpenter node autoscaling, k6 load testing, Prometheus/Grafana observability |
| V3 | [`v3.0-sre-observability`](https://github.com/ThinkWithOps/thinkwithops-online-boutique-production/releases/tag/v3.0-sre-observability) | Coming soon | Loki/Promtail logging, Tempo tracing, Prometheus alert rules, Alertmanager + Slack, runbooks, incident debug scripts — local minikube |

---

## Attribution

The application source (`src/*`) and the original GCP/GKE deployment assets are from Google's [**GoogleCloudPlatform/microservices-demo**](https://github.com/GoogleCloudPlatform/microservices-demo) ("Online Boutique"), licensed under [Apache License 2.0](LICENSE). No application code was modified to build this AWS layer.

Only the DevOps/infrastructure layer described in this README is original work added on top.

---

## V1 — EKS Deployment

VPC → EKS cluster → ECR → Helm release → GitHub Actions OIDC CI/CD. First live deploy, tagged [`v1.0-eks-deployment`](https://github.com/ThinkWithOps/thinkwithops-online-boutique-production/releases/tag/v1.0-eks-deployment) (see [Video Series](#video-series)).

## Architecture

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 40, "rankSpacing": 55}, "themeVariables": {"fontSize": "18px"}}}%%
flowchart TB
    Internet(("Internet")):::entry
    GHA["GitHub Actions\n(aws-eks-deploy.yaml)"]:::entry
    OIDC["OIDC token\n→ AWS STS AssumeRole"]:::entry
    DeployRole["IAM Role\ngithub-actions-deploy"]:::entry

    LB["LoadBalancer\n(frontend-external)"]:::entry
    ECR["Amazon ECR\n12 repos, 1 per service"]:::service
    EKS["EKS Control Plane\nonline-boutique-production"]:::service
    NG["EKS Node Group\n2× t3.small"]:::service

    FE["frontend"]:::service
    CART["cartservice"]:::service
    CHK["checkoutservice"]:::service
    PAY["paymentservice"]:::service
    SHIP["shippingservice"]:::service
    CUR["currencyservice"]:::service
    EMAIL["emailservice"]:::service
    PROD["productcatalogservice"]:::service
    REC["recommendationservice"]:::service
    AD["adservice"]:::service

    REDIS[("Redis cache\nredis-cart")]:::data
    STATE[("S3 + DynamoDB\nTerraform state + lock")]:::data

    GHA --> OIDC --> DeployRole
    DeployRole --> ECR
    DeployRole --> EKS
    ECR --> NG
    EKS --> NG

    Internet --> LB --> FE
    FE --> CART --> REDIS
    FE --> CHK --> PAY
    CHK --> SHIP
    CHK --> CUR
    CHK --> EMAIL
    FE --> PROD
    FE --> REC
    FE --> AD
    FE --> SHIP
    FE --> CUR

    NG -.-> STATE

    classDef entry fill:#a8c8f0,stroke:#4a76b8,stroke-width:1.5px,color:#1a2b3c,rx:10,ry:10
    classDef service fill:#a9d3a0,stroke:#5a9152,stroke-width:1.5px,color:#1a2b1c,rx:10,ry:10
    classDef data fill:#f3c98a,stroke:#c98a3a,stroke-width:1.5px,color:#3c2a10,rx:10,ry:10
```

### How this flows

**Deploy path (blue nodes):** a push to `main` triggers GitHub Actions (`aws-eks-deploy.yaml`), which requests a short-lived OIDC token and exchanges it with AWS STS for temporary credentials — no stored AWS keys anywhere in GitHub Secrets. Those credentials assume the `github-actions-deploy` IAM role, which is scoped to two things: pushing built images to ECR, and deploying to the EKS control plane.

**Traffic path (green nodes):** a request hits the `frontend-external` LoadBalancer — a plain Kubernetes `LoadBalancer` Service, not an ALB Ingress (the ALB controller add-on is provisioned but not installed this run) — and lands on the `frontend` pod. From there: `frontend` fans out to `cartservice` (which reads/writes the Redis cache), `checkoutservice` (which itself calls `paymentservice`, `shippingservice`, `currencyservice`, and `emailservice` to complete an order), plus direct calls to `productcatalogservice`, `recommendationservice`, and `adservice`.

**Compute + registry (green nodes, background):** the EKS node group (2× `t3.small`) is what actually runs all 11 pods — the control plane only makes scheduling decisions, it doesn't host workloads itself. Every image running on those nodes was pulled from one of the 12 ECR repositories, one per service.

**State (amber nodes):** Terraform's own state — the record of what it created — lives in S3 with a DynamoDB lock table, so two people can't `apply` at the same time and corrupt it. This is provisioned by a separate one-time `bootstrap/` step before the main infrastructure apply can even run.

---

## Tech Stack

| Technology | Role |
|---|---|
| Terraform (>= 1.6, `hashicorp/aws` ~> 5.0) | VPC, EKS, ECR, IAM/IRSA, S3+DynamoDB remote state |
| Amazon EKS (1.30) | Managed Kubernetes control plane, `online-boutique-production` |
| Amazon ECR | 12 private image repos, one per microservice, lifecycle policies |
| Amazon VPC | 3-AZ public/private subnets, NAT gateway, IGW |
| IAM Roles for Service Accounts (IRSA) | Scoped AWS access per Kubernetes ServiceAccount, no node-wide IAM |
| GitHub Actions + OIDC | Build/push/deploy pipeline, no long-lived AWS keys in CI |
| Helm 3 | Chart-based deploy, `values-aws-production.yaml` overlay on the existing chart |
| Docker (multi-stage) | Per-service builds, existing Dockerfiles reused as-is |
| aws-load-balancer-controller / ExternalDNS / Cluster Autoscaler | Optional add-ons for ALB ingress, Route53 automation, node autoscaling |
| HorizontalPodAutoscaler + metrics-server (V2) | Pod-level autoscaling on CPU/memory for 10 services |
| Karpenter (V2) | Node-level autoscaling — on-demand `t3.small` provisioning + consolidation |
| k6 (V2) | In-cluster load test, ramping virtual users |
| Prometheus + kube-state-metrics + node-exporter (V2) | Metrics scraping for pods, cluster state, and nodes |
| OpenTelemetry Collector (V2) | Telemetry pipeline feeding Prometheus |
| Grafana (V2) | `online-boutique-autoscaling` dashboard — live proof of scale-out/in |
| Loki + Promtail (V3) | Centralized logging for all 11 services, filesystem storage, no object-store dependency |
| Grafana Tempo (V3) | Distributed tracing, single-binary/local storage |
| OTel Collector `spanmetrics` connector (V3) | Derives real RED (rate/error/duration) metrics from trace spans — the app has no native ones |
| Prometheus Alertmanager + Slack (V3) | Alert routing — latency, error-rate, and pod-crash rules, Slack webhook receiver |
| Minikube (V3 target) | Local single-node cluster — no AWS/cloud dependency for this layer |

---

## Microservices

| Service | Language |
|---|---|
| frontend | Go |
| cartservice | C# |
| productcatalogservice | Go |
| currencyservice | Node.js |
| paymentservice | Node.js |
| shippingservice | Go |
| emailservice | Python |
| checkoutservice | Go |
| recommendationservice | Python |
| adservice | Java |
| loadgenerator | Python/Locust |
| shoppingassistantservice | Python (optional, Gemini-powered) |

All communicate over gRPC; contracts live in `protos/`.

---

## Prerequisites

- AWS account with permissions to create VPC/EKS/IAM/ECR/S3/DynamoDB resources
- [Terraform](https://developer.hashicorp.com/terraform) >= 1.6
- [AWS CLI](https://aws.amazon.com/cli/) v2, configured
- [kubectl](https://kubernetes.io/docs/tasks/tools/) >= 1.30
- [Helm](https://helm.sh/) >= 3.15
- [Docker](https://www.docker.com/) for building/pushing images
- A GitHub repo with OIDC federation (default on github.com) if using the CI workflow

---

## How to Deploy

**1. Bootstrap the Terraform state backend (one time)**
```bash
cd terraform-aws/bootstrap
terraform init
terraform apply
terraform output   # note state_bucket / lock_table, copy into ../backend.tf
```

**2. Provision VPC, EKS, ECR, IAM/IRSA**
```bash
cd terraform-aws
cp terraform.tfvars.example terraform.tfvars
# edit: aws_account_id, github_repository, node sizing
terraform init
terraform plan -out=tfplan
terraform apply "tfplan"
```

**3. Point kubectl at the cluster**
```bash
aws eks update-kubeconfig --region us-east-1 --name online-boutique-production
kubectl get nodes
```

**4. Build and push all 12 images to ECR**
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

for svc in adservice cartservice checkoutservice currencyservice emailservice \
           frontend loadgenerator paymentservice productcatalogservice \
           recommendationservice shippingservice shoppingassistantservice; do
  ctx="src/$svc"; [ "$svc" = "cartservice" ] && ctx="src/$svc/src"
  docker build -t <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/$svc:latest "$ctx"
  docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/$svc:latest
done
```
(`.github/workflows/aws-eks-deploy.yaml` does this automatically per push, via OIDC — no stored AWS keys.)

**5. Deploy with Helm**
```bash
helm upgrade --install online-boutique helm-chart/ \
  -f helm-chart/values.yaml \
  -f helm-chart/values-aws-production.yaml \
  --set images.tag=latest \
  --set frontend.externalService=true \
  --namespace online-boutique --create-namespace
```
`values-aws-production.yaml` defaults to ALB-mode (`externalService: false`), which requires the aws-load-balancer-controller add-on to be installed (see the "Optional — ALB Ingress" note below). The `--set frontend.externalService=true` override above gets you a plain `LoadBalancer` Service instead — no add-on install required, matches the actual verified deploy this README describes.

**6. Get the frontend URL**
```bash
kubectl get svc frontend-external -n online-boutique
# open http://<EXTERNAL-IP> in a browser
```

**Optional — ALB Ingress + ExternalDNS + Cluster Autoscaler add-ons** (needs a Route53 domain + ACM cert): see manifests/values under `addons/`.

---

## Project Structure (AWS layer)

```
terraform-aws/
├── bootstrap/                    # S3 + DynamoDB state backend (run once, first)
├── vpc.tf, eks.tf, ecr.tf, iam.tf, backend.tf, variables.tf, outputs.tf
└── terraform.tfvars.example      # copy to terraform.tfvars, fill in real values

helm-chart/
└── values-aws-production.yaml    # ECR image repo, IRSA annotations, resource limits — overlay only

kubernetes-manifests-aws/
├── namespace.yaml, configmap-aws-config.yaml, secret-example.yaml
├── hpa.yaml                      # HorizontalPodAutoscalers
└── node-affinity-patch.yaml

addons/
├── aws-load-balancer-controller/ # IRSA serviceaccount, values, frontend Ingress
├── external-dns/                 # IRSA serviceaccount, deployment
└── cluster-autoscaler/           # IRSA serviceaccount, deployment

.github/workflows/
└── aws-eks-deploy.yaml           # matrix build/push to ECR (OIDC) + helm upgrade --install

karpenter/                        # V2 — node-level autoscaler
├── nodepool.yaml                 # NodePool + EC2NodeClass, t3.small on-demand
└── README.md

k6/                                # V2 — in-cluster load test
├── 100k-users.js                 # ramp script, browse → cart → checkout
├── k6-pod.yaml
└── README.md

observability/
├── prometheus/                   # V2 base + V3 alert-rules.yaml (PrometheusRule)
├── grafana/                      # online-boutique-autoscaling dashboard
├── otel-collector/               # V2 base + V3 spanmetrics connector, Tempo exporter
├── loki/                         # V3 — Loki + Promtail (centralized logging)
├── tempo/                        # V3 — distributed tracing
├── alertmanager/                 # V3 — Slack alert routing (webhook via Secret, not committed)
└── README.md

docs/runbooks/                    # V3 — one runbook per alert
├── high-latency.md
├── high-error-rate.md
└── pod-crash-looping.md

scripts/debug/                    # V3 — kubectl helpers for common incidents
├── pod-crash.sh
├── high-memory.sh
├── slow-response.sh
└── service-unreachable.sh
```

---

## V2 — Load Testing + Autoscaling

Builds on the V1 deploy without touching it — same cluster, same Helm release, three new layers added on top:

- **`kubernetes-manifests-aws/hpa.yaml`** — HorizontalPodAutoscalers for all 10 long-lived Deployments (excludes `loadgenerator`, a batch-style generator, and `shoppingassistantservice`, disabled by default).
- **`karpenter/`** — node-level autoscaler (NodePool + EC2NodeClass), replacing/supplementing the Cluster Autoscaler add-on.
- **`k6/`** — load test script exercising the browse → add-to-cart → checkout path, ramping virtual users.
- **`observability/`** — Prometheus + kube-state-metrics + node-exporter, OpenTelemetry Collector config, and a Grafana dashboard for watching both scale out live.

### V2 Architecture

Same cluster as V1. Three new layers added on top:

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 30, "rankSpacing": 45}, "themeVariables": {"fontSize": "14px"}}}%%
flowchart TB
    Internet(("Internet")):::entry
    LB["LoadBalancer\n(frontend-external)"]:::entry
    FE["frontend\nHPA: 3→10"]:::service
    CART["cartservice\nHPA: 2→8"]:::service
    CHK["checkoutservice\nHPA: 2→6"]:::service
    REDIS[("Redis cache\nredis-cart")]:::data

    K6["k6 pod\n(in-cluster load test)"]:::load
    HPA["HorizontalPodAutoscaler\n10 services\nCPU 70% + Memory 80%"]:::autoscale
    KARPENTER["Karpenter\nNodePool: t3.small on-demand\nconsolidateAfter: 1m"]:::autoscale
    PROM["Prometheus\n+ kube-state-metrics\n+ node-exporter"]:::observe
    GRAFANA["Grafana\nonline-boutique-autoscaling\ndashboard"]:::observe
    NODES["EKS Nodes\n2 → 8 (under load)"]:::service

    K6 -->|"ramps 0→3000 VUs"| LB
    Internet --> LB --> FE
    FE --> CART --> REDIS
    FE --> CHK

    HPA -->|"scales pods"| FE
    HPA -->|"scales pods"| CART
    HPA -->|"scales pods"| CHK
    KARPENTER -->|"launches nodes"| NODES
    PROM -->|"metrics"| HPA
    PROM --> GRAFANA

    classDef entry fill:#a8c8f0,stroke:#4a76b8,stroke-width:1.5px,color:#1a2b3c
    classDef service fill:#a9d3a0,stroke:#5a9152,stroke-width:1.5px,color:#1a2b1c
    classDef data fill:#f3c98a,stroke:#c98a3a,stroke-width:1.5px,color:#3c2a10
    classDef autoscale fill:#d4b8f0,stroke:#7c4dba,stroke-width:1.5px,color:#1a0a3c
    classDef observe fill:#f0d4a8,stroke:#ba7c4d,stroke-width:1.5px,color:#3c1a0a
    classDef load fill:#b8f0d4,stroke:#4dba7c,stroke-width:1.5px,color:#0a3c1a
```

### How V2 adds to V1

**Pod autoscaling (purple nodes):** HorizontalPodAutoscaler watches CPU and memory per service. When average CPU crosses 70%, the HPA controller requests more replicas. Requires metrics-server to be installed — without it HPA shows unknown targets and never scales.

**Node autoscaling (purple nodes):** Karpenter watches for pods stuck in Pending because no existing node has room. It launches a new t3.small on-demand instance in under 60 seconds. When load drops and a node sits underused for 1 minute (`consolidateAfter: 1m`), Karpenter terminates it. Nodes exist exactly as long as they are needed.

**Load test (green node):** k6 runs inside the cluster as a Kubernetes pod, not from a laptop. Traffic originates from inside the same VPC, same network path as real user traffic. Script ramps 0 → 3,000 VUs (written for 100,000 VUs — scaled down to what t3.small nodes can actually sustain).

**Observability (orange nodes):** Prometheus scrapes metrics from every pod, kube-state-metrics for cluster state, node-exporter for node-level metrics. Grafana dashboard shows pod count, node count, and HPA CPU utilization in real time.

### HPA configuration summary

CPU (70% avg utilization) + memory (80% avg utilization) targets on every service, `kubectl apply -f kubernetes-manifests-aws/hpa.yaml`:

| Service | Min | Max |
|---|---|---|
| frontend | 3 | 10 |
| cartservice | 2 | 8 |
| checkoutservice, productcatalogservice, currencyservice, recommendationservice, adservice, emailservice, paymentservice, shippingservice | 2 | 6 |

Requires the `metrics-server` EKS add-on — install with `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` if HPA shows `<unknown>` targets.

### Karpenter node scaling summary

IAM (controller pod-identity role + node role/instance profile) is provisioned in `terraform-aws/iam.tf` (`module.karpenter`), alongside an `eks-pod-identity-agent` EKS add-on (`terraform-aws/eks.tf`) the controller needs to fetch its own AWS credentials in-cluster.

`karpenter/nodepool.yaml` defines a `NodePool` + `EC2NodeClass` restricted to `t3.small` on-demand instances (this account is free-tier-restricted — `t3.medium` gets rejected at launch, same constraint as the V1 managed node group). Consolidation is aggressive (`consolidateAfter: 1m`) so idle nodes get reclaimed quickly once load drops. Install steps: see `karpenter/README.md`.

Verified live: under load, Karpenter scaled the cluster from 2 nodes up to 8 as HPA drove pod counts up (frontend 3→10 replicas, currencyservice/recommendationservice 2→6), then consolidated back down once load receded.

### k6 load test instructions

`k6/100k-users.js` ramps 0 → 100,000 virtual users over ~28 minutes against the frontend Service — written at production scale for the portfolio/demo narrative. Actual VU count you can run in a given moment is bound by real node capacity (a `t3.small`-only NodePool won't sustain literal 100k VUs on a couple of nodes) — scale the `stages` targets down for a live run on a small cluster, keeping the same ramp shape.

### Commands to run the load test

```bash
# In-cluster (recommended — avoids local network/machine being the bottleneck)
kubectl create namespace k6 --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap k6-script -n k6 --from-file=k6/100k-users.js
kubectl run k6 -n k6 --image=grafana/k6:latest --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"k6","image":"grafana/k6:latest","command":["k6","run","/scripts/100k-users.js"],"env":[{"name":"FRONTEND_URL","value":"http://frontend.online-boutique.svc.cluster.local"}],"volumeMounts":[{"name":"script","mountPath":"/scripts"}]}],"volumes":[{"name":"script","configMap":{"name":"k6-script"}}]}}'
kubectl -n k6 logs -f k6

# Watch the reaction live
kubectl get hpa -n online-boutique -w
kubectl get nodes -w
kubectl get nodeclaims

# Grafana dashboard
kubectl -n monitoring port-forward svc/grafana 3000:80
# open http://localhost:3000/d/online-boutique-autoscaling
```

See `observability/README.md` for the full Prometheus/Grafana/OTel install order, and `k6/README.md` / `karpenter/README.md` for more detail on each piece.

---

## V3 — SRE / Observability + Incident Response

Builds on V2 without touching V1/V2 or any application code — target shifts to **local minikube**, no cloud dependencies. Tag: `v3.0-sre-observability`.

- **Loki + Promtail** (`observability/loki/`) — centralized logs for all 11 services, queryable in Grafana by namespace/app/pod, filesystem storage (no object store needed).
- **Grafana Tempo** (`observability/tempo/`) — distributed tracing, single-binary mode, local storage.
- **OTel Collector `spanmetrics` connector** (`observability/otel-collector/config.yaml`) — the app never exposed a native `http_requests_total`/duration metric, so this derives real RED (rate/error/duration) metrics directly from trace spans instead of relying on a proxy metric.
- **Prometheus alert rules** (`observability/prometheus/alert-rules.yaml`) — `HighRequestLatency` (p95 > 500ms), `HighErrorRate` (> 5%), `PodCrashLooping`, `PodNotReady`.
- **Alertmanager + Slack** (`observability/alertmanager/`) — routes alerts to Slack via a webhook Secret (never committed — see `slack-webhook-secret.example.yaml`), critical alerts get their own channel + faster repeat interval.
- **Runbooks** (`docs/runbooks/`) — one per alert, each linked from the alert's `runbook_url` annotation.
- **Incident debug scripts** (`scripts/debug/`) — `pod-crash.sh`, `high-memory.sh`, `slow-response.sh`, `service-unreachable.sh`, each referenced from its matching runbook.

### Why minikube for this layer

V1/V2 are AWS-specific by design (Terraform/EKS/Karpenter only make sense against real cloud infra). The observability/incident-response layer is exactly the part that doesn't need to be — running it on minikube keeps the demo free of AWS cost and lets anyone reproduce it without an AWS account at all.

```sh
minikube start --cpus=4 --memory=8192
```

Full install order, verification steps, and what each piece is for: **see `observability/README.md`**.

### The gap this closes

V2 proved autoscaling works under load, live in a terminal. It didn't answer: what happens when something breaks at 3am? V3 adds the other half — logs to search, traces to follow a slow request across services, metrics-driven alerts that page before a user complains, and a runbook + debug script so the response isn't "start from zero."

---

## Cost Notes

- **EKS control plane**: flat $0.10/hr, no free tier
- **Node group**: sized to `t3.small` (free-tier-eligible instance class) — accounts restricted to free-tier instance types will reject larger types like `t3.medium`/`m6i.large` at launch
- **NAT gateway**: single NAT (not 3) to cut cost for demo/non-HA use
- Rough total: **~$0.20–0.25/hr** running, effectively **$0** once `terraform destroy` is run
- Recommended workflow: `apply` → verify/demo → `destroy`, rather than leaving the cluster up
- **V2 load test cost spike**: Karpenter scaling 2 → 8 nodes during a k6 run roughly 4x's the node-hour cost for the duration of the test (~8× `t3.small` instead of 2×); consolidation (`consolidateAfter: 1m`) reclaims nodes within minutes of load dropping, so the spike is short-lived, not sustained

---

## What This Teaches

| What Was Built | Skill Demonstrated |
|---|---|
| VPC + EKS + ECR + IAM/IRSA in Terraform | AWS infrastructure-as-code from scratch |
| IRSA roles per add-on (ALB controller, ExternalDNS, Cluster Autoscaler) | Least-privilege AWS access from Kubernetes, no node-wide IAM |
| GitHub Actions OIDC → AWS role assumption | Keyless CI/CD, no long-lived cloud credentials |
| Helm overlay pattern (`-f base -f production`) | Layering environment-specific config without forking a chart |
| Remote state bootstrap (S3 + DynamoDB, chicken-and-egg problem) | Terraform backend design constraints |
| Free-tier / account-restriction debugging | Reading AWS API errors (`AsgInstanceLaunchFailures`) and adjusting instance types live |
| TLS interception debugging (AV Web Shield breaking loopback gRPC) | Diagnosing local dev-environment network issues, not just cloud issues |
| HPA on 10 services | Pod autoscaling on real CPU + memory metrics |
| Karpenter NodePool | On-demand node provisioning + consolidation |
| k6 in-cluster load test | Load testing without local network bottleneck |
| Prometheus + Grafana | Live proof of autoscaling — not just YAML |
| metrics-server dependency | Understanding hidden add-on requirements |
| OTel spanmetrics connector | Deriving real RED metrics from traces when the app exposes none natively |
| Loki + Promtail | Centralized logging without a per-service logging agent |
| Grafana Tempo | Distributed tracing, correlating a slow request across services |
| PrometheusRule + Alertmanager routing | Alert-on-symptom design (latency/errors/crashes), severity-based routing |
| Runbooks + debug scripts | Incident response that doesn't start from zero — docs and tooling as a deliverable, not an afterthought |

---

## Challenges

- **Corporate/local AV HTTPS scanning broke Terraform.** AVG's Web Shield intercepted loopback TLS between Terraform core and its provider plugin (`x509: certificate signed by unknown authority` on a *local* gRPC handshake). Fixed by temporarily disabling HTTPS scanning during `plan`/`apply`.
- **AWS CLI/Terraform SSL errors from corp network TLS interception.** `SSL_CERT_FILE`/`AWS_CA_BUNDLE` pointed at a PEM built from the Windows trusted-root cert store resolved it.
- **Node group `CREATE_FAILED`: `t3.medium` rejected.** `AsgInstanceLaunchFailures: ... not eligible for Free Tier`. The AWS account was restricted to free-tier instance types only. Switched to `t3.small` (free-tier eligible, 2 vCPU/2GB — still enough for all 11 lightweight services) and re-applied only the node group.
- **HPA showed `<unknown>` targets, never scaled (V2).** No error, no event — just silently stuck at 0% CPU/memory forever. Root cause: `metrics-server` wasn't installed. HPA depends on it entirely and fails quiet, not loud, when it's missing.
- **Karpenter controller pod couldn't get AWS credentials (V2).** Needed the `eks-pod-identity-agent` EKS add-on installed and a pod-identity association wired to the controller's IAM role (`terraform-aws/eks.tf` / `terraform-aws/iam.tf`, `module.karpenter`) before the controller could launch nodes at all — IRSA alone wasn't enough for this path.
- **k6 from a laptop skewed results (V2).** Running the load test from a local machine made the local network/machine the bottleneck, not the cluster. Moved k6 in-cluster (`k6/k6-pod.yaml`) so traffic originates from the same VPC as real user traffic.
- **`minikube start --memory=8192` rejected (V3).** `MK_USAGE: Docker Desktop has only 7844MB memory but you specified 8192MB`. Docker Desktop's own memory allocation (Settings → Resources → Memory) was below what minikube was asked for. Fixed by either lowering the `--memory` flag to fit (e.g. `--memory=7500`) or raising Docker Desktop's limit first.
- **`recommendationservice` / `emailservice` crash-looping on minikube, not on EKS (V3).** `Readiness probe failed: timeout ... context deadline exceeded` — the app itself was fine, but a 1-second probe `timeoutSeconds` (tuned for real cloud nodes) was too tight once 11 services + the full observability stack were sharing a 4-vCPU minikube node. Fixed by patching `livenessProbe`/`readinessProbe` `timeoutSeconds` up to 5s on the affected deployments — see `docs/runbooks/pod-crash-looping.md`.

---

## Cleanup

**Delete the Helm release before running `terraform destroy`.** The frontend's LoadBalancer (and its security group) is created by Kubernetes' own AWS cloud-controller when the Service is applied — not by Terraform — so Terraform has no record of it. If you destroy the EKS cluster first, that LoadBalancer never gets its normal deletion trigger and is orphaned, silently blocking your VPC's subnets and security groups from being deleted. Cleaning that up after the fact means manually finding and deleting the leftover ELB and SG via the AWS CLI/Console before `terraform destroy` can finish.

```bash
# 1. Delete the Helm release FIRST — this triggers AWS to clean up its own LoadBalancer/SG
helm uninstall online-boutique -n online-boutique
# wait ~30s for the LB to actually disappear, then confirm:
aws elb describe-load-balancers --region us-east-1   # should be empty (or unrelated to this cluster)

# 2. Then destroy the infrastructure
cd terraform-aws && terraform destroy
cd bootstrap && terraform destroy   # only if you're fully done — this deletes remote state
```

**If you already destroyed the cluster first and `terraform destroy` is stuck** on a subnet/VPC `DependencyViolation` error: find and delete the orphaned ELB and its security group manually, then re-run `terraform destroy`.

```bash
# Find the leftover ELB (name matches your frontend's external hostname prefix)
aws elb describe-load-balancers --region us-east-1 --query "LoadBalancerDescriptions[].LoadBalancerName"
aws elb delete-load-balancer --load-balancer-name <name> --region us-east-1

# Find its security group (named like "k8s-elb-<name>")
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=<your-vpc-id>" --query "SecurityGroups[].{id:GroupId,name:GroupName}"
aws ec2 delete-security-group --group-id <sg-id>

# Now re-run
cd terraform-aws && terraform destroy
```

---

## Command Reference

Every command used across this project's setup, deploy, verification, and teardown, in one place.

**Terraform**
| Command | Purpose |
|---|---|
| `cd terraform-aws/bootstrap && terraform init && terraform apply` | One-time: create the S3 state bucket + DynamoDB lock table |
| `terraform init` | Initialize the main config against the S3 backend |
| `terraform plan -out=tfplan` | Preview changes, save the plan |
| `terraform apply "tfplan"` | Apply the saved plan |
| `terraform destroy` | Tear down everything this config created |
| `terraform force-unlock <lock-id>` | Clear a stuck state lock (e.g. after a killed/interrupted apply) |
| `terraform output` | Show output values (cluster endpoint, ECR URLs, IRSA role ARNs, etc.) |

**AWS CLI — cluster & auth**
| Command | Purpose |
|---|---|
| `aws sts get-caller-identity` | Confirm which AWS account/identity you're authenticated as |
| `aws eks update-kubeconfig --region us-east-1 --name online-boutique-production` | Point `kubectl` at the cluster |
| `aws eks describe-nodegroup --cluster-name online-boutique-production --nodegroup-name <name> --query "nodegroup.{status:status,health:health}"` | Check node group status/health |
| `aws ec2 describe-instance-types --filters "Name=free-tier-eligible,Values=true" --query "InstanceTypes[].InstanceType"` | List instance types your account can actually launch |
| `aws ec2 describe-instances --filters "Name=tag:eks:cluster-name,Values=online-boutique-production"` | Check whether node EC2 instances actually launched |
| `aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[].{name:AutoScalingGroupName,desired:DesiredCapacity}"` | Check the node group's underlying ASG desired/running counts |

**AWS CLI — images**
| Command | Purpose |
|---|---|
| `aws ecr get-login-password --region us-east-1 \| docker login --username AWS --password-stdin <account>.dkr.ecr.us-east-1.amazonaws.com` | Authenticate Docker to ECR |
| `docker build -t <account>.dkr.ecr.us-east-1.amazonaws.com/<service>:latest src/<service>` | Build one service's image |
| `docker push <account>.dkr.ecr.us-east-1.amazonaws.com/<service>:latest` | Push it to ECR |

**kubectl**
| Command | Purpose |
|---|---|
| `kubectl get nodes` | Confirm nodes are `Ready` |
| `kubectl get pods -n online-boutique` | Confirm all 11 pods are `Running` |
| `kubectl get svc frontend-external -n online-boutique` | Get the live frontend URL |
| `kubectl -n online-boutique rollout status deployment/frontend --timeout=5m` | Wait for a deployment rollout to finish |

**Helm**
| Command | Purpose |
|---|---|
| `helm upgrade --install online-boutique helm-chart/ -f helm-chart/values.yaml -f helm-chart/values-aws-production.yaml --set frontend.externalService=true --namespace online-boutique --create-namespace` | Deploy/update the full release |
| `helm list -n online-boutique` | Confirm the release is deployed |
| `helm status online-boutique -n online-boutique` | Full release status |
| `helm uninstall online-boutique -n online-boutique` | Remove the release (do this **before** `terraform destroy`, see Cleanup above) |

**Minikube (V3 local target)**
| Command | Purpose |
|---|---|
| `minikube start --cpus=4 --memory=7500` | Start the local cluster (lower `--memory` if Docker Desktop rejects 8192 — see Challenges) |
| `kubectl create namespace online-boutique --dry-run=client -o yaml \| kubectl apply -f -` | Create the app namespace |
| `helm install online-boutique helm-chart/ --namespace online-boutique` | Deploy the app using its default public-image values — no AWS overlay needed |
| `minikube service frontend-external -n online-boutique` | Open the storefront in a browser (minikube has no cloud LoadBalancer) |
| `kubectl -n online-boutique port-forward svc/frontend-external 8080:80` | Alternative to `minikube service` — access at `localhost:8080` |
| `kubectl -n online-boutique patch deployment <name> --type=json -p='[{"op":"replace","path":"/spec/template/spec/containers/0/livenessProbe/timeoutSeconds","value":5},{"op":"replace","path":"/spec/template/spec/containers/0/readinessProbe/timeoutSeconds","value":5}]'` | Fix probe-timeout crash-looping under CPU contention (see Challenges) |
| `minikube delete` | Tear down the local cluster entirely |

**GitHub Actions / OIDC diagnostics**
| Command | Purpose |
|---|---|
| `gh workflow list -R <owner>/<repo>` | List workflows and their enabled/disabled state |
| `gh workflow run "<workflow name>" -R <owner>/<repo> --ref main` | Manually trigger a workflow run |
| `gh run list -R <owner>/<repo> --workflow="<workflow name>" --limit 5` | Recent runs and their status |
| `gh run view <run-id> -R <owner>/<repo> --log-failed` | Logs for only the failed steps of a run |
| `gh api repos/<owner>/<repo>/actions/oidc/customization/sub` | Check the actual OIDC subject-claim prefix GitHub sends for this repo (differs for forks — see `terraform-aws/iam.tf`) |

**HPA / metrics-server (V2)**
| Command | Purpose |
|---|---|
| `kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml` | Install metrics-server (required — HPA shows `<unknown>` targets without it) |
| `kubectl apply -f kubernetes-manifests-aws/hpa.yaml` | Apply HorizontalPodAutoscalers for all 10 services |
| `kubectl get hpa -n online-boutique` | Check current CPU/memory utilization vs. targets, and replica counts |
| `kubectl get hpa -n online-boutique -w` | Watch replica counts change live during load |

**Karpenter (V2)**
| Command | Purpose |
|---|---|
| `helm install karpenter oci://public.ecr.aws/karpenter/karpenter --version "1.1.0" --namespace kube-system --set settings.clusterName=online-boutique-production --set settings.interruptionQueue=Karpenter-online-boutique-production --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<karpenter_iam_role_arn>` | Install the Karpenter controller |
| `kubectl apply -f karpenter/nodepool.yaml` | Apply the NodePool + EC2NodeClass |
| `kubectl get nodeclaims` | Karpenter's own record of nodes it has launched, and their status |
| `kubectl get nodes -w` | Watch node count change live as Karpenter scales |
| `kubectl -n kube-system logs -l app.kubernetes.io/name=karpenter --tail=50` | Karpenter controller logs (launch failures, consolidation decisions) |

**k6 load test (V2)**
| Command | Purpose |
|---|---|
| `kubectl create namespace k6 --dry-run=client -o yaml \| kubectl apply -f -` | Create the k6 namespace |
| `kubectl create configmap k6-script -n k6 --from-file=k6/100k-users.js` | Load the test script into the cluster |
| `kubectl apply -f k6/k6-pod.yaml` | Launch the k6 pod in-cluster |
| `kubectl -n k6 logs -f k6` | Stream VU ramp and iteration output live |

**Prometheus / Grafana (V2)**
| Command | Purpose |
|---|---|
| `helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace -f observability/prometheus/values.yaml` | Install Prometheus + kube-state-metrics + node-exporter + Alertmanager |
| `helm install grafana grafana/grafana --namespace monitoring` | Install standalone Grafana |
| `kubectl -n monitoring port-forward svc/grafana 3000:80` | Access Grafana locally at `http://localhost:3000` |
| `kubectl -n monitoring get pods` | Confirm the full observability stack is `Running` |

**Loki / Tempo / Alertmanager (V3)**
| Command | Purpose |
|---|---|
| `helm install loki grafana/loki-stack --namespace monitoring -f observability/loki/values.yaml` | Install Loki + Promtail (centralized logging) |
| `helm install tempo grafana/tempo --namespace monitoring -f observability/tempo/values.yaml` | Install Tempo (distributed tracing) |
| `kubectl apply -f observability/prometheus/alert-rules.yaml` | Apply the latency/error-rate/pod-crash `PrometheusRule` |
| `kubectl apply -f observability/alertmanager/slack-webhook-secret.example.yaml` | Create the Slack webhook Secret (edit the URL first) |
| `helm upgrade kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring -f observability/prometheus/values.yaml -f observability/alertmanager/values.yaml` | Apply the Slack-wired Alertmanager overlay |
| `kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093` | Access the Alertmanager UI locally |
| `./scripts/debug/pod-crash.sh <app-label>` | Diagnose a crash-looping/OOMKilled pod |
| `./scripts/debug/high-memory.sh <app-label>` | Check memory usage vs. limits for a service |
| `./scripts/debug/slow-response.sh <app-label>` | Investigate a service tripping the latency alert |
| `./scripts/debug/service-unreachable.sh <service-name>` | Diagnose a Service with no reachable endpoints |

---

## GCP Path (original, untouched)

Google's original GKE/GCP deployment path — `kubernetes-manifests/`, `helm-chart/templates/` (base), `terraform/` (GKE + Memorystore), `kustomize/`, `skaffold.yaml` — ships unmodified in this repo. See [`docs/development-guide.md`](docs/development-guide.md) for that quickstart.

---

**License:** Application code is Apache 2.0, © Google LLC — see [LICENSE](LICENSE). AWS infrastructure code added in this repo follows the same license unless noted otherwise.
