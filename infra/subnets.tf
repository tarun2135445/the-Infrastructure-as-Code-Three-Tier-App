###############################################################################
# Subnets — three tiers per AZ.
#
#   public        : ALB, NAT Gateways. Has a route to the IGW.
#   private app   : ASG instances. Egress via NAT only.
#   private data  : RDS. No egress at all (RDS doesn't need the internet).
#
# Splitting app and data tiers means we can write a tight DB security group
# that only allows traffic from the app tier, not from anything in the VPC.
###############################################################################

resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${local.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_app_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-app-${local.azs[count.index]}"
    Tier = "app"
  }
}

resource "aws_subnet" "private_data" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_data_subnet_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${local.name_prefix}-data-${local.azs[count.index]}"
    Tier = "data"
  }
}
