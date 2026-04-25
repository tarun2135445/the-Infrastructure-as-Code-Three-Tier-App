###############################################################################
# VPC + Internet Gateway + (optional) NAT Gateway
#
# The VPC owns the address space; the IGW gives public subnets a route to
# the internet; the NAT Gateway gives private subnets *outbound-only*
# internet access (for OS updates, SSM, Secrets Manager, etc.) without
# exposing them to inbound traffic.
###############################################################################

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

# One Elastic IP per NAT Gateway. With single_nat_gateway=true that means
# one EIP total; otherwise one per AZ.
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : var.az_count
  domain = "vpc"

  # The IGW must exist before AWS will hand out an EIP that depends on it.
  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${local.name_prefix}-nat-eip-${count.index + 1}"
  }
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  depends_on = [aws_internet_gateway.this]

  tags = {
    Name = "${local.name_prefix}-nat-${count.index + 1}"
  }
}
