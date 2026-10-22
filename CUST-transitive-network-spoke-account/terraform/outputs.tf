output "account_id" {
  description = "Spoke account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Home region of the SSM contract."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "spokes" {
  description = "Per-region spoke VPC details."
  value = {
    for region in var.spoke_regions : region => {
      vpc_id                        = aws_vpc.spoke[region].id
      vpc_cidr                      = aws_vpc.spoke[region].cidr_block
      private_subnet_ids            = [for key, s in aws_subnet.private : s.id if local.subnets[key].region == region]
      transit_subnet_ids            = [for key, s in aws_subnet.transit : s.id if local.subnets[key].region == region]
      private_route_table_id        = aws_route_table.private[region].id
      transit_gateway_id            = local.transit_gateway_ids[region]
      transit_gateway_attachment_id = aws_ec2_transit_gateway_vpc_attachment.spoke[region].id
      ipam_pool_id                  = local.environment_pool_ids[region]
    }
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
