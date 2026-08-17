# Copyright 2026
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# IRSA roles for cluster add-ons (ALB controller, ExternalDNS, Cluster
# Autoscaler) plus the GitHub Actions OIDC deploy role used by
# .github/workflows/aws-eks-deploy.yaml (no long-lived AWS secrets).
#
# The EKS cluster role and node role are created inside the `eks` module
# (terraform-aws-modules/eks/aws) in eks.tf; they are not duplicated here.

# ---------------------------------------------------------------------------
# AWS Load Balancer Controller (drives the frontend Ingress -> ALB)
# ---------------------------------------------------------------------------
data "http" "alb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${var.cluster_name}-alb-controller"
  description = "IAM policy for aws-load-balancer-controller (managed by terraform-aws)"
  policy      = data.http.alb_controller_iam_policy.response_body
}

module "alb_controller_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${var.cluster_name}-alb-controller-irsa"

  role_policy_arns = {
    policy = aws_iam_policy.alb_controller.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# ExternalDNS (Route53 record management)
# ---------------------------------------------------------------------------
data "aws_route53_zone" "external_dns" {
  count        = var.external_dns_domain_filter != "" ? 1 : 0
  name         = var.external_dns_domain_filter
  private_zone = false
}

data "aws_iam_policy_document" "external_dns" {
  statement {
    effect    = "Allow"
    actions   = ["route53:ChangeResourceRecordSets"]
    resources = var.external_dns_domain_filter != "" ? ["arn:aws:route53:::hostedzone/${data.aws_route53_zone.external_dns[0].zone_id}"] : ["arn:aws:route53:::hostedzone/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["route53:ListHostedZones", "route53:ListResourceRecordSets", "route53:ListTagsForResource"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name   = "${var.cluster_name}-external-dns"
  policy = data.aws_iam_policy_document.external_dns.json
}

module "external_dns_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name = "${var.cluster_name}-external-dns-irsa"

  role_policy_arns = {
    policy = aws_iam_policy.external_dns.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:external-dns"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Cluster Autoscaler
# ---------------------------------------------------------------------------
module "cluster_autoscaler_irsa_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.48"

  role_name                        = "${var.cluster_name}-cluster-autoscaler-irsa"
  attach_cluster_autoscaler_policy = true
  cluster_autoscaler_cluster_ids   = [module.eks.cluster_name]

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:cluster-autoscaler"]
    }
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Pod-level ECR pull role (IRSA), for workloads that want to pull images
# without relying solely on the node role's AmazonEC2ContainerRegistryReadOnly
# policy (e.g. cross-account pulls in the future).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ecr_pull_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:${var.eks_namespace}:default"]
    }
  }
}

resource "aws_iam_role" "ecr_pull" {
  name               = "${var.cluster_name}-ecr-pull-irsa"
  assume_role_policy = data.aws_iam_policy_document.ecr_pull_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_pull" {
  role       = aws_iam_role.ecr_pull.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ---------------------------------------------------------------------------
# GitHub Actions OIDC deploy role (used by .github/workflows/aws-eks-deploy.yaml
# via aws-actions/configure-aws-credentials -- no long-lived AWS access keys)
# ---------------------------------------------------------------------------
data "tls_certificate" "github_oidc" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github_oidc.certificates[0].sha1_fingerprint]
}

variable "github_repository" {
  type        = string
  description = "GitHub repo allowed to assume the deploy role, as 'org/repo'. TODO: fill in."
  default     = "GoogleCloudPlatform/microservices-demo" # TODO: replace with this fork's actual org/repo
}

variable "github_repository_oidc_sub_prefix" {
  type        = string
  description = <<-EOT
    The repo segment GitHub actually puts in the OIDC "sub" claim. For most
    repos this is identical to var.github_repository, but GitHub appends
    owner/repo numeric IDs for forked repos (fork-safety measure) --
    check with: gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  default     = "ThinkWithOps@254184712/thinkwithops-online-boutique-production@1332138512"
}

data "aws_iam_policy_document" "github_actions_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    # GitHub customizes the OIDC "sub" claim's repo segment for forked repos
    # (appends owner/repo numeric IDs, e.g. "ThinkWithOps@254184712/repo@1332138512")
    # to prevent a fork's workflows from spoofing the upstream repo's identity.
    # Check the actual value for a given repo with:
    #   gh api repos/<owner>/<repo>/actions/oidc/customization/sub
    # Both the fork-prefixed and plain forms are included below so this works
    # whether or not the repo is (or later becomes) a fork.
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values = [
        "repo:${var.github_repository_oidc_sub_prefix}:ref:refs/heads/main",
        "repo:${var.github_repository_oidc_sub_prefix}:ref:refs/tags/v*",
        "repo:${var.github_repository}:ref:refs/heads/main",
        "repo:${var.github_repository}:ref:refs/tags/v*",
      ]
    }
  }
}

resource "aws_iam_role" "github_actions_deploy" {
  name               = "${var.cluster_name}-github-actions-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume.json
  tags               = var.tags
}

# ECR push/pull for the CI build-and-push step.
resource "aws_iam_role_policy_attachment" "github_actions_ecr" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# EKS describe access so `aws eks update-kubeconfig` works; actual in-cluster
# permissions come from an EKS access entry / aws-auth mapping to this role.
data "aws_iam_policy_document" "github_actions_eks_describe" {
  statement {
    effect    = "Allow"
    actions   = ["eks:DescribeCluster", "eks:ListClusters"]
    resources = [module.eks.cluster_arn]
  }
}

resource "aws_iam_policy" "github_actions_eks_describe" {
  name   = "${var.cluster_name}-github-actions-eks-describe"
  policy = data.aws_iam_policy_document.github_actions_eks_describe.json
}

resource "aws_iam_role_policy_attachment" "github_actions_eks_describe" {
  role       = aws_iam_role.github_actions_deploy.name
  policy_arn = aws_iam_policy.github_actions_eks_describe.arn
}

# Grants the CI deploy role cluster-admin via an EKS access entry so
# `helm upgrade --install` in the workflow can actually apply manifests.
resource "aws_eks_access_entry" "github_actions_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions_deploy.arn
}

resource "aws_eks_access_policy_association" "github_actions_deploy" {
  cluster_name  = module.eks.cluster_name
  principal_arn = aws_iam_role.github_actions_deploy.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}
