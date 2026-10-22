# ------------------------------------------------------------------------------
# Hub discovery (read-only, via RAM)
#
# This customization depends on CUST-transitive-network-hub-account having
# been applied in the networking account. That is the one sanctioned
# cross-customization dependency in this repository; the hub's RAM share
# names and pool descriptions are the contract (see the hub README).
# ------------------------------------------------------------------------------

# Transit Gateway: the hub shares it with a RAM share named
# "<hub_name_prefix>-tgw-<region>" in that region.
data "aws_ram_resource_share" "tgw" {
  for_each = toset(var.spoke_regions)

  region = each.key

  name           = "${var.hub_name_prefix}-tgw-${each.key}"
  resource_owner = "OTHER-ACCOUNTS"
}

# IPAM pools: visible in the hub's home region; pick by locale + description.
data "aws_vpc_ipam_pools" "shared" {
  region = var.hub_home_region
}

locals {
  transit_gateway_ids = {
    for region, share in data.aws_ram_resource_share.tgw :
    region => element(split("/", one([for arn in share.resource_arns : arn if can(regex(":transit-gateway/", arn))])), 1)
  }

  environment_pool_ids = {
    for region in var.spoke_regions :
    region => try(one([
      for pool in data.aws_vpc_ipam_pools.shared.ipam_pools : pool.id
      if pool.locale == region && pool.description == "${var.hub_name_prefix}: ${region} ${var.environment}"
    ]), null)
  }
}
