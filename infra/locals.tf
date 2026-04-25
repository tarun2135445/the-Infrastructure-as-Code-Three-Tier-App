locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Owner       = var.owner
    ManagedBy   = "terraform"
  }

  # Pick the first N AZs in the region. Using AZ names (not IDs) so subnets
  # land where humans expect them in the console.
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # Three subnet tiers, each /24, derived from the VPC /16 with cidrsubnet().
  # Layout for vpc_cidr=10.0.0.0/16 and az_count=2:
  #   public  : 10.0.0.0/24, 10.0.1.0/24
  #   app     : 10.0.10.0/24, 10.0.11.0/24
  #   data    : 10.0.20.0/24, 10.0.21.0/24
  # The +offset keeps the tiers visually separated and leaves growing room
  # between them (handy when adding a new tier later without renumbering).
  public_subnet_cidrs       = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i)]
  private_app_subnet_cidrs  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 10)]
  private_data_subnet_cidrs = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 8, i + 20)]
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}
