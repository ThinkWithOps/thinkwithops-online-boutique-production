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

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}

output "cluster_arn" {
  value = module.eks.cluster_arn
}

output "region" {
  value = var.region
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "ecr_repository_urls" {
  description = "Map of service name -> ECR repository URL, one per var.ecr_repositories entry"
  value       = { for k, v in aws_ecr_repository.service : k => v.repository_url }
}

output "alb_controller_irsa_role_arn" {
  value = module.alb_controller_irsa_role.iam_role_arn
}

output "external_dns_irsa_role_arn" {
  value = module.external_dns_irsa_role.iam_role_arn
}

output "cluster_autoscaler_irsa_role_arn" {
  value = module.cluster_autoscaler_irsa_role.iam_role_arn
}

output "ecr_pull_irsa_role_arn" {
  value = aws_iam_role.ecr_pull.arn
}

output "github_actions_deploy_role_arn" {
  description = "Role ARN for aws-actions/configure-aws-credentials in .github/workflows/aws-eks-deploy.yaml"
  value       = aws_iam_role.github_actions_deploy.arn
}

output "update_kubeconfig_command" {
  value = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
