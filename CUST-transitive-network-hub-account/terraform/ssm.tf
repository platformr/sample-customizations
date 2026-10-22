# ------------------------------------------------------------------------------
# SSM parameter contract (home region) + a per-region convenience copy of the
# Transit Gateway identifiers. See README.md "SSM parameters".
# ------------------------------------------------------------------------------

locals {
  ssm_prefix = "/platformr/${var.customization_name}"

  ssm_tgw = merge([
    for region, tgw in aws_ec2_transit_gateway.hub : {
      "transit_gateway/${region}/id"             = tgw.id
      "transit_gateway/${region}/arn"            = tgw.arn
      "transit_gateway/${region}/asn"            = tostring(tgw.amazon_side_asn)
      "transit_gateway/${region}/route_table_id" = tgw.association_default_route_table_id
      "transit_gateway/${region}/ram_share_arn"  = aws_ram_resource_share.tgw[region].arn
      "transit_gateway/${region}/cidr"           = var.hub_regions[region].cidr
    }
  ]...)

  ssm_peering = {
    for key, att in aws_ec2_transit_gateway_peering_attachment.mesh :
    "transit_gateway/peering/${key}/attachment_id" => att.id
  }

  ssm_ipam_region = merge([
    for region, pool in aws_vpc_ipam_pool.region : {
      "ipam/pool/${region}/id"   = pool.id
      "ipam/pool/${region}/arn"  = pool.arn
      "ipam/pool/${region}/cidr" = var.hub_regions[region].cidr
    }
  ]...)

  ssm_ipam_environment = merge([
    for key, pool in aws_vpc_ipam_pool.environment : {
      "ipam/pool/${key}/id"   = pool.id
      "ipam/pool/${key}/arn"  = pool.arn
      "ipam/pool/${key}/cidr" = local.environment_pools[key].cidr
    }
  ]...)

  ssm_strings = merge(
    {
      "organization_arn"       = data.aws_organizations_organization.current.arn
      "home_region"            = local.home_region
      "cloud_cidr"             = var.cloud_cidr
      "ipam/id"                = aws_vpc_ipam.this.id
      "ipam/arn"               = aws_vpc_ipam.this.arn
      "ipam/private_scope_id"  = aws_vpc_ipam.this.private_default_scope_id
      "ipam/tier"              = var.ipam_tier
      "ipam/pool/cloud/id"     = aws_vpc_ipam_pool.cloud.id
      "ipam/pool/cloud/arn"    = aws_vpc_ipam_pool.cloud.arn
      "ipam/ram_share_arn"     = aws_ram_resource_share.ipam.arn
      "vpc_allocation_netmask" = "default=${var.vpc_allocation_netmask.default};min=${var.vpc_allocation_netmask.min};max=${var.vpc_allocation_netmask.max}"
    },
    local.ssm_tgw,
    local.ssm_peering,
    local.ssm_ipam_region,
    local.ssm_ipam_environment,
  )

  ssm_lists = {
    "hub_regions"    = local.hub_region_names
    "environments"   = var.environments
    "ram_principals" = local.ram_principals
  }
}

resource "aws_ssm_parameter" "string" {
  for_each = local.ssm_strings

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name}: network hub contract."
  type        = "String"
  value       = each.value
}

resource "aws_ssm_parameter" "list" {
  for_each = local.ssm_lists

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name}: network hub contract."
  type        = "StringList"
  value       = join(",", each.value)
}

# In-region copy so consumers in a hub region can find their local TGW without
# knowing the home region.
resource "aws_ssm_parameter" "regional_tgw" {
  for_each = var.hub_regions

  region = each.key

  name        = "${local.ssm_prefix}/transit_gateway_id"
  description = "Published by ${var.customization_name}: Transit Gateway serving this region."
  type        = "String"
  value       = aws_ec2_transit_gateway.hub[each.key].id
}
