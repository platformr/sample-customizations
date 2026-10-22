# ------------------------------------------------------------------------------
# AWS DevOps Agent: agent space + hand-off to api_helpers
#
# Terraform manages:  IAM roles (iam.tf), the agent space (here), and SSM
#                     parameters that pass IDs/ARNs to post-api-helpers.sh.
# Helpers manage:     associating this AWS account with the agent space and
#                     enabling the operator app. The provider has no resources
#                     for those calls (AssociateService, EnableOperatorApp).
# ------------------------------------------------------------------------------

resource "aws_devopsagent_agent_space" "this" {
  name        = var.agent_space_name
  description = var.agent_space_description
  locale      = var.agent_space_locale
  kms_key_arn = var.kms_key_arn

  # The space must be able to assume its role as soon as it is used.
  depends_on = [
    aws_iam_role_policy_attachment.agent_space_access,
    aws_iam_role_policy.agent_space_slr,
  ]
}

# ---- Terraform -> helper hand-off --------------------------------------------
# Helpers never read Terraform state. Anything they need is published to SSM
# under /platformr/<customization>/ and read back with `aws ssm get-parameter`.

locals {
  ssm_prefix = "/platformr/${var.customization_name}"

  handoff = {
    agent_space_id         = aws_devopsagent_agent_space.this.agent_space_id
    agent_space_arn        = aws_devopsagent_agent_space.this.arn
    agent_space_role_arn   = aws_iam_role.agent_space.arn
    operator_app_role_arn  = aws_iam_role.operator_app.arn
    agent_space_region     = local.region
    agent_space_account_id = local.account_id
  }
}

resource "aws_ssm_parameter" "handoff" {
  for_each = local.handoff

  name        = "${local.ssm_prefix}/${each.key}"
  description = "Published by ${var.customization_name} for api_helpers."
  type        = "String"
  value       = each.value
}
