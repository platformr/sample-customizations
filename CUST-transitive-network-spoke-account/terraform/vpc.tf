# ------------------------------------------------------------------------------
# Spoke VPC per region
#
# CIDR comes from the hub's environment pool (IPAM allocates it). Layout for a
# /20 VPC with 2 AZs:
#   private workload subnets : /22 per AZ   (cidrsubnet(vpc, 2, az))
#   transit subnets          : /28 per AZ   (cidrsubnet(vpc, 8, 240 + az))
# Transit subnets hold only the Transit Gateway attachment ENIs, the AWS
# recommended pattern, and never host workloads.
# No internet gateway / NAT: egress is the hub's job (or add later).
# ------------------------------------------------------------------------------

locals {
  azs = {
    for region in var.spoke_regions :
    region => slice(data.aws_availability_zones.available[region].names, 0, var.availability_zone_count)
  }

  subnets = merge([
    for region in var.spoke_regions : {
      for index, az in local.azs[region] : "${region}/${index}" => {
        region = region
        az     = az
        index  = index
      }
    }
  ]...)
}

resource "aws_vpc" "spoke" {
  for_each = toset(var.spoke_regions)

  region = each.key

  ipv4_ipam_pool_id    = local.environment_pool_ids[each.key]
  ipv4_netmask_length  = var.vpc_netmask_length
  enable_dns_support   = true
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name        = "${var.name_prefix}-${var.environment}-${each.key}"
    environment = var.environment
  }

  lifecycle {
    precondition {
      condition     = local.environment_pool_ids[each.key] != null
      error_message = "No shared IPAM pool found in ${var.hub_home_region} with locale ${each.key} and description \"${var.hub_name_prefix}: ${each.key} ${var.environment}\". Is the hub applied, is this account in its RAM share, and do environment / hub_name_prefix / hub_home_region match?"
    }
  }
}

# Lock the default security group (no rules) so nothing uses it by accident.
resource "aws_default_security_group" "spoke" {
  for_each = toset(var.spoke_regions)

  region = each.key

  vpc_id = aws_vpc.spoke[each.key].id

  tags = {
    Name = "${var.name_prefix}-${var.environment}-${each.key}-default-locked"
  }
}

# ---- Subnets ------------------------------------------------------------------

resource "aws_subnet" "private" {
  for_each = local.subnets

  region = each.value.region

  vpc_id            = aws_vpc.spoke[each.value.region].id
  cidr_block        = cidrsubnet(aws_vpc.spoke[each.value.region].cidr_block, 2, each.value.index)
  availability_zone = each.value.az

  tags = {
    Name = "${var.name_prefix}-${var.environment}-private-${each.value.az}"
    tier = "private"
  }
}

resource "aws_subnet" "transit" {
  for_each = local.subnets

  region = each.value.region

  vpc_id            = aws_vpc.spoke[each.value.region].id
  cidr_block        = cidrsubnet(aws_vpc.spoke[each.value.region].cidr_block, 8, 240 + each.value.index)
  availability_zone = each.value.az

  tags = {
    Name = "${var.name_prefix}-${var.environment}-transit-${each.value.az}"
    tier = "transit-gateway"
  }
}

# ---- Route tables -------------------------------------------------------------

resource "aws_route_table" "private" {
  for_each = toset(var.spoke_regions)

  region = each.key

  vpc_id = aws_vpc.spoke[each.key].id

  tags = {
    Name = "${var.name_prefix}-${var.environment}-${each.key}-private"
  }
}

resource "aws_route_table_association" "private" {
  for_each = local.subnets

  region = each.value.region

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.value.region].id
}

resource "aws_route_table" "transit" {
  for_each = toset(var.spoke_regions)

  region = each.key

  vpc_id = aws_vpc.spoke[each.key].id

  tags = {
    Name = "${var.name_prefix}-${var.environment}-${each.key}-transit"
  }
}

resource "aws_route_table_association" "transit" {
  for_each = local.subnets

  region = each.value.region

  subnet_id      = aws_subnet.transit[each.key].id
  route_table_id = aws_route_table.transit[each.value.region].id
}
