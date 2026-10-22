# ------------------------------------------------------------------------------
# IPAM: cloud CIDR -> region pools -> environment pools
#
# Spokes allocate VPC CIDRs from the environment pools (shared via RAM). The
# region pools give each Transit Gateway a single summary route; the cloud
# pool is the one block to advertise on-premises.
# ------------------------------------------------------------------------------

resource "aws_vpc_ipam" "this" {
  description = "${var.name_prefix} IPAM"
  tier        = var.ipam_tier

  dynamic "operating_regions" {
    for_each = toset(distinct(concat([local.home_region], local.hub_region_names)))
    content {
      region_name = operating_regions.value
    }
  }

  tags = {
    Name = "${var.name_prefix}-ipam"
  }
}

# ---- Level 1: cloud ------------------------------------------------------------

resource "aws_vpc_ipam_pool" "cloud" {
  description    = "${var.name_prefix}: all cloud address space"
  address_family = "ipv4"
  ipam_scope_id  = aws_vpc_ipam.this.private_default_scope_id
  auto_import    = false

  tags = {
    Name = "${var.name_prefix}-cloud"
  }
}

resource "aws_vpc_ipam_pool_cidr" "cloud" {
  ipam_pool_id = aws_vpc_ipam_pool.cloud.id
  cidr         = var.cloud_cidr
}

# ---- Level 2: region -------------------------------------------------------------

resource "aws_vpc_ipam_pool" "region" {
  for_each = var.hub_regions

  description         = "${var.name_prefix}: ${each.key}"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  locale              = each.key
  source_ipam_pool_id = aws_vpc_ipam_pool.cloud.id
  auto_import         = false

  tags = {
    Name   = "${var.name_prefix}-${each.key}"
    region = each.key
  }
}

resource "aws_vpc_ipam_pool_cidr" "region" {
  for_each = var.hub_regions

  ipam_pool_id = aws_vpc_ipam_pool.region[each.key].id
  cidr         = each.value.cidr

  depends_on = [aws_vpc_ipam_pool_cidr.cloud]
}

# ---- Level 3: environment --------------------------------------------------------

resource "aws_vpc_ipam_pool" "environment" {
  for_each = local.environment_pools

  description         = "${var.name_prefix}: ${each.value.region} ${each.value.environment}"
  address_family      = "ipv4"
  ipam_scope_id       = aws_vpc_ipam.this.private_default_scope_id
  locale              = each.value.region
  source_ipam_pool_id = aws_vpc_ipam_pool.region[each.value.region].id
  auto_import         = false

  allocation_default_netmask_length = var.vpc_allocation_netmask.default
  allocation_min_netmask_length     = var.vpc_allocation_netmask.min
  allocation_max_netmask_length     = var.vpc_allocation_netmask.max

  tags = {
    Name        = "${var.name_prefix}-${each.value.region}-${each.value.environment}"
    region      = each.value.region
    environment = each.value.environment
  }
}

resource "aws_vpc_ipam_pool_cidr" "environment" {
  for_each = local.environment_pools

  ipam_pool_id = aws_vpc_ipam_pool.environment[each.key].id
  cidr         = each.value.cidr

  depends_on = [aws_vpc_ipam_pool_cidr.region]
}
