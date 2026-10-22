# ------------------------------------------------------------------------------
# Transit Gateways: one per hub region
# ------------------------------------------------------------------------------

resource "aws_ec2_transit_gateway" "hub" {
  for_each = var.hub_regions

  region = each.key

  description     = "${var.name_prefix} transit gateway (${each.key})"
  amazon_side_asn = each.value.asn

  # Spokes attach from other accounts via the RAM share; accept them without a
  # manual step and put them on the default route table so everything is
  # transitive by default. Segment with extra route tables later if needed.
  auto_accept_shared_attachments  = "enable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = {
    Name = "${var.name_prefix}-${each.key}"
  }
}

# ---- Inter-region peering (full mesh) ----------------------------------------
# Peering attachments do not propagate routes; each side gets a static route
# for the peer region's summary CIDR, so any spoke in region A reaches any
# spoke in region B through the two hubs.

locals {
  # One attachment per unordered pair: the region earlier in sorted order is
  # the requester. (Terraform has no string "<", hence index comparison.)
  region_pairs = var.enable_transit_gateway_peering ? {
    for pair in setproduct(local.hub_region_names, local.hub_region_names) :
    "${pair[0]}--${pair[1]}" => { requester = pair[0], accepter = pair[1] }
    if index(local.hub_region_names, pair[0]) < index(local.hub_region_names, pair[1])
  } : {}

  peer_routes = merge(
    {
      for key, pair in local.region_pairs : "${key}/requester" => {
        pair   = key
        region = pair.requester
        dest   = var.hub_regions[pair.accepter].cidr
      }
    },
    {
      for key, pair in local.region_pairs : "${key}/accepter" => {
        pair   = key
        region = pair.accepter
        dest   = var.hub_regions[pair.requester].cidr
      }
    },
  )
}

resource "aws_ec2_transit_gateway_peering_attachment" "mesh" {
  for_each = local.region_pairs

  region = each.value.requester

  transit_gateway_id      = aws_ec2_transit_gateway.hub[each.value.requester].id
  peer_region             = each.value.accepter
  peer_transit_gateway_id = aws_ec2_transit_gateway.hub[each.value.accepter].id
  peer_account_id         = local.account_id

  tags = {
    Name = "${var.name_prefix}-${each.value.requester}-to-${each.value.accepter}"
  }
}

resource "aws_ec2_transit_gateway_peering_attachment_accepter" "mesh" {
  for_each = local.region_pairs

  region = each.value.accepter

  transit_gateway_attachment_id = aws_ec2_transit_gateway_peering_attachment.mesh[each.key].id

  tags = {
    Name = "${var.name_prefix}-${each.value.accepter}-from-${each.value.requester}"
  }
}

resource "aws_ec2_transit_gateway_route" "mesh" {
  for_each = local.peer_routes

  region = each.value.region

  destination_cidr_block         = each.value.dest
  transit_gateway_route_table_id = aws_ec2_transit_gateway.hub[each.value.region].association_default_route_table_id
  transit_gateway_attachment_id  = aws_ec2_transit_gateway_peering_attachment.mesh[each.value.pair].id

  # Routes over a peering only work once the accepter side has accepted.
  depends_on = [aws_ec2_transit_gateway_peering_attachment_accepter.mesh]
}
