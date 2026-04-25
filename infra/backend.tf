# Remote state in S3 with DynamoDB locking.
#
# The bucket and table are created by ./bootstrap/ before this stack is
# initialized. Pass values at init time so the same code can be reused
# across environments without editing this file:
#
#   terraform init \
#     -backend-config="bucket=<state-bucket>" \
#     -backend-config="key=infra/terraform.tfstate" \
#     -backend-config="region=us-east-1" \
#     -backend-config="dynamodb_table=<lock-table>" \
#     -backend-config="encrypt=true"
#
# For local-only experimentation, comment this block out and Terraform
# will fall back to a local state file.
terraform {
  backend "s3" {}
}
