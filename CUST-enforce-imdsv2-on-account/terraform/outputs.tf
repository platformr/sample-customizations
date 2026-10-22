output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Region the IMDS defaults were set in."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "imds_defaults" {
  description = "Account-level IMDS defaults set by Terraform."
  value = {
    http_endpoint               = aws_ec2_instance_metadata_defaults.this.http_endpoint
    http_tokens                 = aws_ec2_instance_metadata_defaults.this.http_tokens
    http_put_response_hop_limit = aws_ec2_instance_metadata_defaults.this.http_put_response_hop_limit
    instance_metadata_tags      = aws_ec2_instance_metadata_defaults.this.instance_metadata_tags
    enforce                     = var.enforce
  }
}
