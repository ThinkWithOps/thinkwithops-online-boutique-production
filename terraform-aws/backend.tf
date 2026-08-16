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
# Remote state backend.
#
# NOTE: Terraform does not allow variables inside a `backend` block, so the
# bucket/table/region below must be filled in with literal values matching
# the outputs of terraform-aws/bootstrap (see that module's README/comments).
#
# Bootstrap first:
#   cd terraform-aws/bootstrap && terraform init && terraform apply
#
# Then fill in the values below (or pass via `-backend-config=` flags /
# a backend.hcl file) and run `terraform init` here.

terraform {
  backend "s3" {
    bucket         = "online-boutique-production-tfstate"
    key            = "online-boutique-production/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "online-boutique-production-tf-lock"
    encrypt        = true
  }
}
