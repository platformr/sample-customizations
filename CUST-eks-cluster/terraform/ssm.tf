# ------------------------------------------------------------------------------
# SSM parameters: the contract for workloads that deploy onto this cluster.
#
# Any later customization or application pipeline can look these up instead of
# reading this Terraform state. Keep the keys stable; they are documented in
# README.md ("SSM parameters").
# ------------------------------------------------------------------------------

locals {
  ssm_prefix = "/platformr/${var.customization_name}"

  ssm_strings = {
    cluster_name                       = module.eks.cluster_name
    cluster_arn                        = module.eks.cluster_arn
    cluster_endpoint                   = module.eks.cluster_endpoint
    cluster_certificate_authority_data = module.eks.cluster_certificate_authority_data
    cluster_version                    = module.eks.cluster_version
    cluster_security_group_id          = module.eks.cluster_security_group_id
    node_security_group_id             = module.eks.node_security_group_id
    oidc_provider_arn                  = module.eks.oidc_provider_arn
    oidc_issuer_url                    = module.eks.cluster_oidc_issuer_url
    node_iam_role_arn                  = module.eks.node_iam_role_arn
    vpc_id                             = module.vpc.vpc_id
    vpc_cidr                           = module.vpc.vpc_cidr_block
    region                             = data.aws_region.current.region
    default_storage_class              = var.default_storage_class_name
    ingress_class_name                 = var.ingress_class_name
    ingress_scheme                     = var.ingress_scheme
    kubeconfig_command                 = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${data.aws_region.current.region}"
  }

  ssm_lists = {
    private_subnet_ids = module.vpc.private_subnets
    public_subnet_ids  = module.vpc.public_subnets
    availability_zones = local.azs
  }
}

resource "aws_ssm_parameter" "string" {
  for_each = local.ssm_strings

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name} for workloads deploying to the cluster."
  type        = "String"
  value       = each.value
}

resource "aws_ssm_parameter" "list" {
  for_each = local.ssm_lists

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name} for workloads deploying to the cluster."
  type        = "StringList"
  value       = join(",", each.value)
}
