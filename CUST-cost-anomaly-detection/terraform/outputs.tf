output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Provider region (Cost Explorer endpoint)."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "monitor_arn" {
  description = "ARN of the AWS-services anomaly monitor."
  value       = aws_ce_anomaly_monitor.services.arn
}

output "subscription_arn" {
  description = "ARN of the email alert subscription."
  value       = aws_ce_anomaly_subscription.email.arn
}

output "alert_email" {
  description = "Address receiving alerts."
  value       = var.alert_email
}
