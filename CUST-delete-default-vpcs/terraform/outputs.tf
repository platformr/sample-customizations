output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Provider region holding the SSM marker parameters."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "ssm_parameter_prefix" {
  description = "SSM prefix for the marker and validation parameters."
  value       = local.ssm_prefix
}
