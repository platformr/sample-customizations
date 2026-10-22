# ------------------------------------------------------------------------------
# Wire the VPC into the hub: attach to the shared Transit Gateway and route the
# cloud CIDR (and optionally everything) through it. The hub auto-accepts the
# attachment and propagates the VPC CIDR into its default route table, so the
# VPC is reachable from every other spoke (in both hub regions) immediately.
# ------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway_vpc_attachment" "spoke" {
  for_each = toset(var.spoke_regions)

  region = each.key

  transit_gateway_id = local.transit_gateway_ids[each.key]
  vpc_id             = aws_vpc.spoke[each.key].id
  subnet_ids         = [for key, subnet in aws_subnet.transit : subnet.id if local.subnets[key].region == each.key]
  dns_support        = "enable"

  # Association/propagation are decided by the hub (default route table on).
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = {
    Name = "${var.name_prefix}-${var.environment}-${each.key}"
  }
}

resource "aws_route" "private_to_cloud" {
  for_each = toset(var.spoke_regions)

  region = each.key

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = var.cloud_cidr
  transit_gateway_id     = local.transit_gateway_ids[each.key]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_route" "transit_to_cloud" {
  for_each = toset(var.spoke_regions)

  region = each.key

  route_table_id         = aws_route_table.transit[each.key].id
  destination_cidr_block = var.cloud_cidr
  transit_gateway_id     = local.transit_gateway_ids[each.key]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}

resource "aws_route" "private_default" {
  for_each = var.route_default_via_transit_gateway ? toset(var.spoke_regions) : toset([])

  region = each.key

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  transit_gateway_id     = local.transit_gateway_ids[each.key]

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.spoke]
}
