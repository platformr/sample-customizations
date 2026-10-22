# ------------------------------------------------------------------------------
# Multi-region transitive network hub (deploy to the organization's NETWORK
# account)
#
#   tgw.tf   one Transit Gateway per hub region, full-mesh inter-region peering
#            with static summary routes (transitive across regions)
#   ipam.tf  one IPAM (home region) with a 3-level pool hierarchy:
#            cloud CIDR -> region CIDR -> environment pools
#   ram.tf   Transit Gateways and environment pools shared to the organization
#   ssm.tf   SSM parameter contract for consumers in this account / pipelines
#
# Every hub region is handled with the provider's per-resource `region`
# argument (AWS provider >= 6), so adding a region is one map entry in
# var.hub_regions, not a new provider alias and a copy of the resources.
# ------------------------------------------------------------------------------

locals {
  account_id  = data.aws_caller_identity.current.account_id
  home_region = data.aws_region.current.region

  hub_region_names = sort(keys(var.hub_regions))

  # Share with explicit principals, or with the whole organization.
  ram_principals = length(var.ram_principals) > 0 ? var.ram_principals : [data.aws_organizations_organization.current.arn]

  # Environment pools: split each region CIDR into 2^bits equal blocks.
  env_bits = ceil(log(length(var.environments), 2))
  environment_pools = merge([
    for region, cfg in var.hub_regions : {
      for idx, env in var.environments : "${region}/${env}" => {
        region      = region
        environment = env
        cidr        = cidrsubnet(cfg.cidr, local.env_bits, idx)
      }
    }
  ]...)
}
