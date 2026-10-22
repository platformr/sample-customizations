output "account_id" {
  description = "Network account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Home region (IPAM, IPAM RAM share, SSM contract)."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "organization_arn" {
  description = "Organization the hub is shared with (when ram_principals is empty)."
  value       = data.aws_organizations_organization.current.arn
}

output "transit_gateways" {
  description = "Per-region Transit Gateway details."
  value = {
    for region, tgw in aws_ec2_transit_gateway.hub : region => {
      id             = tgw.id
      arn            = tgw.arn
      asn            = tgw.amazon_side_asn
      route_table_id = tgw.association_default_route_table_id
      ram_share_arn  = aws_ram_resource_share.tgw[region].arn
    }
  }
}

output "transit_gateway_peering_attachments" {
  description = "Inter-region peering attachment IDs keyed by requester--accepter."
  value       = { for k, v in aws_ec2_transit_gateway_peering_attachment.mesh : k => v.id }
}

output "ipam" {
  description = "IPAM and pool hierarchy."
  value = {
    id               = aws_vpc_ipam.this.id
    private_scope_id = aws_vpc_ipam.this.private_default_scope_id
    cloud_pool_id    = aws_vpc_ipam_pool.cloud.id
    cloud_cidr       = var.cloud_cidr
    region_pools     = { for r, p in aws_vpc_ipam_pool.region : r => { id = p.id, cidr = var.hub_regions[r].cidr } }
    environment_pools = {
      for k, p in aws_vpc_ipam_pool.environment : k => { id = p.id, cidr = local.environment_pools[k].cidr }
    }
    ram_share_arn = aws_ram_resource_share.ipam.arn
  }
}

output "ssm_parameter_prefix" {
  description = "SSM prefix of the contract parameters (home region)."
  value       = local.ssm_prefix
}

output "ssm_parameter_names" {
  description = "All contract parameter names in the home region."
  value       = sort(concat([for p in aws_ssm_parameter.string : p.name], [for p in aws_ssm_parameter.list : p.name]))
}
