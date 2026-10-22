output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region the agreements were created in."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "enabled_model_ids" {
  description = "Base model IDs with foundation-model agreements."
  value       = sort(keys(aws_bedrock_foundation_model_agreement.model))
}

output "use_case_form_submitted" {
  description = "Whether this customization submitted the Anthropic use-case form."
  value       = var.submit_use_case_form
}

output "data_retention_mode" {
  description = "Data retention mode the post helper sets (null = untouched)."
  value       = var.data_retention_mode
}
