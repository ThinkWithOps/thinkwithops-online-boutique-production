# Karpenter (node autoscaler, v2)

Terraform (`terraform-aws/iam.tf` module `karpenter`, `terraform-aws/eks.tf`
node security group tag) provisions the IAM side: controller pod-identity
role + `online-boutique-production-karpenter-node` node role/instance
profile, and tags subnets/security groups for discovery. This directory
holds the Kubernetes-side install.

Run instead of, not alongside, `addons/cluster-autoscaler` -- both compete
over scale-down decisions if run together.

## Install

```sh
# From terraform-aws output:
#   terraform output karpenter_iam_role_arn (controller) 
#   terraform output karpenter_node_iam_role_name

helm registry logout public.ecr.aws || true
helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "1.1.0" \
  --namespace kube-system \
  --set settings.clusterName=online-boutique-production \
  --set settings.interruptionQueue=online-boutique-production-karpenter \
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=<karpenter_iam_role_arn> \
  --wait

kubectl apply -f karpenter/nodepool.yaml
```

Verify: scale a deployment up (e.g. `kubectl -n online-boutique scale deploy/frontend --replicas=10`)
and watch `kubectl get nodeclaims` -- Karpenter should launch a new node
within ~30-60s if the existing managed node group can't fit the pods.
