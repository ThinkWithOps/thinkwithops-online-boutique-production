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
# Bootstrap module: creates the S3 bucket + DynamoDB lock table used as the
# remote state backend for the main terraform-aws/ configuration.
#
# Terraform backend blocks cannot reference input variables, so this state
# store must exist *before* `terraform init` is run in terraform-aws/. This
# bootstrap module intentionally has NO remote backend of its own -- run it
# once with local state, note the outputs, then wire them into
# terraform-aws/backend.tf.
#
# Usage:
#   cd terraform-aws/bootstrap
#   terraform init
#   terraform apply -var="bucket_name=online-boutique-production-tfstate" \
#                    -var="dynamodb_table_name=online-boutique-production-tf-lock"
#   terraform output

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type        = string
  description = "AWS region for the state bucket / lock table"
  default     = "us-east-1"
}

variable "bucket_name" {
  type        = string
  description = "Globally-unique S3 bucket name for Terraform remote state"
  default     = "online-boutique-production-tfstate"
}

variable "dynamodb_table_name" {
  type        = string
  description = "DynamoDB table used for Terraform state locking"
  default     = "online-boutique-production-tf-lock"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = var.bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = var.bucket_name
    Project     = "online-boutique-production"
    ManagedBy   = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name    = var.dynamodb_table_name
    Project = "online-boutique-production"
  }
}

output "state_bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "lock_table" {
  value = aws_dynamodb_table.tf_lock.name
}
