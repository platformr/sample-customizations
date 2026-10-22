output "account_id" {
  description = "Account this customization was applied to."
  value       = data.aws_caller_identity.current.account_id
}

output "region" {
  description = "Provider region (IAM itself is global)."
  value       = data.aws_region.current.region
}

output "partition" {
  description = "AWS partition (aws, aws-us-gov, aws-cn)."
  value       = data.aws_partition.current.partition
}

output "password_policy" {
  description = "Effective password policy values."
  value = {
    minimum_password_length        = aws_iam_account_password_policy.cis.minimum_password_length
    password_reuse_prevention      = aws_iam_account_password_policy.cis.password_reuse_prevention
    max_password_age               = aws_iam_account_password_policy.cis.max_password_age
    require_uppercase_characters   = aws_iam_account_password_policy.cis.require_uppercase_characters
    require_lowercase_characters   = aws_iam_account_password_policy.cis.require_lowercase_characters
    require_numbers                = aws_iam_account_password_policy.cis.require_numbers
    require_symbols                = aws_iam_account_password_policy.cis.require_symbols
    allow_users_to_change_password = aws_iam_account_password_policy.cis.allow_users_to_change_password
    hard_expiry                    = aws_iam_account_password_policy.cis.hard_expiry
  }
}
