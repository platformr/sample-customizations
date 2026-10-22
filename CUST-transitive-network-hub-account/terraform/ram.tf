# ------------------------------------------------------------------------------
# RAM shares
#   * one share per hub region for that region's Transit Gateway (RAM shares
#     are regional; the TGW must be shared from its own region)
#   * one share in the IPAM home region for all environment pools (IPAM pools
#     can only be shared from the IPAM home region)
# Principals default to the whole organization.
# ------------------------------------------------------------------------------

# ---- Transit Gateways ---------------------------------------------------------

resource "aws_ram_resource_share" "tgw" {
  for_each = var.hub_regions

  region = each.key

  name                      = "${var.name_prefix}-tgw-${each.key}"
  allow_external_principals = false

  tags = {
    Name = "${var.name_prefix}-tgw-${each.key}"
  }
}

resource "aws_ram_resource_association" "tgw" {
  for_each = var.hub_regions

  region = each.key

  resource_arn       = aws_ec2_transit_gateway.hub[each.key].arn
  resource_share_arn = aws_ram_resource_share.tgw[each.key].arn
}

resource "aws_ram_principal_association" "tgw" {
  for_each = {
    for pair in setproduct(local.hub_region_names, local.ram_principals) :
    "${pair[0]}/${pair[1]}" => { region = pair[0], principal = pair[1] }
  }

  region = each.value.region

  principal          = each.value.principal
  resource_share_arn = aws_ram_resource_share.tgw[each.value.region].arn
}

# ---- IPAM environment pools (home region only) --------------------------------

resource "aws_ram_resource_share" "ipam" {
  name                      = "${var.name_prefix}-ipam-pools"
  allow_external_principals = false

  tags = {
    Name = "${var.name_prefix}-ipam-pools"
  }
}

resource "aws_ram_resource_association" "ipam" {
  for_each = aws_vpc_ipam_pool.environment

  resource_arn       = each.value.arn
  resource_share_arn = aws_ram_resource_share.ipam.arn

  # A pool is only shareable once its CIDR is provisioned.
  depends_on = [aws_vpc_ipam_pool_cidr.environment]
}

resource "aws_ram_principal_association" "ipam" {
  for_each = toset(local.ram_principals)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.ipam.arn
}
