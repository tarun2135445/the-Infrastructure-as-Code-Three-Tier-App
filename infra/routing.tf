###############################################################################
# Route tables
#
# Public route table: 0.0.0.0/0 -> IGW. Shared across all public subnets.
# Private route tables: one per NAT Gateway, 0.0.0.0/0 -> NAT.
#   With single_nat_gateway=true there's one private RT and every private
#   subnet shares it. With it false, one RT per AZ so traffic stays in-AZ.
# The data tier reuses the app-tier RTs — same egress profile; the SG layer
# is what isolates them.
###############################################################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-rt-public"
  }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count = var.single_nat_gateway ? 1 : var.az_count

  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${local.name_prefix}-rt-private-${count.index + 1}"
  }
}

resource "aws_route" "private_nat" {
  count = var.single_nat_gateway ? 1 : var.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private_app" {
  count = var.az_count

  subnet_id = aws_subnet.private_app[count.index].id
  # When single_nat_gateway=true every subnet points at the same RT.
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}

resource "aws_route_table_association" "private_data" {
  count = var.az_count

  subnet_id      = aws_subnet.private_data[count.index].id
  route_table_id = aws_route_table.private[var.single_nat_gateway ? 0 : count.index].id
}
