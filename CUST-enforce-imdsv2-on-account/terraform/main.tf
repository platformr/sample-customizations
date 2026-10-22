# ------------------------------------------------------------------------------
# IMDSv2 account defaults + enforcement (per region)
#
# Terraform sets the account-level IMDS defaults for new instances:
#   HttpTokens = required (IMDSv2 only), HttpEndpoint = enabled, hop limit.
#
# The *enforcement* flag (HttpTokensEnforced) that makes IMDSv1 launches fail
# regardless of instance/AMI settings is not exposed by the provider as of
# v6.69, so post-api-helpers.sh sets it with
#   aws ec2 modify-instance-metadata-defaults --http-tokens-enforced enabled
# when var.enforce is true. The flag is handed off via SSM.
#
# Neither setting changes EXISTING instances.
# ------------------------------------------------------------------------------

resource "aws_ec2_instance_metadata_defaults" "this" {
  http_endpoint               = "enabled"
  http_tokens                 = "required"
  http_put_response_hop_limit = var.http_put_response_hop_limit
  instance_metadata_tags      = var.instance_metadata_tags
}

resource "aws_ssm_parameter" "enforce" {
  name        = "/platformr/${var.customization_name}/enforce"
  description = "Published by ${var.customization_name} for api_helpers: whether to enable HttpTokensEnforced."
  type        = "String"
  value       = tostring(var.enforce)

  depends_on = [aws_ec2_instance_metadata_defaults.this]
}
