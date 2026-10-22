output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region Transaction Search was enabled in."
  value       = data.aws_region.current.region
}

output "trace_segment_destination" {
  description = "Where X-Ray now sends trace segments (expected: CloudWatchLogs)."
  value       = aws_xray_trace_segment_destination.this.destination
}

output "indexing_percentage" {
  description = "Requested span indexing percentage."
  value       = var.indexing_percentage
}

output "logs_resource_policy_name" {
  description = "Name of the CloudWatch Logs resource policy granting X-Ray write access."
  value       = aws_cloudwatch_log_resource_policy.transaction_search.policy_name
}

output "agentcore_log_groups" {
  description = "Vended log groups created for AgentCore resources (if any)."
  value       = { for k, v in aws_cloudwatch_log_group.agentcore : k => v.name }
}
