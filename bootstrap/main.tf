###############################################################################
# Bootstrap stack — creates the S3 bucket + DynamoDB table the main stack
# uses for remote state and locking.
#
# This stack uses LOCAL state by design: you can't store the state of the
# state backend in itself. Run it once, commit the bucket name, then point
# the main stack's backend at it via -backend-config flags.
###############################################################################

variable "project" {
  description = "Short project name."
  type        = string
  default     = "aws-portfolio"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "owner" {
  description = "Owner tag."
  type        = string
  default     = "platform"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      Owner     = var.owner
      ManagedBy = "terraform"
      Purpose   = "tfstate-backend"
    }
  }
}

data "aws_caller_identity" "current" {}

# Account-id-suffixed name keeps the bucket globally unique without forcing
# the user to invent one.
locals {
  bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "${var.project}-tfstate-locks"
}

resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  # Don't auto-destroy state buckets. If you really need to nuke it, run
  # `aws s3 rb --force` by hand and then `terraform destroy`.
  lifecycle {
    prevent_destroy = true
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
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket                  = aws_s3_bucket.tfstate.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tfstate_locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket" {
  value       = aws_s3_bucket.tfstate.bucket
  description = "Pass to `terraform init -backend-config=bucket=...`"
}

output "lock_table" {
  value       = aws_dynamodb_table.tfstate_locks.name
  description = "Pass to `terraform init -backend-config=dynamodb_table=...`"
}

output "init_command" {
  description = "Copy/paste this into infra/ to wire the backend."
  value = join(" ", [
    "terraform -chdir=../infra init",
    "-backend-config=bucket=${aws_s3_bucket.tfstate.bucket}",
    "-backend-config=key=infra/terraform.tfstate",
    "-backend-config=region=${var.region}",
    "-backend-config=dynamodb_table=${aws_dynamodb_table.tfstate_locks.name}",
    "-backend-config=encrypt=true",
  ])
}
