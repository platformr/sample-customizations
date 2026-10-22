# ------------------------------------------------------------------------------
# CUST-delete-default-vpcs: Terraform side
#
# All the work happens in api_helpers (pre deletes, post verifies). Terraform
# only records that the customization is applied to this account so other
# tooling can discover it:
#
#   /platformr/CUST-delete-default-vpcs/enabled  = "true"
#   /platformr/CUST-delete-default-vpcs/scope    = "all-enabled-regions"
#
# post-api-helpers.sh additionally writes last_validation* parameters under the
# same prefix (not managed by Terraform; removed by the helper on destroy).
# ------------------------------------------------------------------------------

locals {
  ssm_prefix = "/platformr/${var.customization_name}"
}

resource "aws_ssm_parameter" "enabled" {
  name        = "${local.ssm_prefix}/enabled"
  description = "True when ${var.customization_name} has been applied to this account (default VPCs removed in all enabled regions)."
  type        = "String"
  value       = "true"
}

resource "aws_ssm_parameter" "scope" {
  name        = "${local.ssm_prefix}/scope"
  description = "Region scope swept by ${var.customization_name}."
  type        = "String"
  value       = "all-enabled-regions"
}
