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

variable "aws_account_id" {
  type        = string
  description = "AWS account ID that owns this infrastructure. TODO: fill in."
}

variable "region" {
  type        = string
  description = "AWS region for all resources"
  default     = "us-east-1"
}

variable "cluster_name" {
  type        = string
  description = "Name of the EKS cluster"
  default     = "online-boutique-production"
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version for the EKS control plane"
  default     = "1.30"
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for the VPC"
  default     = "10.42.0.0/16"
}

variable "azs" {
  type        = list(string)
  description = "Availability zones to spread subnets across (must be in var.region)"
  default     = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "private_subnet_cidrs" {
  type        = list(string)
  description = "Private subnet CIDRs, one per AZ (node groups / pods live here)"
  default     = ["10.42.0.0/19", "10.42.32.0/19", "10.42.64.0/19"]
}

variable "public_subnet_cidrs" {
  type        = list(string)
  description = "Public subnet CIDRs, one per AZ (ALB / NAT gateways live here)"
  default     = ["10.42.96.0/24", "10.42.97.0/24", "10.42.98.0/24"]
}

variable "single_nat_gateway" {
  type        = bool
  description = "If true, use one shared NAT gateway instead of one per AZ (cheaper, less resilient)"
  default     = false
}

variable "node_instance_types" {
  type        = list(string)
  description = "Instance types for the default managed node group"
  default     = ["m6i.large"]
}

variable "node_group_min_size" {
  type    = number
  default = 3
}

variable "node_group_max_size" {
  type    = number
  default = 9
}

variable "node_group_desired_size" {
  type    = number
  default = 3
}

variable "node_capacity_type" {
  type        = string
  description = "ON_DEMAND or SPOT"
  default     = "ON_DEMAND"
}

variable "ecr_repositories" {
  type        = list(string)
  description = "One ECR repository is created per microservice listed here. Must match the image names used by helm-chart/values.yaml and .github/workflows/aws-eks-deploy.yaml."
  default = [
    "adservice",
    "cartservice",
    "checkoutservice",
    "currencyservice",
    "emailservice",
    "frontend",
    "loadgenerator",
    "paymentservice",
    "productcatalogservice",
    "recommendationservice",
    "shippingservice",
    "shoppingassistantservice",
  ]
}

variable "eks_namespace" {
  type        = string
  description = "Kubernetes namespace the app + IRSA roles/service accounts target"
  default     = "default"
}

variable "external_dns_domain_filter" {
  type        = string
  description = "Route53 hosted zone / domain ExternalDNS is allowed to manage. TODO: fill in (e.g. example.com)."
  default     = ""
}

variable "tags" {
  type        = map(string)
  description = "Extra tags applied to all resources"
  default     = {}
}
