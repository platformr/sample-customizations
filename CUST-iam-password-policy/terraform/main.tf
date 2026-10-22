# ------------------------------------------------------------------------------
# IAM account password policy (CIS / Config rule IAM_PASSWORD_POLICY)
#
# One resource, account-wide. Re-applying with the same values is a no-op.
# `terraform destroy` deletes the policy, which puts the account back on the
# AWS default policy (NON_COMPLIANT for the Config rule).
# ------------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "cis" {
  minimum_password_length        = var.minimum_password_length
  password_reuse_prevention      = var.password_reuse_prevention
  max_password_age               = var.max_password_age
  require_uppercase_characters   = var.require_uppercase_characters
  require_lowercase_characters   = var.require_lowercase_characters
  require_numbers                = var.require_numbers
  require_symbols                = var.require_symbols
  allow_users_to_change_password = var.allow_users_to_change_password
  hard_expiry                    = var.hard_expiry
}
