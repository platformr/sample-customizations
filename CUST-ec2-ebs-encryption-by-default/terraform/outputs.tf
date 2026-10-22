output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region encryption by default was enabled in."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "ebs_encryption_by_default" {
  description = "Whether encryption by default is enabled."
  value       = aws_ebs_encryption_by_default.this.enabled
}

output "default_kms_key_arn" {
  description = "Customer-managed default key if one was set, otherwise null (aws/ebs in use)."
  value       = var.default_kms_key_arn
}
