# ------------------------------------------------------------------------------
# Main resources for this customization.
#
# Guidelines (see /AGENTS.md for the full list):
#   * Keep everything self-contained: no remote state reads from other
#     customizations, no cross-customization dependencies.
#   * Use data.aws_caller_identity / data.aws_region instead of hard-coded IDs.
#   * Make resources safe to apply repeatedly to the same account.
#   * Anything Terraform cannot manage belongs in ../api_helpers.
# ------------------------------------------------------------------------------

# Example placeholder. Replace with real resources.
#
# resource "aws_ssm_parameter" "example" {
#   name  = "/platformr/${var.customization_name}/deployed"
#   type  = "String"
#   value = "true"
# }
