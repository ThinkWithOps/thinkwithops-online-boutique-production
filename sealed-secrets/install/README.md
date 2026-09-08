# Sealed Secrets install (V4, minikube)

Bitnami Sealed Secrets controller. Cluster-scoped infra, installed once,
outside any GitOps Application (same bootstrapping reasoning as ArgoCD).

```bash
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

## Sealing a future application secret

V4 does not currently use Slack or contain another real application secret,
so no generated SealedSecret is committed. When a real secret is introduced,
use this generic workflow:

```bash
# 1. Create the real Secret locally. Never commit this file.
kubectl create secret generic example-secret \
  --namespace online-boutique-dev \
  --from-literal=example-key='REAL_VALUE' \
  --dry-run=client -o yaml > /tmp/example-secret.plain.yaml

# 2. Seal it against the cluster's current public cert.
kubeseal --format=yaml \
  --cert sealed-secrets/pub-cert.pem \
  < /tmp/example-secret.plain.yaml \
  > sealed-secrets/example-secret.sealed.yaml

# 3. Delete the plaintext copy immediately.
rm /tmp/example-secret.plain.yaml

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
