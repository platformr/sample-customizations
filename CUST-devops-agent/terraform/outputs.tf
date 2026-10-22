output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region the agent space lives in."
  value       = data.aws_region.current.region
}

output "agent_space_id" {
  description = "DevOps Agent agent space ID."
  value       = aws_devopsagent_agent_space.this.agent_space_id
}

output "agent_space_arn" {
  description = "DevOps Agent agent space ARN."
  value       = aws_devopsagent_agent_space.this.arn
}

output "agent_space_role_arn" {
  description = "Role the agent space assumes in this account."
  value       = aws_iam_role.agent_space.arn
}

output "operator_app_role_arn" {
  description = "Role the operator web app assumes."
  value       = aws_iam_role.operator_app.arn
}

output "ssm_parameter_prefix" {
  description = "SSM path under which hand-off values are published for the helpers."
  value       = local.ssm_prefix
}
