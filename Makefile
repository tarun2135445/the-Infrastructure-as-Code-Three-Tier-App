###############################################################################
# Operator-friendly wrappers for the most common workflows.
#
#   make bootstrap     # one-time: create S3+DynamoDB state backend
#   make init          # wire infra/ to the backend
#   make plan          # what would change?
#   make apply         # ship it
#   make destroy       # tear it all down (no charges left running)
#   make fmt validate  # static checks (run before commit)
#   make hit           # curl the ALB once it's up
#   make ssm           # shell into a private instance via SSM
###############################################################################

REGION  ?= us-east-1
PROJECT ?= aws-portfolio
INFRA   := infra
BOOT    := bootstrap

# Resolve account-suffixed bucket name without hardcoding it.
ACCOUNT_ID = $(shell aws sts get-caller-identity --query Account --output text 2>/dev/null)
BUCKET     = $(PROJECT)-tfstate-$(ACCOUNT_ID)
LOCK_TABLE = $(PROJECT)-tfstate-locks

.PHONY: help bootstrap init plan apply destroy fmt validate hit ssm

help:
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Create the S3 bucket + DynamoDB lock table for remote state.
	cd $(BOOT) && terraform init && terraform apply -auto-approve

init: ## terraform init for the main stack with backend config.
	cd $(INFRA) && terraform init -reconfigure \
	  -backend-config="bucket=$(BUCKET)" \
	  -backend-config="key=infra/terraform.tfstate" \
	  -backend-config="region=$(REGION)" \
	  -backend-config="dynamodb_table=$(LOCK_TABLE)" \
	  -backend-config="encrypt=true"

plan: ## Show what would change.
	cd $(INFRA) && terraform plan -out plan.out

apply: ## Apply the most recent plan, or prompt if none.
	cd $(INFRA) && (test -f plan.out && terraform apply plan.out || terraform apply)

destroy: ## Tear it all down. Confirm before running in any shared account.
	cd $(INFRA) && terraform destroy

fmt: ## Reformat all .tf files in place.
	terraform fmt -recursive

validate: ## Static validation — no AWS calls.
	cd $(INFRA) && terraform init -backend=false -input=false >/dev/null && terraform validate
	cd $(BOOT)  && terraform init -backend=false -input=false >/dev/null && terraform validate

hit: ## curl the ALB and pretty-print the response.
	@URL=$$(cd $(INFRA) && terraform output -raw alb_dns_name); \
	echo "curl http://$$URL/"; \
	curl -fsS "http://$$URL/" | python3 -m json.tool

ssm: ## Open an SSM session to one of the running app instances.
	@CMD=$$(cd $(INFRA) && terraform output -raw ssm_session_command); \
	echo "$$CMD"; \
	eval "$$CMD"
