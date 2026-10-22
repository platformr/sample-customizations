# ------------------------------------------------------------------------------
# SSM parameter contract for workloads deploying into these spoke VPCs.
# Home-region store keyed by region, plus an in-region copy of the basics.
# ------------------------------------------------------------------------------

locals {
  ssm_prefix = "/platformr/${var.customization_name}"

  ssm_strings = merge(
    {
      "environment"     = var.environment
      "cloud_cidr"      = var.cloud_cidr
      "hub_name_prefix" = var.hub_name_prefix
      "hub_home_region" = var.hub_home_region
    },
    merge([
      for region in var.spoke_regions : {
        "${region}/vpc_id"                        = aws_vpc.spoke[region].id
        "${region}/vpc_cidr"                      = aws_vpc.spoke[region].cidr_block
        "${region}/private_route_table_id"        = aws_route_table.private[region].id
        "${region}/transit_route_table_id"        = aws_route_table.transit[region].id
        "${region}/transit_gateway_id"            = local.transit_gateway_ids[region]
        "${region}/transit_gateway_attachment_id" = aws_ec2_transit_gateway_vpc_attachment.spoke[region].id
        "${region}/ipam_pool_id"                  = local.environment_pool_ids[region]
      }
    ]...)
  )

  ssm_lists = merge(
    { "regions" = var.spoke_regions },
    merge([
      for region in var.spoke_regions : {
        "${region}/availability_zones" = local.azs[region]
        "${region}/private_subnet_ids" = [for key, s in aws_subnet.private : s.id if local.subnets[key].region == region]
        "${region}/transit_subnet_ids" = [for key, s in aws_subnet.transit : s.id if local.subnets[key].region == region]
      }
    ]...)
  )
}

resource "aws_ssm_parameter" "string" {
  for_each = local.ssm_strings

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name}: spoke network contract."
  type        = "String"
  value       = each.value
}

resource "aws_ssm_parameter" "list" {
  for_each = local.ssm_lists

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name}: spoke network contract."
  type        = "StringList"
  value       = join(",", each.value)
}

# In-region copies so a workload in that region can find its VPC directly.
resource "aws_ssm_parameter" "regional_vpc_id" {
  for_each = toset(var.spoke_regions)

  region = each.key

  name        = "${local.ssm_prefix}/vpc_id"
  description = "Published by ${var.customization_name}: spoke VPC in this region."
  type        = "String"
  value       = aws_vpc.spoke[each.key].id
}

resource "aws_ssm_parameter" "regional_private_subnet_ids" {
  for_each = toset(var.spoke_regions)

  region = each.key

  name        = "${local.ssm_prefix}/private_subnet_ids"
  description = "Published by ${var.customization_name}: private subnets of the spoke VPC in this region."
  type        = "StringList"
  value       = join(",", [for key, s in aws_subnet.private : s.id if local.subnets[key].region == each.key])
}
