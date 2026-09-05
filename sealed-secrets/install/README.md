# Sealed Secrets install (V4, minikube)

Bitnami Sealed Secrets controller. Cluster-scoped infra, installed once,
outside any GitOps Application (same bootstrapping reasoning as ArgoCD).

```bash
kubectl create namespace sealed-secrets

kubectl apply -f https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.27.1/controller.yaml

kubectl -n kube-system rollout status deploy/sealed-secrets-controller --timeout=120s
```

(The upstream manifest installs into `kube-system` by default; that's fine
here since this repo has no other secret-manager workload in that namespace.)

Install the `kubeseal` CLI (matches the controller version above):

```bash
# Windows (this repo's dev environment): download from
# https://github.com/bitnami-labs/sealed-secrets/releases/tag/v0.27.1
# kubeseal-0.27.1-windows-amd64.tar.gz -> extract kubeseal.exe onto PATH
kubeseal --version
```

## Sealing the alertmanager Slack webhook (the one real secret in this repo)

This repo's only plaintext secret example is
`observability/alertmanager/slack-webhook-secret.example.yaml` (V3). For V4 the
GitOps-committed path replaces "apply this file with real values by hand" with
"commit a SealedSecret that only this cluster's controller can decrypt":

```bash
# 1. Create the REAL secret locally -- never commit this file. Key name
#    (webhook-url) must match what observability/alertmanager/values.yaml
#    expects the mounted secret to contain.
kubectl create secret generic alertmanager-slack-webhook \
  --namespace monitoring \
  --from-literal=webhook-url='https://hooks.slack.com/services/REAL/WEBHOOK/URL' \
  --dry-run=client -o yaml > /tmp/alertmanager-slack-webhook.plain.yaml

# 2. Seal it against the cluster's current public cert.
kubeseal --format=yaml \
  --cert sealed-secrets/pub-cert.pem \
  < /tmp/alertmanager-slack-webhook.plain.yaml \
  > sealed-secrets/alertmanager-slack-webhook.sealed.yaml

# 3. Delete the plaintext copy immediately.
rm /tmp/alertmanager-slack-webhook.plain.yaml

# 4. Commit only the .sealed.yaml file.
```

Fetch the controller's current public cert (needed for step 2, safe to keep
committed -- it's public by design, sealing-only, cannot decrypt anything):

```bash
kubeseal --fetch-cert \
  --controller-namespace kube-system \
  --controller-name sealed-secrets-controller \
  > sealed-secrets/pub-cert.pem
```

## Backing up the controller's private key

The private key is what actually decrypts SealedSecrets -- losing it means
every committed `.sealed.yaml` becomes permanently unrecoverable. Back it up
to a secure, offline location immediately after install and after every
rotation:

```bash
kubectl get secret -n kube-system \
  -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o yaml > sealed-secrets-key-backup.yaml
```

**Never commit `sealed-secrets-key-backup.yaml` to git.** Store it in a
password manager or offline vault. It's a plain Kubernetes Secret containing
the RSA private key -- treat it with the same care as root cluster credentials.

To restore onto a fresh cluster (disaster recovery):

```bash
kubectl apply -f sealed-secrets-key-backup.yaml
kubectl -n kube-system delete pod -l name=sealed-secrets-controller  # force reload
```

## Key rotation

The controller auto-generates a new active key on a schedule (default: every
30 days) but keeps old keys around to decrypt secrets sealed under them. To
force an immediate rotation and re-seal existing secrets under the new key:

```bash
kubectl -n kube-system delete pod -l name=sealed-secrets-controller
# wait for the new pod, then re-fetch the cert and re-seal:
kubeseal --fetch-cert --controller-namespace kube-system --controller-name sealed-secrets-controller > sealed-secrets/pub-cert.pem
# re-run the "sealing" steps above against the new cert for each committed SealedSecret
```

Old SealedSecrets keep working (old private key retained) until you
deliberately re-seal and remove the old key secret.
